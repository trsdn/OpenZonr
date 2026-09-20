import ApplicationServices
import Foundation
import Testing
@testable import OpenZonrApp
@testable import OpenZonrCore
@testable import OpenZonrMac

/// Nach dem Loslassen darf kein Overlay stehen bleiben.
///
/// Der Fehler, den diese Datei festhält: In einem Review-Fix-Commit fiel im
/// `.ended`-Zweig des Controllers die Zeile `overlay.hide()` weg. Wer beim
/// Loslassen ⌘ noch hielt (das ist der Normalfall bei `showsWhile(.command)`),
/// sah die blaue Zone weiterhin, denn `update(pointer:modifiers:)` zeichnet sie
/// beim Loslassen mit denselben Tasten noch einmal. Das Overlay verschwand nur,
/// wenn der Nutzer ⌘ vor der Maustaste losließ.
///
/// Geprüft wird die Zusage, nicht die Zeichnung: beim Loslassen wird das
/// Overlay nicht mehr gezeigt, sondern ausdrücklich versteckt — unabhängig
/// davon, welchen Plan `update` errechnet hätte.
@Suite("DropzoneController — Overlay nach dem Loslassen")
@MainActor
struct DropzoneControllerOverlayTests {

    @MainActor
    final class SpyOverlay: DropzoneOverlaying {
        private(set) var calls: [String] = []
        func show(_ plan: DropzoneOverlayPlan.Plan) { calls.append("show") }
        func hide() { calls.append("hide") }
    }

    private func draggedWindow() -> DraggedWindow {
        DraggedWindow(
            element: AXUIElementCreateSystemWide(),
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            bundleIdentifier: nil,
            applicationName: "Test",
            frame: WindowFrame(x: 0, y: 0, width: 100, height: 100)
        )
    }

    @Test("Loslassen mit gehaltener ⌘: das Overlay wird versteckt, nicht neu gezeigt")
    func releaseWithCommandHeldHidesTheOverlay() throws {
        let loaded = try AppModelFixtures.modelWithLoadedConfiguration(AppModelFixtures.minimalConfiguration())
        let spy = SpyOverlay()
        let controller = DropzoneController(model: loaded.model, overlay: spy)
        let point = ScreenPoint(x: 10, y: 10)

        #if DEBUG
        controller._handleForTesting(.began(draggedWindow(), at: point))
        controller._handleForTesting(.ended(point, modifiers: [.command]))
        #endif

        // Genau ein Aufruf, und der versteckt. Ohne die Zeile im `.ended`-Zweig
        // bliebe die Liste leer (oder endete auf "show").
        #expect(spy.calls == ["hide"])
    }

    @Test("Loslassen ohne Tasten: dasselbe")
    func releaseWithoutModifiersHidesTheOverlay() throws {
        let loaded = try AppModelFixtures.modelWithLoadedConfiguration(AppModelFixtures.minimalConfiguration())
        let spy = SpyOverlay()
        let controller = DropzoneController(model: loaded.model, overlay: spy)
        let point = ScreenPoint(x: 10, y: 10)

        #if DEBUG
        controller._handleForTesting(.began(draggedWindow(), at: point))
        controller._handleForTesting(.ended(point, modifiers: []))
        #endif

        #expect(spy.calls == ["hide"])
    }
}
