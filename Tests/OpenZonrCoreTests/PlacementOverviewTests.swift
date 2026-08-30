import Foundation
import Testing
@testable import OpenZonrCore

/// Prüft die Zuordnung Regel → Zone, die die Übersicht aus Issue #19
/// zeichnet. Sichtbar gemachte Beobachtungen:
///
/// - leere Zonen bleiben leer und werden nicht weggelassen,
/// - Regeln erscheinen in Auswertungsreihenfolge (Priorität absteigend),
/// - eine Regel für eine im Profil nicht gebundene Rolle landet in der
///   Auffangzone.
struct PlacementOverviewTests {

    @Test("Regeln werden in ihre gebundenen Zonen einsortiert")
    func rulesLandInBoundZones() {
        let configuration = TestConfigurations.minimal()
        let profile = configuration.profiles[0]

        let panels = PlacementOverview.build(for: profile, configuration: configuration)

        #expect(panels.count == 1)
        let main = panels[0]
        #expect(main.zones.count == 2)

        // Die Editor-Regel bindet an Rolle "editor" → Zone "left".
        let left = main.zones.first { $0.zone.id == "left" }
        #expect(left?.rules.map(\.name) == ["Editor"])

        let right = main.zones.first { $0.zone.id == "right" }
        #expect(right?.rules.map(\.name) == ["Chat"])
    }

    @Test("Eine Zone ohne Bindung bleibt in der Übersicht sichtbar, aber leer")
    func unusedZoneStaysVisible() {
        var configuration = TestConfigurations.minimal()
        // Eine dritte Zone im Layout, an die keine Rolle bindet — genau der
        // Fall aus dem Issue: `u28e590-full` existiert, keine Bindung nutzt sie.
        configuration.displays[0].layouts[0].zones.append(
            Zone(id: "focus", name: "Fokus", frame: RelativeRect(x: 0, y: 0, width: 1, height: 1))
        )
        let profile = configuration.profiles[0]

        let panels = PlacementOverview.build(for: profile, configuration: configuration)
        let focus = panels[0].zones.first { $0.zone.id == "focus" }
        #expect(focus?.isEmpty == true)
    }

    @Test("Höhere Priorität steht in der Zone weiter oben")
    func higherPriorityAppearsFirst() {
        var configuration = TestConfigurations.minimal()
        configuration = configuration.adding(rule: PlacementRule(
            id: "editor-notizen",
            name: "Editor-Notizen",
            priority: 100,
            match: WindowMatch(bundleIdentifier: "com.example.editor"),
            action: PlacementAction(role: "editor")
        ))

        let panels = PlacementOverview.build(for: configuration.profiles[0], configuration: configuration)
        let left = panels[0].zones.first { $0.zone.id == "left" }
        #expect(left?.rules.map(\.name) == ["Editor-Notizen", "Editor"])
    }

    @Test("Eine Regel für eine ungebundene Rolle landet in der Auffangzone")
    func unboundRoleRoutesToFallback() {
        var configuration = TestConfigurations.minimal()
        // Neue Rolle, die im Profil keine Bindung hat — das Profil hat
        // eine Auffangbindung, dorthin muss die Regel gezeichnet werden.
        configuration = configuration.adding(role: ZoneRole(id: "unbekannt", name: "Unbekannt"))
        configuration = configuration.adding(rule: PlacementRule(
            id: "streuner",
            name: "Streuner",
            priority: 1,
            match: WindowMatch(bundleIdentifier: "com.example.streuner"),
            action: PlacementAction(role: "unbekannt")
        ))

        let panels = PlacementOverview.build(for: configuration.profiles[0], configuration: configuration)
        let fallbackZone = configuration.profiles[0].fallback.zone
        let landing = panels[0].zones.first { $0.zone.id == fallbackZone }
        #expect(landing?.rules.contains(where: { $0.ruleID == "streuner" }) == true)
    }

    @Test("Die Auffangbindung des Profils wird gesondert gemeldet")
    func fallbackZoneReportedSeparately() {
        let configuration = TestConfigurations.minimal()
        let panels = PlacementOverview.build(for: configuration.profiles[0], configuration: configuration)
        #expect(panels[0].fallbackZone == configuration.profiles[0].fallback.zone)
    }

    @Test("Deaktivierte Regeln erscheinen mit enabled: false — die Übersicht darf sie nicht verschweigen")
    func disabledRulesAppearAsDisabled() {
        var configuration = TestConfigurations.minimal()
        configuration = configuration.settingRule("editor-rule", enabled: false)

        let panels = PlacementOverview.build(for: configuration.profiles[0], configuration: configuration)
        let left = panels[0].zones.first { $0.zone.id == "left" }
        let editorLabel = left?.rules.first { $0.ruleID == "editor-rule" }
        #expect(editorLabel?.enabled == false)
    }
}
