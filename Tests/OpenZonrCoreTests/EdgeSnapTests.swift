import Foundation
import Testing

@testable import OpenZonrCore

/// Kantenfang beim Loslassen einer Zone im Editor.
///
/// Das Ziel ist die *sichtbare* Naht: zwei Pixel Lücke im Editor sind auf
/// einer Preview unsichtbar und auf 5120 px sehr sichtbar. Die Rechnung ist
/// rein — kein Mausereignis, keine SwiftUI-View — und gehört deshalb
/// hierher.
struct EdgeSnapTests {

    @Test("Nachbarkante innerhalb der Schwelle fängt vor dem Zwölftelraster")
    func neighbourEdgeWinsOverGrid() {
        // Ohne Nachbarkante würde 0.42 aufs Zwölftel 5/12 ≈ 0.4167 fallen.
        // Mit einer Nachbarkante bei 0.43 (weit innerhalb 1/24 = 0.0416)
        // muss die linke Kante an 0.43 fangen — sonst bleibt genau die
        // Lücke, die der Kantenfang verhindern soll.
        let rect = RelativeRect(x: 0.42, y: 0, width: 0.2, height: 1)
        let neighbour = RelativeRect(x: 0, y: 0, width: 0.43, height: 1)
        let snapped = EdgeSnap.snap(rect, neighbours: [neighbour])
        #expect(snapped.x == 0.43)
    }

    @Test("Ohne Nachbarn in Reichweite greift das Zwölftelraster")
    func gridSnapWhenNoNeighboursInRange() {
        let rect = RelativeRect(x: 0.51, y: 0.01, width: 0.24, height: 0.98)
        let snapped = EdgeSnap.snap(rect, neighbours: [])
        #expect(snapped.x == 6.0 / 12)
        #expect(snapped.y == 0)
        #expect(abs(snapped.width - 3.0 / 12) < 1e-9)
        #expect(abs(snapped.height - 12.0 / 12) < 1e-9)
    }

    @Test("Die gerade gezogene Zone darf nicht in den Nachbarn stehen")
    func draggedZoneMustNotAppearInNeighbours() {
        // Wenn die Zone bei sich selbst rastet, hört jede Bewegung sofort auf,
        // weil ihre alten Kanten immer perfekt anliegen. Der Editor
        // filtert deshalb ihre eigene Rechteckform aus der Nachbarnliste.
        // Dieser Test hält den Grund fest: die Funktion selbst filtert
        // *nichts*, sie fängt an allem, was ihr übergeben wird.
        let rect = RelativeRect(x: 0.5, y: 0, width: 0.25, height: 1)
        let self0 = rect
        // Fingiert eine kleine Verschiebung um 0.005 nach rechts. Ohne
        // Filter würde die alte Position (self0) die neue sofort zurück
        // fangen — das dokumentieren wir hier.
        let dragged = RelativeRect(x: 0.505, y: 0, width: 0.25, height: 1)
        let stuckAtSelf = EdgeSnap.snap(dragged, neighbours: [self0])
        #expect(stuckAtSelf.x == 0.5)
    }

    @Test("Ein Punkt weit weg von jeder Kante bleibt beim Raster")
    func farFromEveryEdgeUsesGrid() {
        let rect = RelativeRect(x: 0.35, y: 0, width: 0.3, height: 1)
        let farNeighbour = RelativeRect(x: 0.9, y: 0, width: 0.1, height: 1)
        let snapped = EdgeSnap.snap(rect, neighbours: [farNeighbour])
        // 0.35 → 4/12 ≈ 0.333…
        #expect(abs(snapped.x - 4.0 / 12) < 1e-9)
    }
}
