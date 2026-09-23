import Foundation
import Testing

@testable import OpenZonrCore

/// Wird ein Rechteck von einer Menge anderer Rechtecke lückenlos überdeckt?
///
/// Der Fall, um den es geht, ist die **Vereinigung**: „Rechts außen" wird von
/// keiner einzelnen Zone überdeckt, sondern erst von „Rechts oben" und „Rechts
/// unten" zusammen. Eine paarweise Prüfung fände ihn nicht.
@Suite("Rechteck-Überdeckung")
struct RectangleCoverageTests {

    private func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> WindowFrame {
        WindowFrame(x: x, y: y, width: w, height: h)
    }

    @Test("Eine leere Menge überdeckt nichts")
    func emptySetCoversNothing() {
        #expect(RectangleCoverage.isCovered(rect(0, 0, 10, 10), by: []) == false)
    }

    @Test("Ein deckungsgleiches Rechteck überdeckt")
    func identicalRectangleCovers() {
        #expect(RectangleCoverage.isCovered(rect(0, 0, 10, 10), by: [rect(0, 0, 10, 10)]))
    }

    @Test("Ein grösseres Rechteck überdeckt")
    func largerRectangleCovers() {
        #expect(RectangleCoverage.isCovered(rect(2, 2, 6, 6), by: [rect(0, 0, 10, 10)]))
    }

    @Test("Zwei Hälften überdecken zusammen — der eigentliche Fall")
    func twoHalvesCoverTogether() {
        let whole = rect(0, 0, 10, 10)
        let lower = rect(0, 0, 10, 5)
        let upper = rect(0, 5, 10, 5)

        #expect(RectangleCoverage.isCovered(whole, by: [lower]) == false)
        #expect(RectangleCoverage.isCovered(whole, by: [upper]) == false)
        #expect(RectangleCoverage.isCovered(whole, by: [lower, upper]))
    }

    @Test("Eine Lücke von einem Punkt genügt, um nicht zu überdecken")
    func aSingleGapIsEnough() {
        let whole = rect(0, 0, 10, 10)
        let lower = rect(0, 0, 10, 4)
        let upper = rect(0, 5, 10, 5)

        #expect(RectangleCoverage.isCovered(whole, by: [lower, upper]) == false)
    }

    @Test("Überlappende Teile überdecken trotzdem")
    func overlappingPartsStillCover() {
        let whole = rect(0, 0, 10, 10)
        #expect(RectangleCoverage.isCovered(whole, by: [rect(0, 0, 10, 7), rect(0, 3, 10, 7)]))
    }

    @Test("Ein Rechteck ohne Fläche gilt als überdeckt")
    func emptyRectangleIsCovered() {
        #expect(RectangleCoverage.isCovered(rect(0, 0, 0, 10), by: []))
    }

    @Test("Teilweise Überdeckung reicht nicht")
    func partialCoverageIsNotEnough() {
        #expect(RectangleCoverage.isCovered(rect(0, 0, 10, 10), by: [rect(0, 0, 5, 10)]) == false)
    }

    @Test("Vertikale Lücke — X-Unterteilung ist erforderlich")
    func verticalGapRequiresXSubdivision() {
        // Ein einzelnes Rechteck, das nur einen Streifen abdeckt, reicht nicht —
        // das Gitter muss in X subdividiert werden, um die fehlende Abdeckung links
        // und rechts zu erkennen.
        #expect(RectangleCoverage.isCovered(rect(0, 0, 10, 10), by: [rect(4, 0, 3, 10)]) == false)
    }

    @Test("L-Form — beide Achsen erfordern Unterteilung")
    func lShapeRequiresBothAxes() {
        // Das Ziel ist eine 3×3-Fläche. Zwei Rechtecke bilden eine L:
        // Eins deckt die Hälfte oben ab, das andere die Hälfte unten rechts.
        // Die Gitterzerlegung muss sowohl in X als auch in Y unterteilen, um die
        // fehlende Ecke (oben links, unten rechts) zu erkennen.
        let target = rect(0, 0, 3, 3)
        let horizontal = rect(0, 1.5, 3, 1.5)  // Oben — deckt [0,3) × [1.5,3) ab
        let vertical = rect(1.5, 0, 1.5, 1.5)  // Unten rechts — deckt [1.5,3) × [0,1.5) ab

        // Einzeln reicht keiner
        #expect(RectangleCoverage.isCovered(target, by: [horizontal]) == false)
        #expect(RectangleCoverage.isCovered(target, by: [vertical]) == false)

        // Beide zusammen decken nicht alles ab: (oben links) bleibt frei
        #expect(RectangleCoverage.isCovered(target, by: [horizontal, vertical]) == false)
    }

    @Test("Drei Rechtecke — die echte Vereinigungsaufgabe")
    func threeRectanglesUnionCase() {
        // Ziel: 10×10. Drei Rechtecke bilden zusammen eine vollständige Abdeckung,
        // aber kein Paar von ihnen tut es.
        let target = rect(0, 0, 10, 10)
        let left = rect(0, 0, 4, 10)      // [0,4) × [0,10)
        let topRight = rect(4, 6, 6, 4)   // [4,10) × [6,10)
        let bottomRight = rect(4, 0, 6, 6) // [4,10) × [0,6)

        // Kein Paar deckt ab
        #expect(RectangleCoverage.isCovered(target, by: [left, topRight]) == false)
        #expect(RectangleCoverage.isCovered(target, by: [left, bottomRight]) == false)
        #expect(RectangleCoverage.isCovered(target, by: [topRight, bottomRight]) == false)

        // Alle drei zusammen decken ab
        #expect(RectangleCoverage.isCovered(target, by: [left, topRight, bottomRight]))
    }

    @Test("Berührung an X-Kante — beide Hälften nebeneinander")
    func horizontalTouchingAtEdge() {
        // Zwei Rechtecke nebeneinander (benachbart in X) decken zusammen ab.
        let target = rect(0, 0, 10, 10)
        let left = rect(0, 0, 5, 10)   // [0,5) × [0,10)
        let right = rect(5, 0, 5, 10)  // [5,10) × [0,10)

        // Einzeln: nicht ausreichend
        #expect(RectangleCoverage.isCovered(target, by: [left]) == false)
        #expect(RectangleCoverage.isCovered(target, by: [right]) == false)

        // Beide zusammen: vollständig, da die Kante genau passt (5 ist
        // ausschließlich in [5,10), inklusive in [0,5) ist nicht möglich)
        #expect(RectangleCoverage.isCovered(target, by: [left, right]))
    }

    @Test("Überdeckendes Rechteck ohne Fläche trägt nichts bei")
    func zeroAreaCoveringRectangleContributesNothing() {
        // Ein Rechteck mit Breite 0 oder Höhe 0 wird gefiltert und trägt
        // nicht zur Abdeckung bei.
        let target = rect(0, 0, 10, 10)
        let zeroWidth = rect(5, 0, 0, 10)
        let zeroHeight = rect(0, 5, 10, 0)

        #expect(RectangleCoverage.isCovered(target, by: [zeroWidth]) == false)
        #expect(RectangleCoverage.isCovered(target, by: [zeroHeight]) == false)
    }

    @Test("Überdeckendes Rechteck ganz ausserhalb trägt nichts bei")
    func outsideCoveringRectangleContributesNothing() {
        // Ein Rechteck, das das Ziel überhaupt nicht berührt, wird gefiltert.
        let target = rect(0, 0, 10, 10)
        let farLeft = rect(-10, 0, 5, 10)
        let farRight = rect(15, 0, 5, 10)
        let farBelow = rect(0, -10, 10, 5)
        let farAbove = rect(0, 15, 10, 5)

        #expect(RectangleCoverage.isCovered(target, by: [farLeft]) == false)
        #expect(RectangleCoverage.isCovered(target, by: [farRight]) == false)
        #expect(RectangleCoverage.isCovered(target, by: [farBelow]) == false)
        #expect(RectangleCoverage.isCovered(target, by: [farAbove]) == false)
    }
}
