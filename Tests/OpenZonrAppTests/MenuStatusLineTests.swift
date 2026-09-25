import Testing
@testable import OpenZonrApp
@testable import OpenZonrCore

/// Die Kopfzeile und die eine Zustandszeile des Menüs.
///
/// Sie sind der Grund für den ganzen Umbau: bisher stand dort ein Zustandsname
/// aus dem Programm plus ein Detail („Kein Profil passt — 2 Profile in der
/// Konfiguration“), was beschreibt, aber nicht sagt, was los ist. Die Sätze
/// hier stehen einzeln, weil eine `MenuBarExtra` sich nicht aufklappen und
/// ablesen lässt — geprüft wird die Entscheidung, nicht ihre Anzeige.
@Suite("Menü — Kopfzeile und Zustandszeile")
struct MenuStatusLineTests {

    @Test("Die Kopfzeile trägt die Fassung")
    func headerWithVersion() {
        #expect(MenuStatus.header(version: "0.1.1") == "OpenZonr 0.1.1")
    }

    @Test("Ohne Bundle steht nur der Name — keine erfundene Nummer")
    func headerWithoutVersion() {
        #expect(MenuStatus.header(version: nil) == "OpenZonr")
        #expect(MenuStatus.header(version: "") == "OpenZonr")
    }

    @Test("Der unersetzte Platzhalter aus der Info.plist zählt nicht als Fassung")
    func headerWithPlaceholder() {
        #expect(MenuStatus.header(version: "__VERSION__") == "OpenZonr")
    }

    @Test("Fehlender Zugriff sagt, was ohne ihn nicht geht, und bietet genau einen Knopf")
    func needsPermission() {
        let line = MenuStatus.line(status: .needsPermission, profileName: nil, isPaused: false, hasProblem: false)
        #expect(line.title == "Access is missing — without it OpenZonr cannot move windows")
        #expect(line.action == .grantAccess)
        #expect(line.action?.title == "Grant Access …")
    }

    @Test("Noch nichts eingerichtet und „nicht lesbar“ sind zwei verschiedene Lagen")
    func needsConfiguration() {
        let fresh = MenuStatus.line(status: .needsConfiguration, profileName: nil, isPaused: false, hasProblem: false)
        #expect(fresh.title == "Nothing set up yet")
        #expect(fresh.action == .explain)

        let broken = MenuStatus.line(status: .needsConfiguration, profileName: nil, isPaused: false, hasProblem: true)
        #expect(broken.title == "The settings cannot be read")
        #expect(broken.action == .explain)
    }

    @Test("Kein passendes Setup bietet einen Weg an, statt nur zu melden")
    func noProfile() {
        let line = MenuStatus.line(status: .noProfile, profileName: nil, isPaused: false, hasProblem: false)
        #expect(line.title == "No setup matches the connected screens")
        #expect(line.action?.title == "What to Do? …")
    }

    @Test("Pausiert sagt, was das heisst, und braucht keinen Knopf")
    func paused() {
        let line = MenuStatus.line(status: .paused, profileName: "Schreibtisch", isPaused: true, hasProblem: false)
        #expect(line.title == "Paused — nothing is placed automatically")
        #expect(line.action == nil)
    }

    @Test("Bereit nennt das Setup beim Namen")
    func active() {
        let line = MenuStatus.line(status: .active, profileName: "Schreibtisch", isPaused: false, hasProblem: false)
        #expect(line.title == "Ready — Setup “Schreibtisch”")
        #expect(line.action == nil)
    }

    @Test("Bereit ohne Namen bleibt ein ganzer Satz")
    func activeWithoutName() {
        #expect(
            MenuStatus.line(status: .active, profileName: nil, isPaused: false, hasProblem: false).title == "Ready"
        )
        #expect(
            MenuStatus.line(status: .active, profileName: "", isPaused: false, hasProblem: false).title == "Ready"
        )
    }

    @Test("Die Pause schlägt durch, auch wenn der Zustand sie noch nicht kennt")
    func pausedWinsOverActive() {
        let line = MenuStatus.line(status: .active, profileName: "Schreibtisch", isPaused: true, hasProblem: false)
        #expect(line.title == "Paused — nothing is placed automatically")
    }

    // MARK: - Update-Block

    @Test("Laufende und gescheiterte Updates haben eine Oberfläche, auch ohne Knopf")
    func bannerShowsLineWithoutButton() {
        // Der Fehler, den das verhindert: die Zustandszeile stand innerhalb der
        // Bedingung „es gibt einen Installieren-Knopf". Ein im Hintergrund
        // gescheiterter Versuch hatte danach gar keine Oberfläche mehr — er
        // meldet sich nirgends sonst.
        for state: UpdateState in [
            .checking, .downloading(version: "0.2.0"), .installing, .failed("Netz weg")
        ] {
            let banner = MenuStatus.updateBanner(for: state)
            #expect(banner.isVisible, "\(state) braucht eine Zeile")
            #expect(banner.line == UpdatePolicy.statusLine(for: state))
            #expect(banner.installTitle == nil)
        }
    }

    @Test("Ein bereitliegendes Update bringt Zeile und Knöpfe")
    func bannerShowsLineAndButtons() {
        let banner = MenuStatus.updateBanner(for: .readyToInstall(version: "0.2.0"))
        #expect(banner.line == "Update 0.2.0 is ready")
        #expect(banner.installTitle == "Install and Relaunch (0.2.0)")
    }

    @Test("Nichts los heisst nichts im Menü; „aktuell“ bleibt sichtbar wie bisher")
    func bannerIdleAndUpToDate() {
        #expect(MenuStatus.updateBanner(for: .idle).isVisible == false)
        // Unverändertes Verhalten aus der alten Fassung: nach einer Suche ohne
        // Fund steht die Zeile da.
        #expect(MenuStatus.updateBanner(for: .upToDate).line == "OpenZonr is up to date")
        #expect(MenuStatus.updateBanner(for: .upToDate).installTitle == nil)
    }
}
