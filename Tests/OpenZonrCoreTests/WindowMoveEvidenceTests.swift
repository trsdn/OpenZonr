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

    @Test("Nur eine Achse folgt (y unveraendert, z. B. oben geklemmt), reicht trotzdem")
    func windowFollowingOnlyOneAxisStillCounts() {
        // Zeiger 60 rechts / 100 hoch, Fenster nur 60 rechts: cos ~ 0,51.
        let clamped = WindowFrame(x: 160, y: 100, width: 400, height: 300)
        #expect(classify(clamped, to: ScreenPoint(x: 210, y: 450)) == .moved)
    }

    @Test("Groessenabweichung innerhalb der Toleranz zaehlt nicht als Resize")
    func subPointSizeNoiseIsIgnored() {
        let noisy = WindowFrame(x: 180, y: 100, width: 401, height: 299)
        #expect(classify(noisy, to: ScreenPoint(x: 250, y: 350)) == .moved)
    }

    @Test("Kleiner Drift bei grossem Zeigerweg ist kein Fensterzug")
    func tinyDriftWithLongPointerTravelIsNotMovement() {
        let drift = WindowFrame(x: 102, y: 100, width: 400, height: 300)
        #expect(classify(drift, to: ScreenPoint(x: 450, y: 350)) == .notMoved)
    }

    @Test("Fenster quer zum Zeiger (fast senkrecht, Skalarprodukt positiv) -> notMoved")
    func perpendicularShiftIsNotMovement() {
        let sideways = WindowFrame(x: 110, y: 160, width: 400, height: 300)
        #expect(classify(sideways, to: ScreenPoint(x: 250, y: 350)) == .notMoved)
        let exactlyPerpendicular = WindowFrame(x: 100, y: 160, width: 400, height: 300)
        #expect(classify(exactlyPerpendicular, to: ScreenPoint(x: 250, y: 350)) == .notMoved)
    }

    @Test("Mindeststrecke: genau am Boden zaehlt, knapp darunter nicht")
    func minimumTravelBoundary() {
        let floor = WindowMoveEvidence.minimumTravel
        let at = WindowFrame(x: 100 + floor, y: 100, width: 400, height: 300)
        let below = WindowFrame(x: 100 + floor - 0.1, y: 100, width: 400, height: 300)
        #expect(classify(at, to: ScreenPoint(x: 350, y: 350)) == .moved)
        #expect(classify(below, to: ScreenPoint(x: 350, y: 350)) == .notMoved)
    }

    @Test("Groessentoleranz: genau 2 pt gilt als gleich, darueber ist resized")
    func sizeToleranceBoundary() {
        let tol = WindowMoveEvidence.sizeTolerance
        let atLimit = WindowFrame(x: 180, y: 100, width: 400 + tol, height: 300)
        let over = WindowFrame(x: 180, y: 100, width: 400 + tol + 0.5, height: 300)
        #expect(classify(atLimit, to: ScreenPoint(x: 250, y: 350)) == .moved)
        #expect(classify(over, to: ScreenPoint(x: 250, y: 350)) == .resized)
    }

    @Test("Reiner Vertikalzug: Fenster folgt nur in y -> moved")
    func yOnlyDragIsMoved() {
        let up = WindowFrame(x: 100, y: 160, width: 400, height: 300)
        #expect(classify(up, to: ScreenPoint(x: 150, y: 410)) == .moved)
    }

    @Test("Zeiger steht still, Fenster bewegt sich -> notMoved")
    func windowMovingWithoutPointerTravelIsNotMovement() {
        let moved = WindowFrame(x: 180, y: 100, width: 400, height: 300)
        #expect(classify(moved, to: from) == .notMoved)
    }

    @Test("Zug ueber Bildschirmgrenze (grosse Verschiebung) -> moved")
    func crossDisplayDragIsMoved() {
        let far = WindowFrame(x: 2100, y: 100, width: 400, height: 300)
        #expect(classify(far, to: ScreenPoint(x: 2150, y: 350)) == .moved)
    }
}
