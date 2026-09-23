import CoreGraphics
import Foundation
import Testing

@testable import OpenZonrCore
@testable import OpenZonrMac

/// Belege für den Schutz aus Issue #69: **welcher Prozess** den Punkt besitzt,
/// wird beim Fenster-Server erfragt — nicht bei AppKit.
///
/// Der Absturz, den diese Tests absichern, hat eine Bedingung, die nichts mit
/// Geometrie zu tun hat: `AXUIElementCopyElementAtPosition` auf dem
/// *systemweiten* Element wird **im eigenen Prozess** bedient, sobald der Punkt
/// auf einem eigenen Element liegt. AppKit führt den Treffertest dann auf dem
/// **aufrufenden** Thread aus — bei uns ein Hintergrund-Thread — während der
/// Hauptthread denselben Bedienungshilfen-Code für dasselbe Statuselement
/// durchläuft. `NSAccessibility` ist hauptthread-gebunden; seine Attributlisten
/// sind gewöhnliche `NSMutableDictionary`. In allen vier Absturzberichten
/// (22.09. 09:42, 21:01, 21:29 und 23.09. 08:51) stehen genau diese zwei
/// Threads gleichzeitig in diesem Code.
///
/// Deshalb prüft ``CoreGraphicsWindowIndex/ownerOfOrdinaryWindow(at:in:excluding:)``
/// **vor** jedem AX-Aufruf, wem der Punkt gehört. Der Test dafür braucht keinen
/// Fenster-Server: die Entscheidung ist eine reine Funktion über die Liste, die
/// `CGWindowListCopyWindowInfo` liefert.
@Suite("Fenster-Besitzer unter einem Punkt")
struct WindowOwnerLookupTests {

    private static let ownPID: pid_t = 4242
    private static let otherPID: pid_t = 99

    /// `CGWindowListCopyWindowInfo` liefert die Liste von vorne nach hinten;
    /// die Reihenfolge der Einträge ist hier also die Stapelreihenfolge.
    private func entry(
        layer: Int,
        bounds: CGRect,
        pid: pid_t
    ) -> CoreGraphicsWindowIndex.Entry {
        CoreGraphicsWindowIndex.Entry(
            layer: layer,
            bounds: bounds,
            title: nil,
            ownerName: nil,
            ownerPID: pid
        )
    }

    @Test("Gewöhnliches Fenster einer fremden App: dessen Prozess wird gemeldet")
    func ordinaryForeignWindowIsReported() {
        let entries = [
            entry(layer: 0, bounds: CGRect(x: 0, y: 100, width: 800, height: 600), pid: Self.otherPID)
        ]

        let owner = CoreGraphicsWindowIndex.ownerOfOrdinaryWindow(
            at: CGPoint(x: 400, y: 300), in: entries, excluding: Self.ownPID
        )

        #expect(owner == Self.otherPID)
    }

    /// Der Absturzpfad selbst — und die Zusage, die ihn schliesst.
    ///
    /// Die Zusage ist **nicht** „über dem eigenen Statuselement wird gar nichts
    /// abgefragt“, sondern die engere und einzig nötige: der AX-Aufruf richtet
    /// sich **nie an den eigenen Prozess**. Nur dann bedient AppKit ihn im
    /// eigenen Prozess auf dem aufrufenden Thread, und nur daraus entsteht das
    /// Wettrennen aus #69. Ein Ziel-PID einer fremden App ist Mach-IPC; unser
    /// AppKit kommt dabei nicht vor.
    ///
    /// Liegt unter dem Symbol ein fremdes Fenster, wird also dieses gemeldet.
    /// Das ist harmlos: die fremde App antwortet auf einen Punkt über ihrer
    /// Titelleiste, ihr Rahmen bewegt sich nicht, es gibt keinen Beleg und damit
    /// kein `.began` (#37).
    @Test("Über dem eigenen Statuselement wird nie der eigene Prozess abgefragt")
    func lookupNeverTargetsOwnProcess() {
        let entries = [
            entry(layer: 25, bounds: CGRect(x: 380, y: 0, width: 40, height: 24), pid: Self.ownPID),
            entry(layer: 0, bounds: CGRect(x: 0, y: 0, width: 800, height: 600), pid: Self.otherPID)
        ]

        let owner = CoreGraphicsWindowIndex.ownerOfOrdinaryWindow(
            at: CGPoint(x: 400, y: 12), in: entries, excluding: Self.ownPID
        )

        #expect(owner != Self.ownPID)
        #expect(owner == Self.otherPID)
    }

    /// Dasselbe ohne fremdes Fenster darunter: dann bleibt nichts zu fragen.
    @Test("Eigenes Statuselement ohne fremdes Fenster darunter: keine Abfrage")
    func ownStatusItemAloneYieldsNothing() {
        let entries = [
            entry(layer: 25, bounds: CGRect(x: 380, y: 0, width: 40, height: 24), pid: Self.ownPID)
        ]

        #expect(CoreGraphicsWindowIndex.ownerOfOrdinaryWindow(
            at: CGPoint(x: 400, y: 12), in: entries, excluding: Self.ownPID
        ) == nil)
    }

    /// Der Fall, an dem der geometrische Schutz aus PR #70 vorbeiging: dessen
    /// Prüfung war `y >= 0 && y < thickness` in globalen Koordinaten und
    /// deckte damit nur die Menüleiste des **Hauptbildschirms** ab. Auf einem
    /// Bildschirm unterhalb des Hauptbildschirms liegt die Menüleiste bei
    /// `y = 1440…1464`, auf einem darüber bei negativem `y`. Beides fiel durch.
    @Test("Menüleiste eines Nebenbildschirms: keine Abfrage, egal bei welchem y")
    func menuBarOnSecondaryDisplayIsRejected() {
        let below = [
            entry(layer: 24, bounds: CGRect(x: 0, y: 1440, width: 1920, height: 24), pid: Self.otherPID)
        ]
        #expect(CoreGraphicsWindowIndex.ownerOfOrdinaryWindow(
            at: CGPoint(x: 900, y: 1450), in: below, excluding: Self.ownPID
        ) == nil)

        let above = [
            entry(layer: 24, bounds: CGRect(x: 0, y: -1080, width: 1920, height: 24), pid: Self.otherPID)
        ]
        #expect(CoreGraphicsWindowIndex.ownerOfOrdinaryWindow(
            at: CGPoint(x: 900, y: -1070), in: above, excluding: Self.ownPID
        ) == nil)
    }

    @Test("Eigenes gewöhnliches Fenster: keine Abfrage")
    func ownOrdinaryWindowIsRejected() {
        let entries = [
            entry(layer: 0, bounds: CGRect(x: 0, y: 0, width: 400, height: 400), pid: Self.ownPID)
        ]

        let owner = CoreGraphicsWindowIndex.ownerOfOrdinaryWindow(
            at: CGPoint(x: 100, y: 100), in: entries, excluding: Self.ownPID
        )

        #expect(owner == nil)
    }

    /// Rückfallschutz für einen Fehler, der beim Einbau dieses Torwächters
    /// entstanden ist und das Ziehen **vollständig** ausgeschaltet hat.
    ///
    /// Der Dock-Prozess hält ein Fenster auf Ebene 20, dessen Bounds den ganzen
    /// Hauptbildschirm abdecken — gemessen am 23.09.2026: `0,0 5120x1440`, also
    /// exakt die Fläche des Hauptbildschirms. Die erste Fassung nahm das
    /// vorderste Fenster am Punkt und prüfte **danach** die Ebene; damit war für
    /// jeden Punkt des Hauptbildschirms der Dock das vorderste Fenster, jede
    /// Abfrage wurde abgewiesen und es kam nie ein `.began` zustande.
    ///
    /// Systemmöbel muss deshalb übersehen werden, nicht als Sperre gelten. Für
    /// die Zusage aus #69 ist das unerheblich: sie verlangt nur, dass kein
    /// AX-Aufruf gegen den eigenen Prozess läuft, und das entscheidet die
    /// PID-Prüfung.
    @Test("Bildschirmfüllendes Systemmöbel (Dock) verdeckt das Fenster nicht")
    func fullScreenFurnitureDoesNotShadowOrdinaryWindows() {
        let dockPID: pid_t = 897
        let entries = [
            entry(layer: 20, bounds: CGRect(x: 0, y: 0, width: 5120, height: 1440), pid: dockPID),
            entry(layer: 0, bounds: CGRect(x: 2986, y: 31, width: 2134, height: 1343), pid: Self.otherPID)
        ]

        let owner = CoreGraphicsWindowIndex.ownerOfOrdinaryWindow(
            at: CGPoint(x: 3000, y: 200), in: entries, excluding: Self.ownPID
        )

        #expect(owner == Self.otherPID)
    }

    /// Die Reihenfolge gilt unter den **gewöhnlichen** Fenstern: Systemmöbel
    /// darüber verschiebt sie nicht.
    @Test("Systemmöbel ändert die Reihenfolge der gewöhnlichen Fenster nicht")
    func furnitureDoesNotReorderOrdinaryWindows() {
        let front: pid_t = 7
        let entries = [
            entry(layer: 20, bounds: CGRect(x: 0, y: 0, width: 5120, height: 1440), pid: 897),
            entry(layer: 0, bounds: CGRect(x: 200, y: 200, width: 400, height: 400), pid: front),
            entry(layer: 0, bounds: CGRect(x: 0, y: 0, width: 800, height: 800), pid: Self.otherPID)
        ]

        #expect(CoreGraphicsWindowIndex.ownerOfOrdinaryWindow(
            at: CGPoint(x: 300, y: 300), in: entries, excluding: Self.ownPID
        ) == front)
    }

    /// Das eigene Statuselement liegt auf Ebene 25 und kann deshalb gar nicht
    /// gewinnen — die Sicherheitszusage hängt an der PID-Prüfung, nicht daran,
    /// dass Systemmöbel den Blick sperrt. Ein **eigenes gewöhnliches** Fenster
    /// wird weiterhin abgewiesen.
    @Test("Eigenes gewöhnliches Fenster unter fremdem Systemmöbel: keine Abfrage")
    func ownOrdinaryWindowUnderFurnitureIsStillRejected() {
        let entries = [
            entry(layer: 20, bounds: CGRect(x: 0, y: 0, width: 5120, height: 1440), pid: 897),
            entry(layer: 0, bounds: CGRect(x: 0, y: 0, width: 400, height: 400), pid: Self.ownPID)
        ]

        let owner = CoreGraphicsWindowIndex.ownerOfOrdinaryWindow(
            at: CGPoint(x: 100, y: 100), in: entries, excluding: Self.ownPID
        )

        #expect(owner == nil)
    }

    @Test("Punkt über dem leeren Schreibtisch: keine Abfrage")
    func emptyDesktopIsRejected() {
        let entries = [
            entry(layer: 0, bounds: CGRect(x: 0, y: 0, width: 100, height: 100), pid: Self.otherPID)
        ]

        let owner = CoreGraphicsWindowIndex.ownerOfOrdinaryWindow(
            at: CGPoint(x: 500, y: 500), in: entries, excluding: Self.ownPID
        )

        #expect(owner == nil)
        #expect(CoreGraphicsWindowIndex.ownerOfOrdinaryWindow(
            at: CGPoint(x: 10, y: 10), in: [], excluding: Self.ownPID
        ) == nil)
    }

    /// Ein verdecktes Fenster gewinnt nicht, nur weil es weiter vorne in der
    /// Liste stünde — gemeldet wird, was der Nutzer tatsächlich anklickt.
    @Test("Verdeckung zählt: das vorderste Fenster am Punkt gewinnt")
    func frontmostWindowWins() {
        let front: pid_t = 7
        let entries = [
            entry(layer: 0, bounds: CGRect(x: 200, y: 200, width: 400, height: 400), pid: front),
            entry(layer: 0, bounds: CGRect(x: 0, y: 0, width: 800, height: 800), pid: Self.otherPID)
        ]

        #expect(CoreGraphicsWindowIndex.ownerOfOrdinaryWindow(
            at: CGPoint(x: 300, y: 300), in: entries, excluding: Self.ownPID
        ) == front)
        #expect(CoreGraphicsWindowIndex.ownerOfOrdinaryWindow(
            at: CGPoint(x: 50, y: 50), in: entries, excluding: Self.ownPID
        ) == Self.otherPID)
    }
}
