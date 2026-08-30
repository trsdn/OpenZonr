import Foundation
import Testing

@testable import OpenZonrCore

/// Belegt, dass Vorlagen ohne Naht schließen, Kennungen stabil sind und die
/// Vorschau vor der Anwendung nennt, welche Bindungen ins Leere zeigen
/// würden.
struct LayoutTemplateTests {

    @Test("Jede Vorlage deckt die Fläche exakt")
    func everyTemplateCoversExactly() {
        for template in LayoutTemplate.allCases {
            let frames = template.zones.map(\.frame)
            let uncovered = LayoutCoverage.uncovered(zones: frames)
            #expect(uncovered.isEmpty, "\(template) hat Lücken: \(uncovered)")
        }
    }

    @Test("Zonenkennungen einer Vorlage sind stabil")
    func templateZoneIDsAreStable() {
        // Wer eine Vorlage zweimal anwendet, bekommt zweimal dieselben
        // Kennungen; sonst würden Bindungen still ins Leere zeigen, ohne dass
        // jemand daran gedreht hätte.
        let first = LayoutTemplate.thirds.zones.map(\.id)
        let second = LayoutTemplate.thirds.zones.map(\.id)
        #expect(first == second)
    }

    @Test("Anwenden ersetzt die Zonen des Layouts, nicht der anderen Layouts")
    func applyingReplacesOnlyTheTargetLayout() {
        var config = TestConfigurations.minimal()
        // Zweites Layout ergänzen, damit der Test beweisen kann, dass es
        // unangetastet bleibt.
        let display: DisplayAlias = "main"
        let secondLayout = Layout(
            id: "single",
            name: "Ganz",
            zones: [Zone(id: "full", name: "Ganz", frame: RelativeRect(x: 0, y: 0, width: 1, height: 1))]
        )
        config.displays[0].layouts.append(secondLayout)

        let updated = config.applying(template: .thirds, layout: "halves", display: display)
        let updatedA = updated.displays[0].layouts[0]
        let updatedB = updated.displays[0].layouts[1]
        #expect(updatedA.zones.map(\.id) == LayoutTemplate.thirds.zones.map(\.id))
        #expect(updatedB.zones == secondLayout.zones)
    }

    @Test("Vorschau nennt Bindungen, die nach der Anwendung hängen würden")
    func previewNamesDanglingBindings() {
        // Die minimale Konfiguration bindet die Rolle „editor" an die Zone
        // „left" des Layouts „halves". Vorlage „thirds" hat diese Kennung
        // nicht — die Bindung würde nach der Anwendung hängen, und genau das
        // muss die Vorschau vorher sagen.
        let config = TestConfigurations.minimal()
        let preview = config.previewApplying(template: .thirds, layout: "halves", display: "main")

        #expect(preview.removedZones.contains("left"))
        #expect(preview.removedZones.contains("right"))
        let editorBinding = preview.danglingBindings.first { $0.role == "editor" }
        #expect(editorBinding?.zone == "left")
        let commsBinding = preview.danglingBindings.first { $0.role == "communication" }
        #expect(commsBinding?.zone == "right")
    }
}
