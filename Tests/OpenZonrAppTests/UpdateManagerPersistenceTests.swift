import Foundation
import Testing
@testable import OpenZonrApp

/// Was der ``UpdateManager`` über einen Neustart hinweg behalten muss.
///
/// Nichts hier geht ins Netz: geprüft ist nur, was in die Voreinstellungen
/// geschrieben und daraus gelesen wird. Das Suchen selbst bleibt ungemessen,
/// solange es kein Release gibt.
@Suite("UpdateManager — was die Voreinstellungen behalten")
@MainActor
struct UpdateManagerPersistenceTests {

    /// Ein eigener, leerer Voreinstellungsbereich je Test.
    private func scratch() -> (UserDefaults, String) {
        let suite = "openzonr-update-persistence-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            fatalError("Kein eigener Voreinstellungsbereich anlegbar.")
        }
        return (defaults, suite)
    }

    private func cleanUp(_ defaults: UserDefaults, _ suite: String) {
        defaults.removePersistentDomain(forName: suite)
    }

    /// Der Grund für das Sichern: ein Rechner wird neu gestartet. Läge der
    /// Zeitpunkt nur im Speicher, begänne jede Anmeldung mit einer fälligen
    /// Suche, und „höchstens einmal am Tag" wäre in Wahrheit „bei jedem Start".
    @Test("Der letzte Suchlauf überlebt ein neues Exemplar")
    func lastCheckSurvivesANewInstance() {
        let (defaults, suite) = scratch()
        defer { cleanUp(defaults, suite) }

        let first = UpdateManager(defaults: defaults)
        #expect(first.isAutomaticCheckDue)
        first.lastAutomaticCheck = Date()
        #expect(!first.isAutomaticCheckDue)

        let second = UpdateManager(defaults: defaults)
        #expect(second.lastAutomaticCheck != nil)
        #expect(!second.isAutomaticCheckDue)
    }

    @Test("Ein lange zurückliegender Suchlauf ist wieder fällig")
    func anOldCheckBecomesDueAgain() {
        let (defaults, suite) = scratch()
        defer { cleanUp(defaults, suite) }

        let manager = UpdateManager(defaults: defaults)
        manager.lastAutomaticCheck = Date(timeIntervalSinceNow: -2 * UpdatePolicy.checkInterval)
        #expect(manager.isAutomaticCheckDue)
    }

    @Test("Ein Zeitpunkt in der Zukunft — zurückgestellte Uhr — ist fällig")
    func aFutureStampIsDue() {
        let (defaults, suite) = scratch()
        defer { cleanUp(defaults, suite) }

        let manager = UpdateManager(defaults: defaults)
        manager.lastAutomaticCheck = Date(timeIntervalSinceNow: UpdatePolicy.checkInterval)
        #expect(manager.isAutomaticCheckDue)
    }

    @Test("Der Schalter ist voreingestellt an und wird gesichert")
    func theToggleIsStored() {
        let (defaults, suite) = scratch()
        defer { cleanUp(defaults, suite) }

        let first = UpdateManager(defaults: defaults)
        #expect(first.automaticChecksEnabled)

        first.automaticChecksEnabled = false
        #expect(!UpdateManager(defaults: defaults).automaticChecksEnabled)

        first.automaticChecksEnabled = true
        #expect(UpdateManager(defaults: defaults).automaticChecksEnabled)
        first.stopAutomaticChecks()
    }
}
