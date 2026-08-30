import Foundation
import Testing
@testable import OpenZonrCore

/// Prüft die zwei getrennten Fassungen aus dem Nachtrag zu Issue #19: mit
/// echtem Fenster ist die Auskunft eine Messung, ohne Fenster eine
/// ausgewiesene Teilauskunft.
struct DryRunPreviewTests {

    // MARK: - Fall A: mit Fenster

    @Test("Fall A: passender Snapshot ergibt eine exakte Vorschau mit aufgelöstem Rahmen")
    func fallA_matchesWithExactPlacement() {
        let configuration = TestConfigurations.minimal { config in
            // Erstfenster-Voreinstellung aus dem Weg räumen, damit die
            // Standard-Fenstermaße durchgehen.
            config.defaults.onlyFirstWindowAfterLaunch = false
        }
        let snapshots = [DryRunTestFixtures.mainSnapshot()]
        let window = TestConfigurations.window(
            bundleIdentifier: "com.example.editor",
            isFirstWindowAfterLaunch: false
        )

        let result = DryRunPreview.evaluate(
            window: window,
            configuration: configuration,
            snapshots: snapshots
        )

        guard case let .matches(match) = result else {
            Issue.record("Erwartet: matches, bekam \(result)")
            return
        }
        #expect(match.rule.id == "editor-rule")
        #expect(!match.isConditional)
        #expect(match.placement?.zone == "left")
        // Ein aufgelöster Rahmen ist eine echte Zahl in Punkten — der Sinn
        // der Zeile: „2560 × 1344 pt".
        #expect(match.placement?.frame.width == snapshots[0].visibleFrame.width * 0.5)
    }

    @Test("Fall A: kein Snapshot passt zu einer Regel → noMatch")
    func fallA_noMatchingRule() {
        let configuration = TestConfigurations.minimal { config in
            config.defaults.onlyFirstWindowAfterLaunch = false
        }
        let window = TestConfigurations.window(bundleIdentifier: "com.example.stranger")

        let result = DryRunPreview.evaluate(
            window: window,
            configuration: configuration,
            snapshots: [DryRunTestFixtures.mainSnapshot()]
        )
        #expect(result == .noMatch)
    }

    @Test("Fall A: der globale Filter lehnt das Fenster ab → noMatch, keine Regel greift")
    func fallA_windowFilterRejectsWindow() {
        let configuration = TestConfigurations.minimal { config in
            config.defaults.onlyFirstWindowAfterLaunch = false
            config.defaults.minimumWindowSize = WindowSize(width: 400, height: 300)
        }
        let winzig = TestConfigurations.window(
            bundleIdentifier: "com.example.editor",
            frame: WindowFrame(x: 0, y: 0, width: 100, height: 80),
            isFirstWindowAfterLaunch: false
        )

        let result = DryRunPreview.evaluate(
            window: winzig,
            configuration: configuration,
            snapshots: [DryRunTestFixtures.mainSnapshot()]
        )
        #expect(result == .noMatch)
    }

    // MARK: - Fall B: nur Bundle

    @Test("Fall B: Regel prüft nur die Bundle-Kennung → keine ungeprüften Kriterien, Antwort ist keine Vermutung")
    func fallB_bundleOnlyRuleIsExact() {
        let configuration = TestConfigurations.minimal { config in
            config.defaults.onlyFirstWindowAfterLaunch = false
        }

        let result = DryRunPreview.evaluate(
            bundleIdentifier: "com.example.editor",
            configuration: configuration,
            snapshots: [DryRunTestFixtures.mainSnapshot()]
        )
        guard case let .matches(match) = result else {
            Issue.record("Erwartet: matches, bekam \(result)")
            return
        }
        #expect(match.rule.id == "editor-rule")
        #expect(!match.isConditional)
        #expect(match.report.undecidable.isEmpty)
        // Ohne Fenster kann trotzdem eine Zone benannt werden, wenn die
        // Snapshots reichen.
        #expect(match.placement?.zone == "left")
    }

    @Test("Fall B: Regel prüft zusätzlich den Titel → Antwort ist bedingt und meldet den Titel als ungeprüft")
    func fallB_titleRuleIsConditional() {
        let configuration = TestConfigurations.minimal { config in
            config.defaults.onlyFirstWindowAfterLaunch = false
            // Titel-Kriterium auf die Editor-Regel setzen — das ist genau die
            // Änderung, an der ein naiver Dry-Run still falsch würde.
            let regel = PlacementRule(
                id: "editor-rule",
                name: "Editor mit Titel",
                priority: 10,
                match: WindowMatch(
                    bundleIdentifier: "com.example.editor",
                    titlePattern: "^Notizen"
                ),
                action: PlacementAction(role: "editor")
            )
            config = config.updating(rule: regel)
        }

        let result = DryRunPreview.evaluate(
            bundleIdentifier: "com.example.editor",
            configuration: configuration
        )
        guard case let .matches(match) = result else {
            Issue.record("Erwartet: matches, bekam \(result)")
            return
        }
        #expect(match.isConditional, "Titel ist ungeprüft — die Auskunft ist bedingt")
        #expect(match.report.undecidable.contains(.title(pattern: "^Notizen")))
    }

    @Test("Fall B: keine Regel kennt das Bundle → noMatch")
    func fallB_noRuleKnowsBundle() {
        let configuration = TestConfigurations.minimal()

        let result = DryRunPreview.evaluate(
            bundleIdentifier: "com.example.stranger",
            configuration: configuration
        )
        #expect(result == .noMatch)
    }

    @Test("Fall B: höhere Priorität gewinnt — die Auswertungsreihenfolge muss stimmen")
    func fallB_higherPriorityRuleWins() {
        var configuration = TestConfigurations.minimal()
        configuration = configuration.adding(rule: PlacementRule(
            id: "editor-notizen",
            name: "Notizen zuerst",
            priority: 100,
            match: WindowMatch(
                bundleIdentifier: "com.example.editor",
                titlePattern: "^Notizen"
            ),
            action: PlacementAction(role: "communication")
        ))

        let result = DryRunPreview.evaluate(
            bundleIdentifier: "com.example.editor",
            configuration: configuration
        )
        guard case let .matches(match) = result else {
            Issue.record("Erwartet: matches")
            return
        }
        // Die höher priorisierte Regel gewinnt. Da sie einen Titel prüft, ist
        // die Auskunft bedingt — trotzdem darf sie nicht durch eine niedriger
        // priorisierte, exaktere Regel ersetzt werden. Sonst hätte man sich
        // eine hilfreiche Antwort erschlichen und das echte Verhalten der
        // Engine nachgezeichnet.
        #expect(match.rule.id == "editor-notizen")
        #expect(match.isConditional)
    }
}

/// Fixtures für Bildschirme, nur für Tests dieser Datei sinnvoll.
enum DryRunTestFixtures {
    /// Ein einzelner Bildschirm, dessen `identity` zum Fingerprint des
    /// „solo"-Profils aus ``TestConfigurations/minimal()`` passt.
    static func mainSnapshot() -> DisplaySnapshot {
        DisplaySnapshot(
            identity: .builtin,
            localizedName: "Hauptbildschirm",
            displayID: 1,
            pixelWidth: 2560,
            pixelHeight: 1600,
            backingScaleFactor: 2,
            frame: WindowFrame(x: 0, y: 0, width: 2560, height: 1600),
            visibleFrame: WindowFrame(x: 0, y: 65, width: 2560, height: 1344),
            isPrimary: true
        )
    }
}
