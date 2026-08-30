import Foundation
import Testing
@testable import OpenZonrApp
@testable import OpenZonrCore

/// Ziehen muss aufhören, wenn der Nutzer pausiert — auf **allen** Wegen. Der
/// tatsächliche Mechanismus, mit dem `DropzoneController` das sicherstellt, ist
/// eine einzige frühe Rückkehr in ``DropzoneController.start()``:
/// `DropzoneActivator.suspension` sagt, ob überhaupt gehorcht werden darf, und
/// wenn nicht, wird kein Event-Tap installiert. Damit sind Overlay, Drop und
/// Angebot in derselben Bewegung stillgelegt: der Rückruf, an dem alle drei
/// hängen, wird erst gar nicht aufgeschaltet.
///
/// Was hier geprüft wird: nach dem Start ist kein Tracker installiert und die
/// Menüzeile hat den erwarteten Satz. Was hier **nicht** geprüft werden kann,
/// ist der pathologische Fall, dass der Rückruf trotzdem feuert — dafür
/// müsste ein Ereignis aus einem CGEventTap kommen, den es in der Testumgebung
/// nicht gibt. Ein Regressionstest über echte Ereignisse gehört, wenn er
/// gebaut wird, nach Core oder Mac (siehe `DropzoneActivator`).
@Suite("DropzoneController — Pause und Aus")
@MainActor
struct DropzoneControllerSuspensionTests {

    @Test("Aus in der Konfiguration: kein Tracker, keine Menüzeile")
    func switchedOffLeavesNoTrackerAndNoLine() throws {
        var configuration = AppModelFixtures.minimalConfiguration()
        configuration.defaults.dropzones.enabled = false
        let loaded = try AppModelFixtures.modelWithLoadedConfiguration(configuration)
        let controller = loaded.model.dropzones

        controller.start()

        // Der Aus-Fall bekommt keinen sichtbaren Satz: darüber steht schon
        // der Umschalter, der genau das sagt. Zwei Sätze wären Lärm.
        #expect(controller.problem == nil)
        #expect(controller._hasActiveTrackerForTesting == false)
    }

    @Test("Pausiert: kein Tracker, aber die Menüzeile erklärt es")
    func pausedLeavesNoTrackerButExplains() throws {
        var configuration = AppModelFixtures.minimalConfiguration()
        configuration.defaults.dropzones.enabled = true
        let loaded = try AppModelFixtures.modelWithLoadedConfiguration(configuration)
        let model = loaded.model
        // `isPaused` ruft `dropzones.restart()` selbst — genau der Pfad, an
        // dem der Fund aus PR #15 lag.
        model.isPaused = true
        let controller = model.dropzones

        // Nach dem Umschalten hat `restart()` bereits gelaufen. Der Zustand
        // muss stehen; ein zusätzliches `start()` würde nichts verändern.
        #expect(controller.problem == DropzoneSuspension.paused.explanation)
        #expect(controller._hasActiveTrackerForTesting == false)
    }

    @Test("Aus und pausiert: Aus-Zustand bleibt sichtbar, kein Tracker")
    func switchedOffAndPausedStillLeavesNoTracker() throws {
        var configuration = AppModelFixtures.minimalConfiguration()
        configuration.defaults.dropzones.enabled = false
        let loaded = try AppModelFixtures.modelWithLoadedConfiguration(configuration)
        let model = loaded.model
        model.isPaused = true
        let controller = model.dropzones

        // `DropzoneActivator.suspension` reiht die Zustände: `switchedOff`
        // schlägt `paused`. Der Test hält diese Reihenfolge fest, weil sie
        // aussen sichtbar ist.
        #expect(controller.problem == nil)
        #expect(controller._hasActiveTrackerForTesting == false)
    }
}
