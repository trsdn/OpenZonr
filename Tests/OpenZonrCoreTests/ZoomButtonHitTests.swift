import Foundation
import Testing

@testable import OpenZonrCore

/// ``ZoomButtonHit`` ist reine Geometrie — die AX-Abfrage sitzt woanders. Die
/// drei Ausgänge sind Zusicherungen an den Aufrufer (siehe Issue #27):
/// **hit** und **missed** sind Alltag, **buttonUnavailable** ist das Signal
/// „hier gibt es keinen Knopf" und muss vom Aufrufer erkennbar behandelt
/// werden — nicht stumm.
@Suite("Zoom-Knopf-Trefferprüfung")
struct ZoomButtonHitTests {

    private let frame = WindowFrame(x: 2585, y: 57, width: 16, height: 16)

    @Test("Treffer im Rahmen wird als hit gemeldet")
    func hitInsideFrame() {
        let point = ScreenPoint(x: 2593, y: 65)
        #expect(zoomButtonHitTest(point: point, zoomButtonFrame: frame) == .hit)
    }

    @Test("Linke und untere Kante gehören zum Rahmen")
    func leftAndBottomEdgesIncluded() {
        // Gleiche Kantenregel wie WindowFrame.contains: unten/links inklusiv.
        #expect(zoomButtonHitTest(point: ScreenPoint(x: 2585, y: 57), zoomButtonFrame: frame) == .hit)
    }

    @Test("Rechte und obere Kante gehören nicht zum Rahmen")
    func rightAndTopEdgesExcluded() {
        #expect(zoomButtonHitTest(point: ScreenPoint(x: 2601, y: 65), zoomButtonFrame: frame) == .missed)
        #expect(zoomButtonHitTest(point: ScreenPoint(x: 2593, y: 73), zoomButtonFrame: frame) == .missed)
    }

    @Test("Punkt daneben wird als missed gemeldet")
    func pointOutsideFrame() {
        let point = ScreenPoint(x: 2600, y: 200)
        #expect(zoomButtonHitTest(point: point, zoomButtonFrame: frame) == .missed)
    }

    @Test("Fehlt der Rahmen, ist die Antwort buttonUnavailable — nicht missed")
    func missingFrameIsExplicit() {
        // Das ist der Kern der drei-wertigen Aufzählung: nil verwechselt sich
        // nicht mit „daneben". Aufrufer sollen den Nutzer erkennbar
        // informieren (Finder-Fall aus Issue #27).
        #expect(zoomButtonHitTest(point: ScreenPoint(x: 0, y: 0), zoomButtonFrame: nil) == .buttonUnavailable)
    }
}
