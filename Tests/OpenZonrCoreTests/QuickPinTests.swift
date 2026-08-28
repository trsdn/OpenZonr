import Foundation
import Testing
@testable import OpenZonrCore

/// „Diese App immer hier öffnen" is the one path through the configuration that
/// nobody sees while using it — no field, no form, no term. That is exactly why
/// it needs the most tests: a wrong priority or a duplicated rule would be
/// invisible until an application opens in the wrong place weeks later.
struct QuickPinTests {

    private func request(
        bundle: String = "com.microsoft.Outlook",
        name: String = "Outlook",
        zone: ZoneID = "right"
    ) -> QuickPin.Request {
        QuickPin.Request(
            bundleIdentifier: bundle,
            applicationName: name,
            profile: "solo",
            target: QuickPin.Target(display: "main", zone: zone)
        )
    }

    // MARK: - The happy path

    @Test("Der Vorgang erzeugt eine Regel, die auf die Zone unter dem Fenster zeigt")
    func pinCreatesRuleAndBinding() throws {
        let outcome = try QuickPin.pin(request(), into: TestConfigurations.minimal())
        let configuration = outcome.configuration

        let rule = try #require(configuration.rules.first { $0.id == outcome.rule })
        #expect(rule.match.bundleIdentifier == "com.microsoft.Outlook")
        #expect(rule.enabled)

        // Die Regel zeigt auf eine Rolle, die Rolle über die Bindung des aktiven
        // Profils auf genau die gewählte Zone.
        let binding = try #require(configuration.profiles[0].roleBindings.first { $0.role == rule.action.role })
        #expect(binding.display == "main")
        #expect(binding.zone == "right")

        #expect(ConfigurationValidator().validate(configuration).errors.isEmpty)
    }

    @Test("Eine vorhandene Bindung auf dieselbe Zone wird wiederverwendet")
    func existingRoleIsReused() throws {
        // "communication" ist im Minimalprofil bereits an main/right gebunden.
        let outcome = try QuickPin.pin(request(), into: TestConfigurations.minimal())

        #expect(outcome.role == "communication")
        #expect(outcome.createdRole == false)
        #expect(outcome.configuration.roles.count == 2)
    }

    @Test("Für eine ungebundene Zone entsteht eine Rolle mit dem Namen der Zone")
    func unboundZoneGetsANewRole() throws {
        let configuration = TestConfigurations.minimal {
            $0.profiles[0].roleBindings = [RoleBinding(role: "editor", display: "main", zone: "left")]
        }

        let outcome = try QuickPin.pin(request(), into: configuration)

        #expect(outcome.createdRole)
        #expect(outcome.role == "rechts")
        #expect(outcome.configuration.roles.contains { $0.id == "rechts" && $0.name == "Rechts" })
        #expect(outcome.configuration.profiles[0].roleBindings.contains {
            $0.role == "rechts" && $0.zone == "right"
        })
    }

    // MARK: - Pressing it twice

    @Test("Zweimal festhalten erzeugt keine zweite Regel")
    func pinningTwiceRetargets() throws {
        let first = try QuickPin.pin(request(bundle: "com.example.editor", name: "Editor"), into: TestConfigurations.minimal())
        let second = try QuickPin.pin(
            request(bundle: "com.example.editor", name: "Editor", zone: "left"),
            into: first.configuration
        )

        #expect(second.reusedRule)
        #expect(second.configuration.rules.count == TestConfigurations.minimal().rules.count)
        #expect(second.configuration.rules.filter { $0.match.bundleIdentifier == "com.example.editor" }.count == 1)

        let rule = try #require(second.configuration.rules.first { $0.id == second.rule })
        #expect(rule.action.role == "editor")
    }

    @Test("Eine abgeschaltete Regel wird wieder eingeschaltet statt verdoppelt")
    func disabledRuleIsRevived() throws {
        let configuration = TestConfigurations.minimal().settingRule("editor-rule", enabled: false)

        let outcome = try QuickPin.pin(request(bundle: "com.example.editor", name: "Editor"), into: configuration)

        #expect(outcome.rule == "editor-rule")
        #expect(outcome.configuration.rules.first { $0.id == "editor-rule" }?.enabled == true)
    }

    @Test("Eine Regel mit Titelmuster wird nicht umgehängt")
    func specificRuleIsLeftAlone() throws {
        let configuration = TestConfigurations.minimal {
            $0.rules.append(
                PlacementRule(
                    id: "editor-compose",
                    name: "Verfassen",
                    priority: 200,
                    match: WindowMatch(bundleIdentifier: "com.example.editor", titlePattern: "^Verfassen"),
                    action: PlacementAction(role: "communication")
                )
            )
            $0.rules.removeAll { $0.id == "editor-rule" }
        }

        let outcome = try QuickPin.pin(request(bundle: "com.example.editor", name: "Editor"), into: configuration)

        #expect(outcome.reusedRule == false)
        // Die von Hand geschriebene Regel bleibt unangetastet und behält ihren Vorrang.
        let compose = try #require(outcome.configuration.rules.first { $0.id == "editor-compose" })
        #expect(compose.action.role == "communication")
        #expect(compose.priority > (outcome.configuration.rules.first { $0.id == outcome.rule }?.priority ?? 0))
    }

    // MARK: - Priority

    @Test("Die neue Regel gewinnt gegen eine Auffangregel")
    func newRuleOutranksCatchAll() throws {
        let configuration = TestConfigurations.minimal {
            $0.rules = [
                PlacementRule(
                    id: "catch-all",
                    name: "Alles Übrige",
                    priority: 500,
                    match: WindowMatch(),
                    action: PlacementAction(role: "editor")
                )
            ]
        }

        let outcome = try QuickPin.pin(request(), into: configuration)
        let rule = try #require(outcome.configuration.rules.first { $0.id == outcome.rule })

        #expect(rule.priority > 500)
        // Und die Gegenprobe an der Engine selbst, statt nur an der Zahl.
        let match = DefaultRuleEngine().firstMatch(
            for: TestConfigurations.window(bundleIdentifier: "com.microsoft.Outlook"),
            in: CompiledRuleSet(rules: outcome.configuration.rules),
            defaults: outcome.configuration.defaults
        )
        #expect(match?.id == outcome.rule)
    }

    @Test("Regeln anderer Apps treiben die Priorität nicht hoch")
    func unrelatedRulesDoNotInflatePriority() throws {
        let configuration = TestConfigurations.minimal {
            $0.rules = [
                PlacementRule(
                    id: "fremd",
                    name: "Fremd",
                    priority: 9000,
                    match: WindowMatch(bundleIdentifier: "com.example.andere"),
                    action: PlacementAction(role: "editor")
                )
            ]
        }

        let outcome = try QuickPin.pin(request(), into: configuration)
        let rule = try #require(outcome.configuration.rules.first { $0.id == outcome.rule })

        #expect(rule.priority == Configuration.rulePriorityStep)
    }

    // MARK: - Retargeting has to keep the same promise

    /// The case found in review: pinning an app a second time used to set the
    /// role and leave the priority alone. If a catch-all rule had appeared above
    /// it in the meantime, the retargeted rule never fired — and the user was
    /// told it now points at the new zone.
    @Test("Eine umgehängte Regel steigt über eine dazugekommene Auffangregel")
    func retargetedRuleOutranksACatchAllAddedLater() throws {
        let configuration = TestConfigurations.minimal {
            $0.rules = [
                PlacementRule(
                    id: "editor-rule",
                    name: "Editor",
                    priority: 10,
                    match: WindowMatch(bundleIdentifier: "com.example.editor"),
                    action: PlacementAction(role: "editor")
                ),
                PlacementRule(
                    id: "catch-all",
                    name: "Alles Übrige",
                    priority: 500,
                    match: WindowMatch(),
                    action: PlacementAction(role: "editor")
                )
            ]
        }

        // Gegenprobe vorher: die Auffangregel gewinnt, die App-Regel ist tot.
        let before = DefaultRuleEngine().firstMatch(
            for: TestConfigurations.window(bundleIdentifier: "com.example.editor"),
            in: CompiledRuleSet(rules: configuration.rules),
            defaults: configuration.defaults
        )
        #expect(before?.id == "catch-all")

        let outcome = try QuickPin.pin(
            request(bundle: "com.example.editor", name: "Editor", zone: "right"),
            into: configuration
        )
        #expect(outcome.reusedRule)

        let rule = try #require(outcome.configuration.rules.first { $0.id == outcome.rule })
        #expect(rule.priority > 500)

        // Und die Gegenprobe an der Engine: die Zusage stimmt jetzt.
        let after = DefaultRuleEngine().firstMatch(
            for: TestConfigurations.window(bundleIdentifier: "com.example.editor"),
            in: CompiledRuleSet(rules: outcome.configuration.rules),
            defaults: outcome.configuration.defaults
        )
        #expect(after?.id == outcome.rule)

        // Und der Validator hat nichts mehr zu melden.
        let shadowed = ConfigurationValidator().validate(outcome.configuration).findings
            .filter { $0.code == .shadowedRule && $0.path == ConfigurationPath.rule(outcome.rule) }
        #expect(shadowed.isEmpty)
    }

    @Test("Auch bei Gleichstand steigt die umgehängte Regel, weil sonst die Dateireihenfolge entscheidet")
    func retargetedRuleAlsoClimbsOnEqualPriority() throws {
        let configuration = TestConfigurations.minimal {
            $0.rules = [
                PlacementRule(
                    id: "catch-all",
                    name: "Alles Übrige",
                    priority: 10,
                    match: WindowMatch(),
                    action: PlacementAction(role: "editor")
                ),
                PlacementRule(
                    id: "editor-rule",
                    name: "Editor",
                    priority: 10,
                    match: WindowMatch(bundleIdentifier: "com.example.editor"),
                    action: PlacementAction(role: "editor")
                )
            ]
        }

        let outcome = try QuickPin.pin(
            request(bundle: "com.example.editor", name: "Editor", zone: "right"),
            into: configuration
        )

        let match = DefaultRuleEngine().firstMatch(
            for: TestConfigurations.window(bundleIdentifier: "com.example.editor"),
            in: CompiledRuleSet(rules: outcome.configuration.rules),
            defaults: outcome.configuration.defaults
        )
        #expect(match?.id == outcome.rule)
    }

    @Test("Eine wiedereingeschaltete Regel, die überdeckt war, greift danach wirklich")
    func revivedRuleActuallyFires() throws {
        let configuration = TestConfigurations.minimal {
            $0.rules = [
                PlacementRule(
                    id: "editor-rule",
                    name: "Editor",
                    enabled: false,
                    priority: 10,
                    match: WindowMatch(bundleIdentifier: "com.example.editor"),
                    action: PlacementAction(role: "editor")
                ),
                PlacementRule(
                    id: "catch-all",
                    name: "Alles Übrige",
                    priority: 300,
                    match: WindowMatch(),
                    action: PlacementAction(role: "editor")
                )
            ]
        }

        let outcome = try QuickPin.pin(
            request(bundle: "com.example.editor", name: "Editor", zone: "right"),
            into: configuration
        )

        let rule = try #require(outcome.configuration.rules.first { $0.id == outcome.rule })
        #expect(rule.enabled)

        let match = DefaultRuleEngine().firstMatch(
            for: TestConfigurations.window(bundleIdentifier: "com.example.editor"),
            in: CompiledRuleSet(rules: outcome.configuration.rules),
            defaults: outcome.configuration.defaults
        )
        #expect(match?.id == outcome.rule)
    }

    /// The counterweight to the three tests above: climbing must happen only
    /// when it is needed, or the numbers grow by ten on every single click.
    @Test("Ohne Konkurrenz bleibt die Priorität beim Umhängen unverändert")
    func retargetingWithoutCompetitionLeavesPriorityAlone() throws {
        let configuration = TestConfigurations.minimal {
            $0.rules = [
                PlacementRule(
                    id: "editor-rule",
                    name: "Editor",
                    priority: 40,
                    match: WindowMatch(bundleIdentifier: "com.example.editor"),
                    action: PlacementAction(role: "editor")
                )
            ]
        }

        var current = configuration
        for _ in 0..<3 {
            current = try QuickPin.pin(
                request(bundle: "com.example.editor", name: "Editor", zone: "right"),
                into: current
            ).configuration
        }

        #expect(current.rules.first { $0.id == "editor-rule" }?.priority == 40)
    }

    // MARK: - The pin refusing to promise an effect

    /// The pin has no field to hang a finding under, so its only honest answer
    /// to a blocking finding is to refuse. These tests pin down which findings
    /// count — refusing on every warning would make the feature unusable.
    @Test("Ohne Befund gibt es keinen Einwand")
    func cleanOutcomeHasNoObjection() throws {
        let outcome = try QuickPin.pin(request(), into: TestConfigurations.minimal())
        let report = ConfigurationValidator().validate(outcome.configuration)

        #expect(QuickPin.objection(to: outcome, report: report) == nil)
    }

    @Test("Eine überdeckte Regel führt zum Einwand statt zur Erfolgsmeldung")
    func shadowedRuleObjects() throws {
        let outcome = try QuickPin.pin(request(), into: TestConfigurations.minimal())
        // Eine Auffangregel, die genau diese Regel überdeckt, nachträglich davor.
        var configuration = outcome.configuration
        configuration.rules.insert(
            PlacementRule(
                id: "catch-all",
                name: "Alles Übrige",
                priority: 10_000,
                match: WindowMatch(),
                action: PlacementAction(role: "editor")
            ),
            at: 0
        )
        let report = ConfigurationValidator().validate(configuration)

        let objection = try #require(QuickPin.objection(to: outcome, report: report))
        #expect(objection.contains("überdeckt"))
    }

    @Test("Eine Überdeckung an einer fremden Regel geht den Vorgang nichts an")
    func shadowedOtherRuleDoesNotObject() throws {
        let outcome = try QuickPin.pin(request(), into: TestConfigurations.minimal())
        var configuration = outcome.configuration
        configuration.rules.insert(
            PlacementRule(
                id: "fremd-oben",
                name: "Fremd oben",
                priority: 10_000,
                match: WindowMatch(bundleIdentifier: "com.example.editor"),
                action: PlacementAction(role: "editor")
            ),
            at: 0
        )
        let report = ConfigurationValidator().validate(configuration)

        // „editor-rule" ist jetzt überdeckt — aber nicht die festgehaltene Regel.
        #expect(report.findings.contains { $0.code == .shadowedRule })
        #expect(QuickPin.objection(to: outcome, report: report) == nil)
    }

    @Test("Ein Fehler irgendwo im Dokument führt zum Einwand")
    func anyErrorObjects() throws {
        let outcome = try QuickPin.pin(request(), into: TestConfigurations.minimal())
        var configuration = outcome.configuration
        configuration.rules.append(
            PlacementRule(
                id: "kaputt",
                name: "Kaputt",
                priority: 1,
                match: WindowMatch(bundleIdentifier: "com.example.x"),
                action: PlacementAction(role: "gibt-es-nicht")
            )
        )
        let report = ConfigurationValidator().validate(configuration)

        #expect(report.errors.isEmpty == false)
        #expect(QuickPin.objection(to: outcome, report: report) != nil)
    }

    // MARK: - Refusals

    @Test("Ohne Bundle-Kennung wird abgelehnt, nicht geraten")
    func emptyBundleIsRefused() {
        #expect(throws: QuickPin.Failure.missingBundleIdentifier) {
            try QuickPin.pin(request(bundle: ""), into: TestConfigurations.minimal())
        }
    }

    @Test("Ein unbekanntes Ziel wird benannt, nicht verschluckt")
    func unknownTargetsAreNamed() {
        #expect(throws: QuickPin.Failure.unknownZone("gibt-es-nicht", display: "main")) {
            try QuickPin.pin(request(zone: "gibt-es-nicht"), into: TestConfigurations.minimal())
        }
        #expect(throws: QuickPin.Failure.unknownProfile("fremd")) {
            try QuickPin.pin(
                QuickPin.Request(
                    bundleIdentifier: "com.example.editor",
                    applicationName: "Editor",
                    profile: "fremd",
                    target: QuickPin.Target(display: "main", zone: "left")
                ),
                into: TestConfigurations.minimal()
            )
        }
        #expect(throws: QuickPin.Failure.unknownDisplay("fremd")) {
            try QuickPin.pin(
                QuickPin.Request(
                    bundleIdentifier: "com.example.editor",
                    applicationName: "Editor",
                    profile: "solo",
                    target: QuickPin.Target(display: "fremd", zone: "left")
                ),
                into: TestConfigurations.minimal()
            )
        }
    }

    // MARK: - Round trip through the store

    @Test("Festhalten, speichern, neu laden — und die Regel greift")
    func pinSurvivesTheStore() throws {
        let outcome = try QuickPin.pin(request(), into: TestConfigurations.minimal())

        let fileSystem = InMemoryFileSystem()
        let store = ConfigurationStore(fileSystem: fileSystem)
        let url = URL(fileURLWithPath: "/tmp/openzonr/config.json")
        try store.save(outcome.configuration, to: url)

        guard case let .loaded(reloaded, report, _) = store.load(at: url) else {
            Issue.record("Die geschriebene Konfiguration ließ sich nicht wieder laden.")
            return
        }
        #expect(report.errors.isEmpty)
        #expect(reloaded == outcome.configuration)

        // Die eigentliche Frage ist nicht, ob die Datei zurückkommt, sondern ob
        // ein Outlook-Fenster danach in der rechten Zone landet.
        var occupancy = ZoneOccupancy()
        let decision = PlacementDecider().decide(
            for: TestConfigurations.window(bundleIdentifier: "com.microsoft.Outlook"),
            identifier: TestConfigurations.identifier("w1"),
            configuration: reloaded,
            rules: CompiledRuleSet(rules: reloaded.rules),
            setup: SetupFingerprint(displays: [.builtin]),
            visibleFrames: ["main": TestConfigurations.mainVisibleFrame],
            occupancy: &occupancy,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let placement = try #require(decision.placement)
        #expect(placement.zone == "right")
        #expect(decision.rule?.id == outcome.rule)
    }
}
