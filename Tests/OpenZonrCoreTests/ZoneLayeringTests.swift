import Foundation
import Testing

@testable import OpenZonrCore

/// Zonen in überlappungsfreie Ebenen zerlegen.
///
/// Der Anlass: die Übersicht schreibt die Beschriftung jeder Zone in ihr
/// Rechteck. Bei gestapelten Zonen lagen mehrere Texte übereinander — gemeldet
/// am 24.09.2026 mit „Rechts:oben" und „Linksild" als Beleg. Innerhalb einer
/// Ebene überlappt nichts, also ist jede Beschriftung wieder lesbar.
@Suite("Zonen in Ebenen zerlegen")
struct ZoneLayeringTests {

    private func zone(_ id: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Zone {
        Zone(id: ZoneID(rawValue: id), name: id, frame: RelativeRect(x: x, y: y, width: w, height: h))
    }

    @Test("Keine Zonen ergeben keine Ebene")
    func emptyYieldsNoLayers() {
        #expect(ZoneLayering.layers(of: []).isEmpty)
    }

    /// Der Normalfall. Ginge er schief, zerfiele jede gewöhnliche
    /// Spaltenaufteilung in Einzelebenen und die Zerlegung wäre unbrauchbar.
    @Test("Nebeneinanderliegende Spalten bleiben in einer Ebene")
    func adjacentColumnsStayTogether() {
        let zones = [
            zone("links", 0, 0, 0.25, 1),
            zone("mitte", 0.25, 0, 0.5, 1),
            zone("rechts", 0.75, 0, 0.25, 1)
        ]

        let layers = ZoneLayering.layers(of: zones)

        #expect(layers.count == 1)
        #expect(layers[0].count == 3)
    }

    @Test("Eine geteilte Kante ist keine Überlappung")
    func sharedEdgeIsNotAnOverlap() {
        #expect(ZoneLayering.overlaps(
            RelativeRect(x: 0, y: 0, width: 0.5, height: 1),
            RelativeRect(x: 0.5, y: 0, width: 0.5, height: 1)
        ) == false)
    }

    /// Die echte Ebene des Autors, Stand 24.09.2026: drei Spalten, und in der
    /// rechten liegen zwei Hälften.
    @Test("Die Ebene des Autors zerfällt in genau zwei Gruppen")
    func theAuthorsLayoutSplitsIntoTwo() {
        let zones = [
            zone("left-quarter", 0, 0, 0.25, 1),
            zone("center-half", 0.25, 0, 0.41666666666666663, 1),
            zone("right-quarter", 0.6666666666666666, 0, 0.33333333333333337, 1),
            zone("neue-zone", 0.6666666666666666, 0, 0.33333333333333337, 0.5),
            zone("neue-zone-2", 0.6666666666666666, 0.5, 0.33333333333333337, 0.5)
        ]

        let layers = ZoneLayering.layers(of: zones)

        #expect(layers.count == 2)
        #expect(Set(layers[0].map(\.id.rawValue)) == ["left-quarter", "center-half", "right-quarter"])
        #expect(Set(layers[1].map(\.id.rawValue)) == ["neue-zone", "neue-zone-2"])
    }

    /// Die grossen Flächen zuerst. Umgekehrt begänne die Übersicht mit den
    /// Bruchstücken und die tragende Aufteilung stünde unten.
    @Test("Die erste Ebene trägt die grössten Flächen")
    func largestAreasComeFirst() {
        let zones = [
            zone("klein", 0, 0, 0.2, 0.2),
            zone("gross", 0, 0, 1, 1)
        ]

        let layers = ZoneLayering.layers(of: zones)

        #expect(layers.count == 2)
        #expect(layers[0].map(\.id.rawValue) == ["gross"])
        #expect(layers[1].map(\.id.rawValue) == ["klein"])
    }

    @Test("Drei ineinander liegende Zonen ergeben drei Ebenen")
    func fullyNestedZonesYieldThreeLayers() {
        let zones = [
            zone("aussen", 0, 0, 1, 1),
            zone("mittel", 0.1, 0.1, 0.5, 0.5),
            zone("innen", 0.2, 0.2, 0.2, 0.2)
        ]

        #expect(ZoneLayering.layers(of: zones).count == 3)
    }

    /// Dieselbe Konfiguration muss dieselbe Ansicht ergeben — sonst hinge das
    /// Bild von der Reihenfolge in der Datei ab.
    @Test("Die Reihenfolge der Eingabe ändert das Ergebnis nicht")
    func inputOrderDoesNotMatter() {
        let zones = [
            zone("a", 0, 0, 1, 1),
            zone("b", 0, 0, 0.5, 1),
            zone("c", 0.5, 0, 0.5, 1)
        ]

        let forward = ZoneLayering.layers(of: zones).map { $0.map(\.id.rawValue) }
        let backward = ZoneLayering.layers(of: zones.reversed()).map { $0.map(\.id.rawValue) }

        #expect(forward == backward)
    }

    @Test("Gleich grosse überlappende Zonen werden nach Kennung geordnet")
    func equalAreasAreOrderedByIdentifier() {
        let zones = [
            zone("zweite", 0, 0, 0.5, 0.5),
            zone("erste", 0.1, 0.1, 0.5, 0.5)
        ]

        let layers = ZoneLayering.layers(of: zones)

        #expect(layers.count == 2)
        #expect(layers[0].map(\.id.rawValue) == ["erste"])
    }

    @Test("Jede Ebene ist in sich überlappungsfrei")
    func everyLayerIsFreeOfOverlap() {
        let zones = [
            zone("a", 0, 0, 1, 1),
            zone("b", 0, 0, 0.5, 1),
            zone("c", 0.5, 0, 0.5, 1),
            zone("d", 0.25, 0.25, 0.5, 0.5),
            zone("e", 0, 0, 0.1, 0.1)
        ]

        for layer in ZoneLayering.layers(of: zones) {
            for (index, one) in layer.enumerated() {
                for other in layer[(index + 1)...] {
                    #expect(ZoneLayering.overlaps(one.frame, other.frame) == false)
                }
            }
        }
    }

    @Test("Keine Zone geht verloren und keine kommt doppelt vor")
    func everyZoneAppearsExactlyOnce() {
        let zones = [
            zone("a", 0, 0, 1, 1),
            zone("b", 0, 0, 0.5, 1),
            zone("c", 0.5, 0, 0.5, 1),
            zone("d", 0.25, 0.25, 0.5, 0.5)
        ]

        let flattened = ZoneLayering.layers(of: zones).flatMap { $0.map(\.id.rawValue) }

        #expect(flattened.sorted() == ["a", "b", "c", "d"])
        #expect(Set(flattened).count == flattened.count)
    }
}
