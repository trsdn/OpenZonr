import Foundation
import Testing

@testable import OpenZonrCore

/// Der Plan muss beides hergeben: die Trefferflächen aller Zonen der Ebene (für
/// die Konturen) und den Zielrahmen der getroffenen (für die Füllung).
@Suite("Overlay-Plan — Trefferflächen")
struct DropzoneOverlayPlanActivationTests {

    private static let visible = VisibleFrame(x: 0, y: 0, width: 1000, height: 800)

    private func zone(_ id: String, frame: WindowFrame, activation: WindowFrame) -> Dropzone {
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

    @Test("Der Plan trägt Trefferflächen und getroffenen Zielrahmen getrennt")
    func planCarriesBoth() {
        let zones = [
            zone("ganz",
                 frame: WindowFrame(x: 600, y: 0, width: 400, height: 800),
                 activation: WindowFrame(x: 600, y: 350, width: 400, height: 100)),
            zone("oben",
                 frame: WindowFrame(x: 600, y: 400, width: 400, height: 400),
                 activation: WindowFrame(x: 600, y: 700, width: 400, height: 100))
        ]
        let plan = DropzoneOverlayPlan.Plan.show(
            zones: zones,
            highlighted: DropzoneMap.zone(at: ScreenPoint(x: 700, y: 400), in: zones)
        )

        // Konturen: alle Trefferflächen der Ebene.
        #expect(plan.zones.map(\.activationFrame) == [
            WindowFrame(x: 600, y: 350, width: 400, height: 100),
            WindowFrame(x: 600, y: 700, width: 400, height: 100)
        ])
        // Füllung: der Zielrahmen der getroffenen Zone, nicht ihr Streifen.
        #expect(plan.highlighted?.frame == WindowFrame(x: 600, y: 0, width: 400, height: 800))
        #expect(plan.highlighted?.zone.rawValue == "ganz")
    }
}
