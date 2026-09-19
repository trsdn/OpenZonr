import Foundation
import Testing
@testable import OpenZonrApp
@testable import OpenZonrCore
@testable import OpenZonrMac

/// Die eine Zusicherung, die der Bundle-Tausch braucht: vorher ist die eigene
/// Arbeit beendet.
///
/// Ein halb verschobenes Fenster ist der Schaden, um den es geht. Die
/// Fensterbeobachtung und der `PlacementScheduler` im ``WatchEngine`` halten
/// Aufträge, die erst laufen, wenn ihr Fenster erscheint — würden sie den Tausch
/// überleben, bewegte ein toter Prozess noch Fenster, oder ein neu gestarteter
/// bekäme einen Auftrag aus der Zeit davor. ``AppModel/installUpdate()`` hält
/// deshalb erst an und installiert dann.
///
/// Der echte Tausch ist hier nicht geprüft und kann es auch nicht sein: er
/// ersetzt das Bundle und startet den Prozess neu. Geprüft ist die Reihenfolge,
/// an der Naht ``AppModel/installAction``.
@Suite("AppModel — Anhalten vor dem Update-Tausch")
@MainActor
struct AppModelUpdateInstallTests {

    /// Steuerbare Berechtigung mit einem Engine-Start, der keine Beobachter an
    /// echte Apps hängt — dasselbe Muster wie in den übrigen App-Tests.
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

    /// Ein eigener Voreinstellungsbereich: der Schalter „Automatisch suchen“
    /// darf nicht in die Voreinstellungen des Rechners schreiben.
    private func scratchUpdates() -> UpdateManager {
        let suite = "openzonr-update-tests-\(UUID().uuidString)"
        return UpdateManager(defaults: UserDefaults(suiteName: suite) ?? .standard)
    }

    private func runningModel(_ stub: Stub) throws -> LoadedModel {
        let loaded = try AppModelFixtures.modelWithLoadedConfiguration(
            platform: stub.platform,
            updates: scratchUpdates()
        )
        loaded.model.refreshPermission(probe: true)
        #expect(loaded.model.windowAccess.isUsable)
        return loaded
    }

    @Test("Installiert wird erst, nachdem angehalten wurde")
    func stopsBeforeInstalling() async throws {
        let stub = Stub()
        let loaded = try runningModel(stub)
        let model = loaded.model
        let controller = model.dropzones
        let stopsBefore = controller._stopCountForTesting

        // Was die Attrappe im Moment des Installierens vorfindet, ist die
        // eigentliche Messung.
        var stoppedWhenInstalling: Bool?
        var dropzoneStopsWhenInstalling: Int?
        model.installAction = {
            stoppedWhenInstalling = model.isStoppedForUpdate
            dropzoneStopsWhenInstalling = controller._stopCountForTesting
            return true
        }

        let installed = await model.installUpdate()

        #expect(installed)
        #expect(stoppedWhenInstalling == true)
        #expect((dropzoneStopsWhenInstalling ?? 0) > stopsBefore)
    }

    @Test("Ohne Installation bleibt der Zustand unverändert angehalten")
    func neverInstallsWithoutStopping() async throws {
        let stub = Stub()
        let loaded = try runningModel(stub)
        let model = loaded.model

        var calls = 0
        model.installAction = {
            calls += 1
            #expect(model.isStoppedForUpdate)
            return true
        }

        _ = await model.installUpdate()
        #expect(calls == 1)
        // Erfolg heisst: der Prozess wird ersetzt. Dass hier nichts wieder
        // aufgenommen wird, ist Absicht.
        #expect(model.isStoppedForUpdate)
    }

    @Test("Scheitert der Tausch, läuft die Beobachtung weiter")
    func resumesAfterAFailedInstall() async throws {
        let stub = Stub()
        let loaded = try runningModel(stub)
        let model = loaded.model
        let controller = model.dropzones
        let startsBefore = controller._startCountForTesting
        let engineStartsBefore = stub.engineStarts

        model.installAction = { false }

        let installed = await model.installUpdate()

        #expect(!installed)
        #expect(!model.isStoppedForUpdate)
        #expect(controller._startCountForTesting > startsBefore)
        #expect(stub.engineStarts > engineStartsBefore)
    }

    @Test("Anhalten hält den Ziehen-Tracker an")
    func stopForUpdateStopsTheDragTracker() throws {
        let stub = Stub()
        let loaded = try runningModel(stub)
        let model = loaded.model
        let controller = model.dropzones
        let stopsBefore = controller._stopCountForTesting

        model.stopForUpdate()

        #expect(model.isStoppedForUpdate)
        #expect(controller._stopCountForTesting > stopsBefore)
        #expect(!controller._hasActiveTrackerForTesting)
    }
}
