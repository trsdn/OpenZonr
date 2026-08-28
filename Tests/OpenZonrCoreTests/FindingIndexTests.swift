import Foundation
import Testing
@testable import OpenZonrCore

/// The issue asks for errors shown *at the affected field* instead of in a list
/// at the edge of the window. That is only possible if a view can look a
/// finding up by path, which is what these tests pin down — including the one
/// case the index must not silently swallow: a finding no field claims.
struct FindingIndexTests {

    @Test("Ein Befund ist unter genau seinem Pfad zu finden")
    func findingIsAddressableByPath() {
        let configuration = TestConfigurations.minimal {
            $0.rules[0].match.titlePattern = "(unvollständig"
        }
        let index = FindingIndex(ConfigurationValidator().validate(configuration))

        let path = ConfigurationPath.ruleMatch("editor-rule").field("titlePattern")
        #expect(index.findings(at: path).map(\.code) == [.invalidTitlePattern])
        #expect(index.severity(at: path) == .error)
    }

    @Test("Ein Befund tief in einer Regel ist von der Regel aus sichtbar")
    func findingBubblesUpToTheRow() {
        let configuration = TestConfigurations.minimal {
            $0.rules[0].match.titlePattern = "(unvollständig"
        }
        let index = FindingIndex(ConfigurationValidator().validate(configuration))

        // Die Zeile in der Liste zeigt das Abzeichen, das Feld den Text.
        #expect(index.severity(under: .rule("editor-rule")) == .error)
        #expect(index.severity(under: .rule("chat-rule")) == nil)
        #expect(index.severity(at: .rule("editor-rule")) == nil)
    }

    @Test("Ein benachbarter Bezeichner gilt nicht als Präfix")
    func neighbouringIdentifiersDoNotMatch() {
        let report = ValidationReport(findings: [
            ValidationFinding(
                code: .unknownRoleInRule,
                path: ConfigurationPath.ruleAction("ab").field("role"),
                message: "Test"
            )
        ])
        let index = FindingIndex(report)

        // "rules[a]" ist ein Zeichenpräfix von "rules[ab]", aber eine andere
        // Regel. Der Vergleich läuft deshalb über die Komponenten.
        #expect(index.findings(under: .rule("ab")).count == 1)
        #expect(index.findings(under: .rule("a")).isEmpty)
    }

    @Test("Fehler wiegen schwerer als Warnungen")
    func errorsOutrankWarnings() {
        let report = ValidationReport(findings: [
            ValidationFinding(code: .unusedRole, path: .role("editor"), message: "Warnung"),
            ValidationFinding(code: .duplicateRoleID, path: .role("editor"), message: "Fehler")
        ])
        let index = FindingIndex(report)

        #expect(index.severity(at: .role("editor")) == .error)
        #expect(index.findings(at: .role("editor")).first?.severity == .error)
    }

    @Test("Ein Befund, den kein Feld beansprucht, geht nicht verloren")
    func unclaimedFindingsRemainVisible() {
        // Doppelte Bezeichner werden über die Position gemeldet — mit zwei
        // gleichen Bezeichnern ist der Bezeichner gerade das, was nicht
        // adressieren kann.
        let configuration = TestConfigurations.minimal {
            $0.rules.append($0.rules[0])
        }
        let report = ConfigurationValidator().validate(configuration)
        let index = FindingIndex(report)

        #expect(report.contains(.duplicateRuleID))
        // Die Zeile der Regel zeigt nur, was ihr eigener Pfad trägt — der
        // Bezeichnerbefund steht an rules[2].id und gehört keiner Zeile.
        #expect(!index.findings(under: .rule("editor-rule")).contains { $0.code == .duplicateRuleID })

        let covered = configuration.rules.map { ConfigurationPath.rule($0.id) }
        #expect(index.findings(notUnder: covered).contains { $0.code == .duplicateRuleID })
    }

    @Test("Eine saubere Konfiguration ergibt einen leeren Index")
    func cleanConfigurationIsEmpty() {
        let index = FindingIndex(ConfigurationValidator().validate(TestConfigurations.minimal()))
        #expect(index.isEmpty)
        #expect(index.severity(under: ConfigurationPath()) == nil)
    }
}
