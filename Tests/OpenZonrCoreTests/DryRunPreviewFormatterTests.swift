import Foundation
import Testing
@testable import OpenZonrCore

/// Prüft die textuelle Wiedergabe: dass der Editor keine Vermutung als
/// Messung ausgibt und im Bedingt-Fall den ungeprüften Teil benennt.
struct DryRunPreviewFormatterTests {

    @Test("noMatch: die Zeile sagt schlicht, dass nichts greift")
    func noMatch() {
        let line = DryRunPreviewFormatter.line(
            for: .noMatch,
            subject: "Dieses Fenster",
            configuration: TestConfigurations.minimal()
        )
        #expect(line.headline.contains("keine Regel greift"))
        #expect(line.caveats.isEmpty)
        #expect(!line.isConditional)
    }

    @Test("Fall A: die Zeile nennt Zone, Bildschirm, Regel, Priorität und Punktmaß")
    func fallA_richLine() {
        let configuration = TestConfigurations.minimal { config in
            config.defaults.onlyFirstWindowAfterLaunch = false
        }
        let result = DryRunPreview.evaluate(
            window: TestConfigurations.window(
                bundleIdentifier: "com.example.editor",
                isFirstWindowAfterLaunch: false
            ),
            configuration: configuration,
            snapshots: [DryRunTestFixtures.mainSnapshot()]
        )
        let line = DryRunPreviewFormatter.line(
            for: result,
            subject: "Dieses Fenster",
            configuration: configuration
        )
        #expect(line.headline.contains("Links"))
        #expect(line.headline.contains("Hauptbildschirm"))
        #expect(line.headline.contains("Editor"))
        #expect(line.headline.contains("Priorität 10"))
        #expect(line.headline.contains("pt"))
        #expect(!line.isConditional)
        #expect(line.caveats.isEmpty)
    }

    @Test("Fall B mit Titel: Zeile ist bedingt und benennt den Fenstertitel als ungeprüft")
    func fallB_conditionalListsCaveat() {
        var configuration = TestConfigurations.minimal { config in
            config.defaults.onlyFirstWindowAfterLaunch = false
        }
        configuration = configuration.updating(rule: PlacementRule(
            id: "editor-rule",
            name: "Editor mit Titel",
            priority: 10,
            match: WindowMatch(
                bundleIdentifier: "com.example.editor",
                titlePattern: "^Notizen"
            ),
            action: PlacementAction(role: "editor")
        ))

        let result = DryRunPreview.evaluate(
            bundleIdentifier: "com.example.editor",
            configuration: configuration,
            snapshots: [DryRunTestFixtures.mainSnapshot()]
        )
        let line = DryRunPreviewFormatter.line(
            for: result,
            subject: "com.example.editor",
            configuration: configuration
        )
        #expect(line.isConditional)
        #expect(line.caveats.contains(where: { $0.contains("Fenstertitel") }))
    }

    @Test("Fall B ohne Snapshot: die Zeile bleibt ehrlich — nur Rolle und Regel, kein Punktmaß")
    func fallB_withoutSnapshotIsHonest() {
        let configuration = TestConfigurations.minimal { config in
            config.defaults.onlyFirstWindowAfterLaunch = false
        }

        let result = DryRunPreview.evaluate(
            bundleIdentifier: "com.example.editor",
            configuration: configuration
        )
        let line = DryRunPreviewFormatter.line(
            for: result,
            subject: "com.example.editor",
            configuration: configuration
        )
        // Ohne Snapshots gibt es keine „Nnn × Nnn pt"-Behauptung.
        #expect(!line.headline.contains(" pt"))
        // Aber die Rolle, in die das Fenster ginge, wird benannt.
        #expect(line.headline.contains("Editor"))
    }
}
