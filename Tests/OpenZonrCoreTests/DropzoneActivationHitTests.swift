import Foundation
import Testing

@testable import OpenZonrCore

/// Der Zweck des ganzen Vorhabens: ein Stapel, dessen Ebenen einzeln erreichbar
/// sind.
///
/// Gemessen an der Ebene des Autors (C49RG9x, 5120x1440) war „Rechts außen"
/// unerreichbar, weil „Rechts oben" und „Rechts unten" es lückenlos überdecken
/// und beide kleiner sind.
@Suite("Treffertest — Trefferflächen")
struct DropzoneActivationHitTests {

    private static let visible = VisibleFrame(x: 0, y: 0, width: 1000, height: 800)

    private func zone(
        _ id: String,
        frame: WindowFrame,
        activation: WindowFrame? = nil
    ) -> Dropzone {
        Dropzone(
            display: DisplayAlias(rawValue: "haupt"),
            zone: ZoneID(rawValue: id),
            name: id,
            relativeFrame: .full,
            frame: frame,
            visibleFrame: Self.visible,
            activationFrame: activation
        )
    }

    /// Der Stapel aus der Konfiguration des Autors, auf 1000x800 verkleinert:
    /// eine ganze Spalte und die zwei Hälften darin, mit drei disjunkten
    /// Trefferstreifen.
    private var stack: [Dropzone] {
        [
            zone("ganz",
                 frame: WindowFrame(x: 600, y: 0, width: 400, height: 800),
                 activation: WindowFrame(x: 600, y: 350, width: 400, height: 100)),
            zone("oben",
                 frame: WindowFrame(x: 600, y: 400, width: 400, height: 400),
                 activation: WindowFrame(x: 600, y: 700, width: 400, height: 100)),
            zone("unten",
                 frame: WindowFrame(x: 600, y: 0, width: 400, height: 400),
                 activation: WindowFrame(x: 600, y: 0, width: 400, height: 100))
        ]
    }

    @Test("Jede Ebene des Stapels ist einzeln erreichbar")
    func everyLayerIsReachable() {
        let zones = stack

        #expect(DropzoneMap.zone(at: ScreenPoint(x: 700, y: 400), in: zones)?.zone.rawValue == "ganz")
        #expect(DropzoneMap.zone(at: ScreenPoint(x: 700, y: 750), in: zones)?.zone.rawValue == "oben")
        #expect(DropzoneMap.zone(at: ScreenPoint(x: 700, y: 50), in: zones)?.zone.rawValue == "unten")
    }

    @Test("Der getroffene Zielrahmen bleibt der grosse, nicht der Streifen")
    func hitCarriesTheTargetFrame() {
        let hit = DropzoneMap.zone(at: ScreenPoint(x: 700, y: 400), in: stack)

        #expect(hit?.frame == WindowFrame(x: 600, y: 0, width: 400, height: 800))
        #expect(hit?.placement.frame == WindowFrame(x: 600, y: 0, width: 400, height: 800))
    }

    @Test("Ausserhalb aller Trefferflächen wird nichts getroffen")
    func missesBetweenTheStrips() {
        #expect(DropzoneMap.zone(at: ScreenPoint(x: 700, y: 200), in: stack) == nil)
    }

    /// Rückfallschutz für jede bestehende Konfiguration: ohne Trefferflächen
    /// muss der Treffertest exakt so entscheiden wie vorher — kleinste gewinnt.
    @Test("Ohne Trefferflächen entscheidet weiter die kleinste Fläche")
    func withoutActivationAreasSmallestStillWins() {
        let zones = [
            zone("gross", frame: WindowFrame(x: 0, y: 0, width: 1000, height: 800)),
            zone("klein", frame: WindowFrame(x: 0, y: 0, width: 100, height: 100))
        ]

        #expect(DropzoneMap.zone(at: ScreenPoint(x: 50, y: 50), in: zones)?.zone.rawValue == "klein")
        #expect(DropzoneMap.zone(at: ScreenPoint(x: 500, y: 500), in: zones)?.zone.rawValue == "gross")
    }

    /// Randauslösung: die Trefferfläche liegt am linken Rand, das Fenster
    /// landet rechts.
    @Test("Trefferfläche ausserhalb des Zielrahmens löst trotzdem aus")
    func activationOutsideTheFrameStillHits() {
        let zones = [
            zone("rechts",
                 frame: WindowFrame(x: 600, y: 0, width: 400, height: 800),
                 activation: WindowFrame(x: 0, y: 0, width: 40, height: 800))
        ]

        let hit = DropzoneMap.zone(at: ScreenPoint(x: 20, y: 400), in: zones)
        #expect(hit?.zone.rawValue == "rechts")
        #expect(hit?.frame.x == 600)
    }

    /// Gleich grosse Trefferflächen werden weiter über Display und Zonen-ID
    /// entschieden, nie über die Reihenfolge im Array.
    @Test("Gleichstand entscheidet die Zonen-ID, nicht die Reihenfolge")
    func tiesAreBrokenByIdentifier() {
        let a = zone("aaa",
                     frame: WindowFrame(x: 0, y: 0, width: 500, height: 800),
                     activation: WindowFrame(x: 0, y: 0, width: 100, height: 100))
        let b = zone("bbb",
                     frame: WindowFrame(x: 500, y: 0, width: 500, height: 800),
                     activation: WindowFrame(x: 0, y: 0, width: 100, height: 100))

        #expect(DropzoneMap.zone(at: ScreenPoint(x: 50, y: 50), in: [a, b])?.zone.rawValue == "aaa")
        #expect(DropzoneMap.zone(at: ScreenPoint(x: 50, y: 50), in: [b, a])?.zone.rawValue == "aaa")
    }
}
