import Foundation
import Observation
import Testing
@testable import OpenZonrApp
@testable import OpenZonrMac

/// Issue #66: „Mehr" schloss sich, wenn man mit der Maus in ein Untermenü
/// wechselte — beim Nutzer **immer**, nach rund einer Sekunde. Verschachtelte
/// `Menu`-Views waren ein Teil des Bildes, aber nicht die ganze Ursache: die
/// eigentliche fand sich in `syncFromEngine()`, das der Berechtigungs-Timer
/// alle zwei Sekunden aufruft. `@Observable`s generierte Setter benachrichtigen
/// bei jeder Zuweisung, auch bei derselben Wert — ohne Gleichheitsprüfung. Eine
/// unbedingte Neuzuweisung von `profileState`, `records` und
/// `observedApplications` bei jedem Tick zwang SwiftUI, den Menü-Inhalt im
/// selben Takt neu aufzubauen — auch während ein Untermenü offen war.
///
/// Geprüft wird hier nicht das Menü selbst (SwiftUI-Ansichten lassen sich
/// headless nicht auf Hover-Verhalten prüfen), sondern die Beobachtung: löst
/// ein wiederholter Sync mit unveränderten Werten eine Änderungsmeldung aus?
@Suite("AppModel — Engine-Sync und Beobachtung (#66)")
@MainActor
struct AppModelEngineSyncObservationTests {

    /// `withObservationTracking`s `onChange` ist `@Sendable` und kann auf
    /// einem beliebigen Thread laufen — eine einfache `var` lässt sich dort
    /// nicht mutieren. Diese Box ist der übliche Ausweg für genau diesen Test.
    private final class ChangeFlag: @unchecked Sendable {
        var fired = false
    }

    private func matchedState() throws -> WatchEngine.ProfileState {
        let configuration = AppModelFixtures.minimalConfiguration()
        let profile = try #require(configuration.profiles.first)
        return .matched(profile)
    }

    @Test("Ein Sync mit unveränderten Werten löst keine Beobachtung aus")
    func unchangedSyncFiresNoObservation() throws {
        let loaded = try AppModelFixtures.modelWithLoadedConfiguration(AppModelFixtures.minimalConfiguration())
        let model = loaded.model
        let state = try matchedState()

        // Ausgangswert setzen — das erste Mal zählt nicht mit.
        model._applyEngineSyncForTesting(profileState: state, records: [], observedApplications: 3)

        let flag = ChangeFlag()
        withObservationTracking {
            _ = model.profileState
            _ = model.records
            _ = model.observedApplications
        } onChange: {
            flag.fired = true
        }

        // Derselbe Zustand, wie ihn ein unveränderter Timer-Tick liefern würde.
        model._applyEngineSyncForTesting(profileState: state, records: [], observedApplications: 3)

        #expect(flag.fired == false)
    }

    @Test("Ein echter Wechsel wird weiterhin übernommen und gemeldet")
    func changedSyncStillFiresObservationAndApplies() throws {
        let loaded = try AppModelFixtures.modelWithLoadedConfiguration(AppModelFixtures.minimalConfiguration())
        let model = loaded.model
        let state = try matchedState()
        model._applyEngineSyncForTesting(profileState: state, records: [], observedApplications: 3)

        let flag = ChangeFlag()
        withObservationTracking {
            _ = model.observedApplications
        } onChange: {
            flag.fired = true
        }

        model._applyEngineSyncForTesting(profileState: state, records: [], observedApplications: 4)

        #expect(flag.fired == true)
        #expect(model.observedApplications == 4)
    }
}
