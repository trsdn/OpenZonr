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
}
