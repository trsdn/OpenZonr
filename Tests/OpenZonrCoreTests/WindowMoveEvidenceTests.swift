import Foundation
import Testing

@testable import OpenZonrCore

/// Bewegungsbeleg fuer #37: Zieht der Nutzer das Fenster, oder etwas darin?
struct WindowMoveEvidenceTests {

    private let start = WindowFrame(x: 100, y: 100, width: 400, height: 300)
    private let from = ScreenPoint(x: 150, y: 350)

    private func classify(
        _ current: WindowFrame, to: ScreenPoint
    ) -> WindowMoveEvidence.Verdict {
        WindowMoveEvidence.classify(initial: start, current: current, pointerFrom: from, pointerTo: to)
    }

    @Test("Titelleistenzug: Fenster folgt dem Zeiger, Groesse gleich -> moved")
    func titleBarDragIsMoved() {
        let moved = WindowFrame(x: 180, y: 90, width: 400, height: 300)
        #expect(classify(moved, to: ScreenPoint(x: 230, y: 340)) == .moved)
    }

    @Test("Inhaltszug (Text, Datei, Scrollbalken): Rahmen unveraendert -> notMoved")
    func contentDragLeavesFrameUntouched() {
        #expect(classify(start, to: ScreenPoint(x: 400, y: 200)) == .notMoved)
    }

    @Test("Rahmen wackelt unter der Mindeststrecke -> notMoved")
    func jitterIsNotMovement() {
        let jitter = WindowFrame(x: 101, y: 100, width: 400, height: 300)
        #expect(classify(jitter, to: ScreenPoint(x: 400, y: 350)) == .notMoved)
    }

    @Test("Kantenziehen aendert die Groesse -> resized, nie moved")
    func edgeResizeIsNotMovement() {
        let resized = WindowFrame(x: 100, y: 100, width: 460, height: 300)
        #expect(classify(resized, to: ScreenPoint(x: 210, y: 350)) == .resized)
        // Ecke links unten: Ursprung und Groesse aendern sich zugleich.
        let cornerResized = WindowFrame(x: 60, y: 60, width: 440, height: 340)
        #expect(classify(cornerResized, to: ScreenPoint(x: 110, y: 310)) == .resized)
    }

    @Test("Fenster bewegt sich gegen den Zeiger -> notMoved")
    func oppositeDirectionIsNotMovement() {
        let opposite = WindowFrame(x: 40, y: 100, width: 400, height: 300)
        #expect(classify(opposite, to: ScreenPoint(x: 250, y: 350)) == .notMoved)
    }

    @Test("Am Bildschirmrand geklemmt: nur eine Achse folgt, reicht trotzdem")
    func clampedWindowStillCountsWhenOneAxisFollows() {
        let clamped = WindowFrame(x: 160, y: 100, width: 400, height: 300)
        #expect(classify(clamped, to: ScreenPoint(x: 210, y: 450)) == .moved)
    }

    @Test("Groessenabweichung innerhalb der Toleranz zaehlt nicht als Resize")
    func subPointSizeNoiseIsIgnored() {
        let noisy = WindowFrame(x: 180, y: 100, width: 401, height: 299)
        #expect(classify(noisy, to: ScreenPoint(x: 250, y: 350)) == .moved)
    }
}
