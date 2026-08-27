import Foundation
import Testing
@testable import OpenZonrCore

struct RuleEngineTests {

    struct MatchCase: Sendable {
        var match: WindowMatch
        var window: WindowSnapshot
        var expectedRuleID: RuleID?
    }

    private let engine = DefaultRuleEngine()
    private let defaultsWithoutFirstWindowConstraint = GlobalDefaults(onlyFirstWindowAfterLaunch: false)

    @Test(
        "Bundle Identifier wird exakt verglichen",
        arguments: [
            MatchCase(
                match: WindowMatch(bundleIdentifier: "com.example.editor"),
                window: TestConfigurations.window(bundleIdentifier: "com.example.editor"),
                expectedRuleID: "gefundene-regel"
            ),
            MatchCase(
                match: WindowMatch(bundleIdentifier: "com.example.editor"),
                window: TestConfigurations.window(bundleIdentifier: "com.example.chat"),
                expectedRuleID: nil
            ),
            MatchCase(
                match: WindowMatch(bundleIdentifier: "com.example.editor"),
                window: TestConfigurations.window(bundleIdentifier: nil),
                expectedRuleID: nil
            )
        ]
    )
    func bundleIdentifier(case testCase: MatchCase) {
        expectMatch(testCase)
    }

    @Test(
        "Titel-Pattern passt im Fenstertitel",
        arguments: [
            MatchCase(
                match: WindowMatch(titlePattern: "Nachricht|Compose"),
                window: TestConfigurations.window(title: "Neue Nachricht verfassen"),
                expectedRuleID: "gefundene-regel"
            ),
            MatchCase(
                match: WindowMatch(titlePattern: "Nachricht|Compose"),
                window: TestConfigurations.window(title: "Posteingang"),
                expectedRuleID: nil
            )
        ]
    )
    func titlePattern(case testCase: MatchCase) {
        expectMatch(testCase)
    }

    @Test(
        "Rollen werden als Erlaubnisliste ausgewertet",
        arguments: [
            MatchCase(
                match: WindowMatch(roles: ["AXWindow"]),
                window: TestConfigurations.window(role: "AXWindow"),
                expectedRuleID: "gefundene-regel"
            ),
            MatchCase(
                match: WindowMatch(roles: ["AXWindow"]),
                window: TestConfigurations.window(role: "AXDialog"),
                expectedRuleID: nil
            ),
            MatchCase(
                match: WindowMatch(roles: ["AXWindow"]),
                window: TestConfigurations.window(role: nil),
                expectedRuleID: nil
            ),
            MatchCase(
                match: WindowMatch(roles: []),
                window: TestConfigurations.window(role: "AXWindow"),
                expectedRuleID: nil
            )
        ]
    )
    func roles(case testCase: MatchCase) {
        expectMatch(testCase)
    }

    @Test(
        "Subrollen werden als Erlaubnisliste ausgewertet",
        arguments: [
            MatchCase(
                match: WindowMatch(subroles: ["AXStandardWindow"]),
                window: TestConfigurations.window(subrole: "AXStandardWindow"),
                expectedRuleID: "gefundene-regel"
            ),
            MatchCase(
                match: WindowMatch(subroles: ["AXStandardWindow"]),
                window: TestConfigurations.window(subrole: "AXDialog"),
                expectedRuleID: nil
            ),
            MatchCase(
                match: WindowMatch(subroles: ["AXStandardWindow"]),
                window: TestConfigurations.window(subrole: nil),
                expectedRuleID: nil
            ),
            MatchCase(
                match: WindowMatch(subroles: []),
                window: TestConfigurations.window(subrole: "AXStandardWindow"),
                expectedRuleID: nil
            )
        ]
    )
    func subroles(case testCase: MatchCase) {
        expectMatch(testCase)
    }

    @Test(
        "Mindestgröße muss erreicht werden",
        arguments: [
            MatchCase(
                match: WindowMatch(minimumSize: WindowSize(width: 800, height: 600)),
                window: TestConfigurations.window(frame: WindowFrame(x: 0, y: 0, width: 800, height: 600)),
                expectedRuleID: "gefundene-regel"
            ),
            MatchCase(
                match: WindowMatch(minimumSize: WindowSize(width: 800, height: 600)),
                window: TestConfigurations.window(frame: WindowFrame(x: 0, y: 0, width: 799, height: 600)),
                expectedRuleID: nil
            ),
            MatchCase(
                match: WindowMatch(minimumSize: WindowSize(width: 800, height: 600)),
                window: TestConfigurations.window(frame: WindowFrame(x: 0, y: 0, width: 800, height: 599)),
                expectedRuleID: nil
            )
        ]
    )
    func minimumSize(case testCase: MatchCase) {
        expectMatch(testCase)
    }

    @Test(
        "Maximalgröße darf nicht überschritten werden",
        arguments: [
            MatchCase(
                match: WindowMatch(maximumSize: WindowSize(width: 800, height: 600)),
                window: TestConfigurations.window(frame: WindowFrame(x: 0, y: 0, width: 800, height: 600)),
                expectedRuleID: "gefundene-regel"
            ),
            MatchCase(
                match: WindowMatch(maximumSize: WindowSize(width: 800, height: 600)),
                window: TestConfigurations.window(frame: WindowFrame(x: 0, y: 0, width: 801, height: 600)),
                expectedRuleID: nil
            ),
            MatchCase(
                match: WindowMatch(maximumSize: WindowSize(width: 800, height: 600)),
                window: TestConfigurations.window(frame: WindowFrame(x: 0, y: 0, width: 800, height: 601)),
                expectedRuleID: nil
            )
        ]
    )
    func maximumSize(case testCase: MatchCase) {
        expectMatch(testCase)
    }

    @Test(
        "Seitenverhältnis liegt im inklusiven Bereich",
        arguments: [
            MatchCase(
                match: WindowMatch(aspectRatio: AspectRatioRange(minimum: 1.0, maximum: 2.0)),
                window: TestConfigurations.window(frame: WindowFrame(x: 0, y: 0, width: 1200, height: 800)),
                expectedRuleID: "gefundene-regel"
            ),
            MatchCase(
                match: WindowMatch(aspectRatio: AspectRatioRange(minimum: 1.0, maximum: 2.0)),
                window: TestConfigurations.window(frame: WindowFrame(x: 0, y: 0, width: 500, height: 800)),
                expectedRuleID: nil
            ),
            MatchCase(
                match: WindowMatch(aspectRatio: AspectRatioRange(minimum: 1.0, maximum: 2.0)),
                window: TestConfigurations.window(frame: WindowFrame(x: 0, y: 0, width: 2400, height: 800)),
                expectedRuleID: nil
            ),
            MatchCase(
                match: WindowMatch(aspectRatio: AspectRatioRange(minimum: 1.0, maximum: 2.0)),
                window: TestConfigurations.window(frame: WindowFrame(x: 0, y: 0, width: 1200, height: 0)),
                expectedRuleID: nil
            )
        ]
    )
    func aspectRatio(case testCase: MatchCase) {
        expectMatch(testCase)
    }

    @Test(
        "Nur erstes Fenster nach App-Start beachtet Regel und Standardwert",
        arguments: [
            MatchCase(
                match: WindowMatch(onlyFirstWindowAfterLaunch: true),
                window: TestConfigurations.window(isFirstWindowAfterLaunch: true),
                expectedRuleID: "gefundene-regel"
            ),
            MatchCase(
                match: WindowMatch(onlyFirstWindowAfterLaunch: true),
                window: TestConfigurations.window(isFirstWindowAfterLaunch: false),
                expectedRuleID: nil
            ),
            MatchCase(
                match: WindowMatch(onlyFirstWindowAfterLaunch: false),
                window: TestConfigurations.window(isFirstWindowAfterLaunch: false),
                expectedRuleID: "gefundene-regel"
            ),
            MatchCase(
                match: WindowMatch(),
                window: TestConfigurations.window(isFirstWindowAfterLaunch: false),
                expectedRuleID: nil
            )
        ]
    )
    func onlyFirstWindowAfterLaunch(case testCase: MatchCase) {
        let defaults = testCase.match.onlyFirstWindowAfterLaunch == nil
            ? GlobalDefaults(onlyFirstWindowAfterLaunch: true)
            : defaultsWithoutFirstWindowConstraint
        expectMatch(testCase, defaults: defaults)
    }

    @Test("Mehrere Kriterien sind mit UND verknüpft")
    func combinedCriteriaUseAndSemantics() {
        let match = WindowMatch(
            bundleIdentifier: "com.example.editor",
            titlePattern: "Dokument",
            subroles: ["AXStandardWindow"],
            minimumSize: WindowSize(width: 800, height: 600),
            maximumSize: WindowSize(width: 1600, height: 1200),
            aspectRatio: AspectRatioRange(minimum: 1.0, maximum: 2.0),
            onlyFirstWindowAfterLaunch: true
        )

        let matchingWindow = TestConfigurations.window(
            bundleIdentifier: "com.example.editor",
            title: "Dokument 1",
            subrole: "AXStandardWindow",
            frame: WindowFrame(x: 0, y: 0, width: 1200, height: 800),
            isFirstWindowAfterLaunch: true
        )
        #expect(firstMatchID(for: matchingWindow, match: match) == "gefundene-regel")

        let nonMatchingWindow = TestConfigurations.window(
            bundleIdentifier: "com.example.editor",
            title: "Dokument 1",
            subrole: "AXDialog",
            frame: WindowFrame(x: 0, y: 0, width: 1200, height: 800),
            isFirstWindowAfterLaunch: true
        )
        #expect(firstMatchID(for: nonMatchingWindow, match: match) == nil)
    }

    @Test("Eine leere Match-Definition passt auf jedes Fenster")
    func emptyMatchMatchesEveryWindow() {
        let rules = CompiledRuleSet(rules: [rule(match: WindowMatch())])

        let window = TestConfigurations.window(
            bundleIdentifier: nil,
            title: nil,
            role: nil,
            subrole: nil,
            frame: WindowFrame(x: 0, y: 0, width: 0, height: 0),
            isFirstWindowAfterLaunch: false
        )

        #expect(engine.firstMatch(for: window, in: rules, defaults: defaultsWithoutFirstWindowConstraint)?.id == "gefundene-regel")
    }

    @Test("Eine deaktivierte Regel wird nie zurückgegeben")
    func disabledRuleIsNeverReturned() {
        let rules = CompiledRuleSet(rules: [
            rule(id: "deaktiviert", enabled: false, match: WindowMatch(bundleIdentifier: "com.example.editor"))
        ])

        let match = engine.firstMatch(
            for: TestConfigurations.window(bundleIdentifier: "com.example.editor"),
            in: rules,
            defaults: defaultsWithoutFirstWindowConstraint
        )

        #expect(match == nil)
    }

    @Test("Höhere Priorität gewinnt unabhängig von der Dateiposition")
    func higherPriorityWins() {
        let rules = CompiledRuleSet(rules: [
            rule(id: "niedrig", priority: 10, match: WindowMatch()),
            rule(id: "hoch", priority: 20, match: WindowMatch())
        ])

        #expect(engine.firstMatch(
            for: TestConfigurations.window(),
            in: rules,
            defaults: defaultsWithoutFirstWindowConstraint
        )?.id == "hoch")
    }

    @Test("Gleiche Priorität bleibt in Dateireihenfolge stabil")
    func equalPriorityKeepsFileOrder() {
        let rules = CompiledRuleSet(rules: [
            rule(id: "erste", priority: 10, match: WindowMatch()),
            rule(id: "zweite", priority: 10, match: WindowMatch()),
            rule(id: "dritte", priority: 10, match: WindowMatch())
        ])

        #expect(rules.entries.map(\.rule.id) == ["erste", "zweite", "dritte"])
        #expect(engine.firstMatch(
            for: TestConfigurations.window(),
            in: rules,
            defaults: defaultsWithoutFirstWindowConstraint
        )?.id == "erste")
    }

    @Test("Die Beispielkonfiguration wertet Outlook spezifisch vor generisch aus")
    func exampleOutlookRulesPreferSpecificComposeRule() throws {
        let configuration = try TestConfigurations.example()
        let rules = CompiledRuleSet(rules: configuration.rules)

        let composeWindow = TestConfigurations.window(
            bundleIdentifier: "com.microsoft.Outlook",
            title: "Nachricht verfassen",
            subrole: "AXStandardWindow",
            frame: WindowFrame(x: 0, y: 0, width: 900, height: 700),
            isFirstWindowAfterLaunch: false
        )
        #expect(engine.firstMatch(for: composeWindow, in: rules, defaults: configuration.defaults)?.id == "outlook-compose")

        let mainWindow = TestConfigurations.window(
            bundleIdentifier: "com.microsoft.Outlook",
            title: "Posteingang",
            subrole: "AXStandardWindow",
            frame: WindowFrame(x: 0, y: 0, width: 1200, height: 800),
            isFirstWindowAfterLaunch: true
        )
        #expect(engine.firstMatch(for: mainWindow, in: rules, defaults: configuration.defaults)?.id == "outlook-main")
    }

    @Test("Ein Fenster ohne Titel passt nur auf Regeln ohne Titel-Pattern")
    func untitledWindowSkipsTitlePatternRules() {
        let rules = CompiledRuleSet(rules: [
            rule(id: "mit-pattern", priority: 20, match: WindowMatch(titlePattern: "Dokument")),
            rule(id: "ohne-pattern", priority: 10, match: WindowMatch())
        ])

        #expect(engine.firstMatch(
            for: TestConfigurations.window(title: nil),
            in: rules,
            defaults: defaultsWithoutFirstWindowConstraint
        )?.id == "ohne-pattern")
    }

    @Test("Ein ungültiger regulärer Ausdruck deaktiviert nur die eigene Regel")
    func invalidPatternDisablesOnlyItsRule() throws {
        let rules = CompiledRuleSet(rules: [
            rule(id: "kaputtes-pattern", priority: 100, match: WindowMatch(titlePattern: "[")),
            rule(id: "gueltige-regel", priority: 10, match: WindowMatch(bundleIdentifier: "com.example.editor"))
        ])

        let unusable = try #require(rules.unusableRules.first)
        #expect(unusable.rule == "kaputtes-pattern")
        #expect(rules.unusableRules.count == 1)
        #expect(engine.firstMatch(
            for: TestConfigurations.window(bundleIdentifier: "com.example.editor"),
            in: rules,
            defaults: defaultsWithoutFirstWindowConstraint
        )?.id == "gueltige-regel")
    }

    private func expectMatch(_ testCase: MatchCase, defaults: GlobalDefaults? = nil) {
        #expect(firstMatchID(
            for: testCase.window,
            match: testCase.match,
            defaults: defaults ?? defaultsWithoutFirstWindowConstraint
        ) == testCase.expectedRuleID)
    }

    private func firstMatchID(
        for window: WindowSnapshot,
        match: WindowMatch,
        defaults: GlobalDefaults? = nil
    ) -> RuleID? {
        let rules = CompiledRuleSet(rules: [rule(match: match)])
        return engine.firstMatch(
            for: window,
            in: rules,
            defaults: defaults ?? defaultsWithoutFirstWindowConstraint
        )?.id
    }

    private func rule(
        id: RuleID = "gefundene-regel",
        enabled: Bool = true,
        priority: Int = 0,
        match: WindowMatch
    ) -> PlacementRule {
        PlacementRule(
            id: id,
            name: id.rawValue,
            enabled: enabled,
            priority: priority,
            match: match,
            action: PlacementAction(role: "editor")
        )
    }
}
