import Foundation
import Testing
@testable import OpenZonrApp

/// Die reinen Entscheidungen rund um Updates.
///
/// Geprüft wird hier, was ohne Netz, ohne Bundle und ohne `AppUpdater`
/// entscheidbar ist: wann eine Suche fällig ist, was der Schalter voreingestellt
/// meldet und welcher Satz im Menü steht. Der Rest — Herunterladen, Prüfen,
/// Bundle-Tausch — bleibt „nicht gemessen": er lässt sich erst an einem echten
/// Release beobachten.
@Suite("Update — Fälligkeit, Voreinstellung und Menütext")
struct UpdatePolicyTests {

    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    // MARK: - Fälligkeit

    @Test("Ohne vorherige Suche ist sofort eine fällig")
    func dueWithoutPreviousCheck() {
        #expect(UpdatePolicy.isCheckDue(lastCheck: nil, now: now))
    }

    @Test("Innerhalb des Tages ist keine fällig")
    func notDueWithinTheDay() {
        let recent = now.addingTimeInterval(-UpdatePolicy.checkInterval + 1)
        #expect(!UpdatePolicy.isCheckDue(lastCheck: recent, now: now))
    }

    @Test("Genau nach einem Tag ist wieder eine fällig")
    func dueExactlyAfterTheInterval() {
        let aDayAgo = now.addingTimeInterval(-UpdatePolicy.checkInterval)
        #expect(UpdatePolicy.isCheckDue(lastCheck: aDayAgo, now: now))
    }

    /// Der Grund für das stündliche Aufwachen: ein Mac, der drei Tage schläft,
    /// überspringt keine Suche, er holt sie beim ersten Aufwachen nach.
    @Test("Eine lange Schlafphase führt zu genau einer fälligen Suche")
    func dueAfterALongSleep() {
        let threeDaysAgo = now.addingTimeInterval(-3 * UpdatePolicy.checkInterval)
        #expect(UpdatePolicy.isCheckDue(lastCheck: threeDaysAgo, now: now))
        #expect(UpdatePolicy.wakeInterval < UpdatePolicy.checkInterval)
    }

    // MARK: - Voreinstellung

    @Test("Ohne gespeicherten Wert ist das automatische Suchen an")
    func automaticChecksDefaultOn() {
        #expect(UpdatePolicy.automaticChecksEnabled(stored: nil))
    }

    @Test("Ein gespeichertes Aus bleibt aus")
    func storedFalseWins() {
        #expect(!UpdatePolicy.automaticChecksEnabled(stored: false))
    }

    @Test("Ein gespeichertes An bleibt an")
    func storedTrueWins() {
        #expect(UpdatePolicy.automaticChecksEnabled(stored: true))
    }

    /// Ein Fremdtyp unter demselben Schlüssel darf den Schalter nicht kippen:
    /// die Voreinstellung bleibt an.
    @Test("Ein unbrauchbarer gespeicherter Wert fällt auf die Voreinstellung zurück")
    func unusableStoredValueFallsBack() {
        #expect(UpdatePolicy.automaticChecksEnabled(stored: "vielleicht"))
    }

    // MARK: - Beschäftigt

    @Test("Laufende Vorgänge gelten als beschäftigt, ruhende nicht", arguments: [
        (UpdateState.idle, false),
        (UpdateState.checking, true),
        (UpdateState.upToDate, false),
        (UpdateState.downloading(version: "1.2.3"), true),
        (UpdateState.readyToInstall(version: "1.2.3"), false),
        (UpdateState.installing, true),
        (UpdateState.failed("Netzwerk"), false)
    ])
    func busyStates(state: UpdateState, expected: Bool) {
        #expect(UpdatePolicy.isBusy(state) == expected)
    }

    // MARK: - Menütext

    @Test("Ruhe sagt nichts")
    func idleHasNoLine() {
        #expect(UpdatePolicy.statusLine(for: .idle) == nil)
    }

    @Test("Ein bereitliegendes Update nennt seine Fassung")
    func readyStateNamesTheVersion() {
        let line = UpdatePolicy.statusLine(for: .readyToInstall(version: "0.2.0"))
        #expect(line == "Update 0.2.0 liegt bereit")
    }

    @Test("Ein Fehler wird beim Namen genannt")
    func failureShowsTheReason() {
        let line = UpdatePolicy.statusLine(for: .failed("Keine Verbindung"))
        #expect(line == "Update fehlgeschlagen: Keine Verbindung")
    }

    @Test("Jeder Zustand ausser Ruhe hat eine Zeile", arguments: [
        UpdateState.checking,
        UpdateState.upToDate,
        UpdateState.downloading(version: "0.2.0"),
        UpdateState.readyToInstall(version: "0.2.0"),
        UpdateState.installing,
        UpdateState.failed("x")
    ])
    func everyBusyStateSpeaks(state: UpdateState) {
        #expect(UpdatePolicy.statusLine(for: state)?.isEmpty == false)
    }

    @Test("Der Installieren-Knopf erscheint nur, wenn etwas bereitliegt")
    func installTitleOnlyWhenReady() {
        #expect(UpdatePolicy.installTitle(for: .readyToInstall(version: "0.2.0"))
            == "Installieren und neu starten (0.2.0)")
        #expect(UpdatePolicy.installTitle(for: .idle) == nil)
        #expect(UpdatePolicy.installTitle(for: .checking) == nil)
        #expect(UpdatePolicy.installTitle(for: .downloading(version: "0.2.0")) == nil)
        #expect(UpdatePolicy.installTitle(for: .installing) == nil)
        #expect(UpdatePolicy.installTitle(for: .failed("x")) == nil)
    }
}
