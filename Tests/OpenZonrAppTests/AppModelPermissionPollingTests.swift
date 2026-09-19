import Foundation
import Testing
@testable import OpenZonrApp
@testable import OpenZonrCore
@testable import OpenZonrMac

/// Der Berechtigungs-Timer feuert alle zwei Sekunden. Ein Tick ohne Änderung
/// darf den Ziehen-Tracker nicht anfassen: ein Neustart verwirft die laufende
/// Geste und blendet das Overlay aus (Issue #44).
@Suite("AppModel — Berechtigungsabfrage und Ziehen-Tracker")
@MainActor
struct AppModelPermissionPollingTests {

    /// Steuerbare Berechtigung. Der Fake-Start des Engines verhindert, dass
    /// Beobachter an echte, laufende Apps gehängt werden.
    @MainActor
    final class Stub {
        var trusted = true
        var access: Accessibility.WindowAccess = .granted
        var engineStarts = 0

        var platform: AppModel.Platform {
            AppModel.Platform(
                isTrusted: { self.trusted },
                probeWindowAccess: { self.trusted ? self.access : .notTrusted },
                startEngine: { _ in self.engineStarts += 1 }
            )
        }
    }

    private func usableModel(_ stub: Stub) throws -> LoadedModel {
        let loaded = try AppModelFixtures.modelWithLoadedConfiguration(platform: stub.platform)
        loaded.model.refreshPermission(probe: true)  // Erst-Erteilung: darf starten
        #expect(loaded.model.windowAccess.isUsable)
        return loaded
    }

    @Test("Unveränderte Abfragen lassen den Tracker in Ruhe")
    func unchangedPollsDoNotRestartTracker() throws {
        let stub = Stub()
        let loaded = try usableModel(stub)
        let controller = loaded.model.dropzones
        let startsBefore = controller._startCountForTesting
        let stopsBefore = controller._stopCountForTesting

        for _ in 0..<5 { loaded.model.refreshPermission(probe: false) }

        #expect(controller._startCountForTesting == startsBefore)
        #expect(controller._stopCountForTesting == stopsBefore)
        #expect(loaded.model.windowAccess.isUsable)
    }

    @Test("Auch eine ausdrückliche Prüfung ohne Änderung startet nicht neu")
    func unchangedProbeDoesNotRestartTracker() throws {
        let stub = Stub()
        let loaded = try usableModel(stub)
        let controller = loaded.model.dropzones
        let startsBefore = controller._startCountForTesting

        loaded.model.refreshPermission(probe: true)

        #expect(controller._startCountForTesting == startsBefore)
    }

    @Test("Verlust hält den Tracker an, Rückkehr startet ihn genau einmal")
    func lossSuspendsAndRecoveryRestoresOnce() throws {
        let stub = Stub()
        let loaded = try usableModel(stub)
        let controller = loaded.model.dropzones

        let stopsBeforeLoss = controller._stopCountForTesting
        let startsBeforeLoss = controller._startCountForTesting
        stub.trusted = false
        loaded.model.refreshPermission(probe: false)
        loaded.model.refreshPermission(probe: false)  // zweiter Tick: nichts Neues
        #expect(controller._stopCountForTesting == stopsBeforeLoss + 1)
        #expect(controller._startCountForTesting == startsBeforeLoss)
        #expect(loaded.model.status == .needsPermission)

        stub.trusted = true
        loaded.model.refreshPermission(probe: false)
        loaded.model.refreshPermission(probe: false)
        #expect(controller._startCountForTesting == startsBeforeLoss + 1)
        #expect(loaded.model.windowAccess.isUsable)
    }

    @Test("Neuladen der Konfiguration startet den Tracker weiterhin neu")
    func reloadStillRestartsTracker() throws {
        let stub = Stub()
        let loaded = try usableModel(stub)
        let controller = loaded.model.dropzones
        let startsBefore = controller._startCountForTesting

        loaded.model.reloadConfiguration()

        #expect(controller._startCountForTesting == startsBefore + 1)
    }
}
