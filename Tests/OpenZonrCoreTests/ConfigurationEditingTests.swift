import Foundation
import Testing
@testable import OpenZonrCore

/// The editor's operations are the layer that a rule editor can be proven on
/// without a screen and without the Accessibility permission. These tests care
/// about the invariants the user interface then relies on — above all that the
/// list order it shows is the order the engine evaluates.
struct ConfigurationEditingTests {

    // MARK: - Order

    @Test("Die Liste zeigt die Auswertungsreihenfolge, nicht die Dateireihenfolge")
    func evaluationOrderFollowsPriority() {
        let configuration = TestConfigurations.minimal {
            $0.rules = [
                PlacementRule(id: "low", name: "Niedrig", priority: 1, match: WindowMatch(), action: PlacementAction(role: "editor")),
                PlacementRule(id: "high", name: "Hoch", priority: 99, match: WindowMatch(), action: PlacementAction(role: "editor"))
            ]
        }

        #expect(configuration.rulesInEvaluationOrder.map(\.id) == ["high", "low"])
    }

    @Test("Gleiche Priorität behält die Dateireihenfolge")
    func equalPrioritiesKeepFileOrder() {
        let configuration = TestConfigurations.minimal {
            $0.rules = [
                PlacementRule(id: "erste", name: "Erste", priority: 5, match: WindowMatch(), action: PlacementAction(role: "editor")),
                PlacementRule(id: "zweite", name: "Zweite", priority: 5, match: WindowMatch(), action: PlacementAction(role: "editor"))
            ]
        }

        #expect(configuration.rulesInEvaluationOrder.map(\.id) == ["erste", "zweite"])
    }

    @Test("Verschieben schreibt die Prioritäten so um, dass die Liste stimmt")
    func movingRuleRenumbersPriorities() {
        let moved = TestConfigurations.minimal().movingRule("chat-rule", to: 0)

        // Was die Liste zeigt, ist danach auch die Dateireihenfolge — sonst
        // behauptet die Oberfläche eine Reihenfolge, die die Engine nicht kennt.
        #expect(moved.rules.map(\.id) == ["chat-rule", "editor-rule"])
        #expect(moved.rulesInEvaluationOrder.map(\.id) == ["chat-rule", "editor-rule"])
        #expect(moved.rules[0].priority > moved.rules[1].priority)
    }

    @Test("Verschieben über den Rand hinaus bleibt am Rand")
    func movingBeyondTheEdgeClamps() {
        let configuration = TestConfigurations.minimal()

        #expect(configuration.movingRule("editor-rule", by: -5).rulesInEvaluationOrder.first?.id == "editor-rule")
        #expect(configuration.movingRule("editor-rule", by: 5).rulesInEvaluationOrder.last?.id == "editor-rule")
    }

    @Test("Ein unbekannter Bezeichner ändert nichts")
    func unknownIdentifiersAreIgnored() {
        let configuration = TestConfigurations.minimal()

        #expect(configuration.movingRule("gibt-es-nicht", to: 0) == configuration)
        #expect(configuration.removingRule("gibt-es-nicht") == configuration)
        #expect(configuration.settingRule("gibt-es-nicht", enabled: false) == configuration)
    }

    // MARK: - Rules

    @Test("Regeln lassen sich anlegen, ändern, abschalten und löschen")
    func ruleLifecycle() throws {
        var configuration = TestConfigurations.minimal()
        let rule = PlacementRule(
            id: configuration.availableRuleID(basedOn: "Neue Regel"),
            name: "Neue Regel",
            priority: 1,
            match: WindowMatch(bundleIdentifier: "com.example.neu"),
            action: PlacementAction(role: "editor")
        )

        configuration = configuration.adding(rule: rule)
        #expect(configuration.rules.count == 3)

        configuration = configuration.settingRule(rule.id, enabled: false)
        #expect(configuration.rules.first { $0.id == rule.id }?.enabled == false)

        var edited = try #require(configuration.rules.first { $0.id == rule.id })
        edited.match.titlePattern = "^Posteingang"
        configuration = configuration.updating(rule: edited)
        #expect(configuration.rules.first { $0.id == rule.id }?.match.titlePattern == "^Posteingang")

        configuration = configuration.removingRule(rule.id)
        #expect(configuration.rules.count == 2)
    }

    // MARK: - Roles and bindings

    @Test("Eine gelöschte Rolle nimmt ihre Bindungen mit, aber nicht ihre Regeln")
    func removingRoleKeepsRulesForTheValidator() {
        let configuration = TestConfigurations.minimal().removingRole("communication")

        #expect(!configuration.roles.contains { $0.id == "communication" })
        #expect(!configuration.profiles[0].roleBindings.contains { $0.role == "communication" })

        // Die Regel bleibt stehen, damit der Validator sie meldet, statt dass
        // die Oberfläche still eine fremde Entscheidung trifft.
        #expect(configuration.rules.contains { $0.action.role == "communication" })
        #expect(ConfigurationValidator().validate(configuration)
            .contains(.unknownRoleInRule, at: "rules[chat-rule].action.role"))
    }

    @Test("Eine Bindung ersetzt die vorhandene derselben Rolle")
    func bindingReplacesInsteadOfDuplicating() {
        let configuration = TestConfigurations.minimal().setting(
            binding: RoleBinding(role: "editor", display: "main", zone: "right"),
            inProfile: "solo"
        )

        let bindings = configuration.profiles[0].roleBindings.filter { $0.role == "editor" }
        #expect(bindings.count == 1)
        #expect(bindings.first?.zone == "right")
    }

    @Test("Das Layout eines Profils wird wie bei der Platzierung aufgelöst")
    func layoutResolutionMatchesTheResolver() {
        var configuration = TestConfigurations.minimal()
        configuration.profiles[0].layouts = [:]

        // Ohne Eintrag im Profil gilt das Standardlayout des Displays — genau
        // das, was DefaultZoneResolver tut.
        #expect(configuration.layoutID(forDisplay: "main", inProfile: "solo") == "halves")

        configuration = configuration.setting(layout: "halves", forDisplay: "main", inProfile: "solo")
        #expect(configuration.profiles[0].layouts["main"] == "halves")
    }

    // MARK: - Zones

    @Test("Zonen lassen sich verschieben, ergänzen und entfernen")
    func zoneLifecycle() {
        var configuration = TestConfigurations.minimal()
        let frame = RelativeRect(x: 0, y: 0, width: 0.25, height: 1)

        configuration = configuration.settingZoneFrame(frame, zone: "left", layout: "halves", display: "main")
        #expect(configuration.displays[0].layouts[0].zones[0].frame == frame)

        let id = configuration.availableZoneID(basedOn: "Links", layout: "halves", display: "main")
        #expect(id == "links")

        configuration = configuration.adding(
            zone: Zone(id: id, name: "Links", frame: RelativeRect(x: 0.25, y: 0, width: 0.25, height: 1)),
            layout: "halves",
            display: "main"
        )
        #expect(configuration.displays[0].layouts[0].zones.count == 3)

        configuration = configuration.removingZone(id, layout: "halves", display: "main")
        #expect(configuration.displays[0].layouts[0].zones.count == 2)
    }

    @Test("Eine gelöschte Zone lässt ihre Bindung stehen, damit der Validator sie meldet")
    func removingZoneSurfacesTheBinding() {
        let configuration = TestConfigurations.minimal().removingZone("right", layout: "halves", display: "main")

        #expect(configuration.profiles[0].roleBindings.contains { $0.zone == "right" })
        #expect(ConfigurationValidator().validate(configuration).contains(.unknownZoneInBinding))
    }

    // MARK: - Identifiers

    @Test("Bezeichner werden lesbar abgeleitet")
    func slugsAreReadable() {
        #expect(IdentifierFactory.slug("Rechte Spalte") == "rechte-spalte")
        #expect(IdentifierFactory.slug("Büro — 2. Monitor") == "buero-2-monitor")
        #expect(IdentifierFactory.slug("Größe/Maß") == "groesse-mass")
        #expect(IdentifierFactory.slug("com.microsoft.Outlook") == "com-microsoft-outlook")
    }

    @Test("Ein belegter Bezeichner wird durchnummeriert, nicht überschrieben")
    func uniqueSlugsCount() {
        #expect(IdentifierFactory.uniqueSlug("zone", taken: []) == "zone")
        #expect(IdentifierFactory.uniqueSlug("zone", taken: ["zone"]) == "zone-2")
        #expect(IdentifierFactory.uniqueSlug("zone", taken: ["zone", "zone-2"]) == "zone-3")
        #expect(IdentifierFactory.uniqueSlug("···", taken: [], fallback: "regel") == "regel")
    }

    @Test("Erzeugte Bezeichner kollidieren nicht mit vorhandenen")
    func generatedIdentifiersAreFree() {
        let configuration = TestConfigurations.minimal()

        #expect(configuration.availableRuleID(basedOn: "Editor") == "editor")
        #expect(configuration.availableRoleID(basedOn: "Editor") == "editor-2")
    }
}
