import Foundation
import Testing

@testable import OpenZonrCore

/// Belegt, dass die Abdeckungsberechnung an denselben Vorlagen exakt Null
/// meldet, für die sie im Editor keine Schraffur zeigen darf.
///
/// Überlappung ist laut ``Layout`` erlaubt und darf kein Fehler sein;
/// unbedeckte Fläche ist fast immer ein Versehen und wird schraffiert. Die
/// Kette ist damit: Vorlage → keine Schraffur, hand-gezogene Lücke →
/// Schraffur.
struct LayoutCoverageTests {

    @Test("Hälften decken die Fläche exakt")
    func halvesLeaveNothingUncovered() {
        let zones = [
            RelativeRect(x: 0, y: 0, width: 0.5, height: 1),
            RelativeRect(x: 0.5, y: 0, width: 0.5, height: 1),
        ]
        #expect(LayoutCoverage.uncovered(zones: zones).isEmpty)
    }

    @Test("Drittel decken die Fläche exakt")
    func thirdsLeaveNothingUncovered() {
        let zones = [
            RelativeRect(x: 0, y: 0, width: 4.0 / 12, height: 1),
            RelativeRect(x: 4.0 / 12, y: 0, width: 4.0 / 12, height: 1),
            RelativeRect(x: 8.0 / 12, y: 0, width: 4.0 / 12, height: 1),
        ]
        #expect(LayoutCoverage.uncovered(zones: zones).isEmpty)
    }

    @Test("25/50/25 deckt die Fläche exakt")
    func twentyFiveFiftyTwentyFiveLeavesNothingUncovered() {
        let zones = [
            RelativeRect(x: 0, y: 0, width: 0.25, height: 1),
            RelativeRect(x: 0.25, y: 0, width: 0.5, height: 1),
            RelativeRect(x: 0.75, y: 0, width: 0.25, height: 1),
        ]
        #expect(LayoutCoverage.uncovered(zones: zones).isEmpty)
    }

    @Test("Fünftel decken die Fläche exakt")
    func fifthsLeaveNothingUncovered() {
        let zones = (0..<5).map { i in
            RelativeRect(x: Double(i) * 0.2, y: 0, width: 0.2, height: 1)
        }
        #expect(LayoutCoverage.uncovered(zones: zones).isEmpty)
    }

    @Test("Überlappung ist keine Lücke")
    func overlappingZonesLeaveNothingUncovered() {
        // Der Konzeptfall: großes Fokusfeld über zwei Hälften. Der Test hält
        // fest, dass die Schraffur genau hier still bleibt.
        let zones = [
            RelativeRect(x: 0, y: 0, width: 0.5, height: 1),
            RelativeRect(x: 0.5, y: 0, width: 0.5, height: 1),
            RelativeRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
        ]
        #expect(LayoutCoverage.uncovered(zones: zones).isEmpty)
    }

    @Test("Eine Lücke im Layout wird ausgewiesen")
    func aRealGapIsReported() {
        // Zwei Zonen mit einem sichtbaren Streifen dazwischen: 0.4–0.6 bleibt
        // unbedeckt. Die Rechnung darf davon nicht schweigen — sonst wäre die
        // Schraffur die Sache eines Auges, nicht des Editors.
        let zones = [
            RelativeRect(x: 0, y: 0, width: 0.4, height: 1),
            RelativeRect(x: 0.6, y: 0, width: 0.4, height: 1),
        ]
        let uncovered = LayoutCoverage.uncovered(zones: zones)
        #expect(!uncovered.isEmpty)
        let area = uncovered.reduce(0) { $0 + $1.area }
        // 20 % der Fläche fehlen; das Verfahren rastet auf 60 Schritte, damit
        // sind Rundungen im Milli-Prozentbereich.
        #expect(abs(area - 0.2) < 1e-6)
    }
}
