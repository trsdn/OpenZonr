import Foundation
import Testing

@testable import OpenZonrCore

/// Streichen über Zellen als Rechteck.
///
/// Gerechnet wird in Zellen, nicht in Punkten: die Geste trifft dieselben
/// Kanten, auf die ``EdgeSnap`` einen gezogenen Griff rasten lässt. Eine andere
/// Auflösung hier hiesse, dass zwei Bedienwege im selben Editor auf
/// verschiedene Raster fallen.
@Suite("Streichen über Zellen")
struct GridSweepTests {

    private static let canvas = CGSize(width: 1200, height: 1200)
    /// Eine Zelle ist 100 Punkte breit bei 1200 / 12.
    private static let cell: Double = 100

    private func rect(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> RelativeRect? {
        GridSweep.rect(
            from: CGPoint(x: x1, y: y1),
            to: CGPoint(x: x2, y: y2),
            canvas: Self.canvas
        )
    }

    @Test("Ein Klick ohne Bewegung ergibt genau eine Zelle")
    func singleClickYieldsOneCell() {
        // Mitte der Zelle (0, 0).
        #expect(rect(50, 50, 50, 50) == RelativeRect(x: 0, y: 0, width: 1.0 / 12, height: 1.0 / 12))
    }

    /// Ohne diese Regel wäre die häufigste Fehlbedienung — klicken statt
    /// ziehen — eine Zone ohne Fläche, also eine unsichtbare und nach dem
    /// neuen Prüfschritt zugleich unerreichbare Zone.
    @Test("Ein Klick ergibt nie ein Rechteck ohne Fläche")
    func singleClickIsNeverEmpty() {
        let result = rect(0, 0, 0, 0)
        #expect(result?.width ?? 0 > 0)
        #expect(result?.height ?? 0 > 0)
    }

    @Test("Ein Zug über drei Spalten und zwei Zeilen zieht beide Enden ein")
    func sweepIncludesBothEnds() {
        // Von Zelle (0,0) nach Zelle (2,1), jeweils in der Zellenmitte.
        let result = rect(50, 50, 2 * Self.cell + 50, Self.cell + 50)

        #expect(result == RelativeRect(x: 0, y: 0, width: 3.0 / 12, height: 2.0 / 12))
    }

    @Test("Die Richtung der Geste ist gleichgültig")
    func directionDoesNotMatter() {
        let forward = rect(50, 50, 2 * Self.cell + 50, Self.cell + 50)
        let backward = rect(2 * Self.cell + 50, Self.cell + 50, 50, 50)

        #expect(forward == backward)
    }

    @Test("Über den Rand hinaus trifft die Randzelle, nicht daneben")
    func beyondTheEdgeHitsTheEdgeCell() {
        let result = rect(50, 50, 5000, 5000)

        #expect(result == RelativeRect(x: 0, y: 0, width: 1, height: 1))
        // Nichts ragt aus dem Einheitsquadrat heraus.
        #expect((result?.x ?? 0) + (result?.width ?? 0) <= 1)
        #expect((result?.y ?? 0) + (result?.height ?? 0) <= 1)
    }

    @Test("Negative Koordinaten treffen die erste Zelle")
    func negativeCoordinatesHitTheFirstCell() {
        #expect(rect(-500, -500, 50, 50) == RelativeRect(x: 0, y: 0, width: 1.0 / 12, height: 1.0 / 12))
    }

    @Test("Die ganze Leinwand ergibt das Einheitsquadrat")
    func fullSweepCoversEverything() {
        #expect(rect(0, 0, 1199, 1199) == RelativeRect(x: 0, y: 0, width: 1, height: 1))
    }

    /// Die Kanten liegen auf `n · (1/12)` — und **nicht** auf `n/12`.
    ///
    /// Das ist kein Haarspalten. In Fließkomma sind die beiden verschieden:
    /// `5 · (1/12) = 0.41666666666666663`, `5/12 = 0.4166666666666667`.
    /// ``EdgeSnap/gridSnap`` rechnet `(value / step).rounded() * step`, also
    /// die Multiplikationsform, und genau diese Zahl steht schon in
    /// bestehenden Konfigurationen. Wer hier dividierte, bekäme Zonen, die um
    /// ein ULP nebeneinander liegen statt aneinander — unsichtbar im Editor,
    /// und auf 5120 Punkten Breite ein Spalt, den niemand erklären kann.
    @Test("Jede Kante liegt auf n · (1/12), wie bei EdgeSnap")
    func everyEdgeSitsOnTheSameTwelfthAsEdgeSnap() {
        let step = 1.0 / 12.0
        for column in 0..<12 {
            for row in 0..<12 {
                let point = CGPoint(x: Double(column) * Self.cell + 50, y: Double(row) * Self.cell + 50)
                let result = GridSweep.rect(from: point, to: point, canvas: Self.canvas)

                #expect(result?.x == Double(column) * step)
                #expect(result?.y == Double(row) * step)
            }
        }
    }

    /// Der eigentliche Beleg: die beiden Bedienwege des Editors — streichen
    /// und ziehen — müssen bitgleiche Kanten erzeugen. Täten sie es nicht,
    /// hinge es von der benutzten Geste ab, ob zwei Zonen bündig sitzen.
    @Test("Streichen und EdgeSnap erzeugen bitgleiche Kanten")
    func sweepAgreesWithEdgeSnapBitForBit() {
        for column in 0...11 {
            for span in 1...(12 - column) {
                let start = CGPoint(x: Double(column) * Self.cell + 50, y: 50)
                let end = CGPoint(x: Double(column + span - 1) * Self.cell + 50, y: 50)
                guard let swept = GridSweep.rect(from: start, to: end, canvas: Self.canvas) else {
                    Issue.record("kein Rechteck für Spalte \(column), Breite \(span)")
                    continue
                }

                // Dasselbe Rechteck durch den Fang der Griff-Geste geschickt:
                // ohne Nachbarn bleibt nur das Zwölftelraster übrig.
                let snapped = EdgeSnap.snap(swept, neighbours: [])

                #expect(snapped.x == swept.x)
                #expect(snapped.width == swept.width)
            }
        }
    }

    @Test("Eine Leinwand ohne Fläche ergibt kein Rechteck")
    func zeroCanvasYieldsNothing() {
        let point = CGPoint(x: 0, y: 0)
        #expect(GridSweep.rect(from: point, to: point, canvas: CGSize(width: 0, height: 100)) == nil)
        #expect(GridSweep.rect(from: point, to: point, canvas: CGSize(width: 100, height: 0)) == nil)
    }
}
