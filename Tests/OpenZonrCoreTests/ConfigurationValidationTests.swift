import Foundation
import Testing
@testable import OpenZonrCore

struct ConfigurationValidationTests {

    private let validator = ConfigurationValidator()

    @Test("Die Beispielkonfiguration ist sauber")
    func exampleConfigurationIsClean() throws {
        let report = validator.validate(try TestConfigurations.example())

        #expect(report.findings.isEmpty)
        #expect(report.errors.isEmpty)
        #expect(report.warnings.isEmpty)
    }

    @Test("Jeder Validierungscode wird am erwarteten Pfad gemeldet", arguments: ValidationScenario.allCases)
    func everyValidationCodeIsReportedAtExpectedPath(scenario: ValidationScenario) {
        let report = validator.validate(scenario.configuration())

        #expect(report.findings.count == 1)
        #expect(report.findings.first?.code == scenario.code)
        #expect(report.findings.first?.path.description == scenario.path)
        #expect(report.contains(scenario.code, at: scenario.path))
    }

    @Test("Mehrere unabhängige Befunde werden gemeinsam gemeldet")
    func multipleIndependentFindingsAreReportedTogether() {
        let configuration = TestConfigurations.minimal {
            $0.displays[0].layouts[0].zones[0].frame.width = 0
            $0.profiles[0].roleBindings[0].zone = "missing-zone"
            $0.rules[0].match.titlePattern = "["
            $0.roles.append(ZoneRole(id: "unused", name: "Unused"))
        }

        let report = validator.validate(configuration)

        #expect(report.contains(.relativeRectNonPositiveSize, at: "displays[main].layouts[halves].zones[left].frame.width"))
        #expect(report.contains(.unknownZoneInBinding, at: "profiles[solo].roleBindings[0].zone"))
        #expect(report.contains(.invalidTitlePattern, at: "rules[editor-rule].match.titlePattern"))
        #expect(report.contains(.unusedRole, at: "roles[unused]"))
    }

    @Test("Nur Warnungen bleiben benutzbar")
    func warningsOnlyRemainUsable() {
        let report = validator.validate(TestConfigurations.minimal {
            $0.roles.append(ZoneRole(id: "unused", name: "Unused"))
        })

        #expect(report.errors.isEmpty)
        #expect(report.warnings.count == 1)
        #expect(report.isUsable)
    }

    @Test("Fehler machen die Konfiguration unbenutzbar")
    func errorsMakeConfigurationUnusable() {
        let report = validator.validate(TestConfigurations.minimal {
            $0.defaults.minimumWindowSize.width = 0
        })

        #expect(report.errors.count == 1)
        #expect(!report.isUsable)
    }

    @Test("Die Reihenfolge der Befunde ist deterministisch")
    func findingOrderIsDeterministic() {
        let configuration = TestConfigurations.minimal {
            $0.profiles[0].roleBindings[0].zone = "missing-zone"
            $0.rules[0].match.titlePattern = "["
            $0.roles.append(ZoneRole(id: "unused", name: "Unused"))
        }

        let first = validator.validate(configuration).stableFindingDescriptions
        let second = validator.validate(configuration).stableFindingDescriptions

        #expect(first == second)
    }

    enum ValidationScenario: CaseIterable, Sendable {
        case duplicateDisplayAlias
        case duplicateRoleID
        case duplicateRuleID
        case duplicateProfileID
        case duplicateLayoutID
        case duplicateZoneID
        case unknownRoleInRule
        case unknownDisplayInBinding
        case unknownLayoutInProfile
        case unknownZoneInBinding
        case unknownDefaultLayout
        case relativeRectOutOfRange
        case relativeRectNonPositiveSize
        case relativeRectOverflow
        case zoneShareTooFewSlots
        case zoneShareSlotIndexOutOfRange
        case aspectRatioInverted
        case aspectRatioNonPositive
        case retryAttemptsTooLow
        case negativeDuration
        case nonPositiveWindowSize
        case invalidTitlePattern
        case duplicateProfileFingerprint
        case unknownDisplayInFingerprint
        case emptyProfileFingerprint
        case unusedRole
        case shadowedRule

        var code: ValidationCode {
            switch self {
            case .duplicateDisplayAlias: .duplicateDisplayAlias
            case .duplicateRoleID: .duplicateRoleID
            case .duplicateRuleID: .duplicateRuleID
            case .duplicateProfileID: .duplicateProfileID
            case .duplicateLayoutID: .duplicateLayoutID
            case .duplicateZoneID: .duplicateZoneID
            case .unknownRoleInRule: .unknownRoleInRule
            case .unknownDisplayInBinding: .unknownDisplayInBinding
            case .unknownLayoutInProfile: .unknownLayoutInProfile
            case .unknownZoneInBinding: .unknownZoneInBinding
            case .unknownDefaultLayout: .unknownDefaultLayout
            case .relativeRectOutOfRange: .relativeRectOutOfRange
            case .relativeRectNonPositiveSize: .relativeRectNonPositiveSize
            case .relativeRectOverflow: .relativeRectOverflow
            case .zoneShareTooFewSlots: .zoneShareTooFewSlots
            case .zoneShareSlotIndexOutOfRange: .zoneShareSlotIndexOutOfRange
            case .aspectRatioInverted: .aspectRatioInverted
            case .aspectRatioNonPositive: .aspectRatioNonPositive
            case .retryAttemptsTooLow: .retryAttemptsTooLow
            case .negativeDuration: .negativeDuration
            case .nonPositiveWindowSize: .nonPositiveWindowSize
            case .invalidTitlePattern: .invalidTitlePattern
            case .duplicateProfileFingerprint: .duplicateProfileFingerprint
            case .unknownDisplayInFingerprint: .unknownDisplayInFingerprint
            case .emptyProfileFingerprint: .emptyProfileFingerprint
            case .unusedRole: .unusedRole
            case .shadowedRule: .shadowedRule
            }
        }

        var path: String {
            switch self {
            case .duplicateDisplayAlias: "displays[1].alias"
            case .duplicateRoleID: "roles[2].id"
            case .duplicateRuleID: "rules[2].id"
            case .duplicateProfileID: "profiles[1].id"
            case .duplicateLayoutID: "displays[main].layouts[1].id"
            case .duplicateZoneID: "displays[main].layouts[halves].zones[2].id"
            case .unknownRoleInRule: "rules[missing-role-rule].action.role"
            case .unknownDisplayInBinding: "profiles[solo].layouts[missing-display]"
            case .unknownLayoutInProfile: "profiles[solo].layouts[main]"
            case .unknownZoneInBinding: "profiles[solo].roleBindings[0].zone"
            case .unknownDefaultLayout: "displays[main].defaultLayoutID"
            case .relativeRectOutOfRange: "displays[main].layouts[halves].zones[left].frame.x"
            case .relativeRectNonPositiveSize: "displays[main].layouts[halves].zones[left].frame.width"
            case .relativeRectOverflow: "displays[main].layouts[halves].zones[left].frame.width"
            case .zoneShareTooFewSlots: "rules[editor-rule].action.share.slots"
            case .zoneShareSlotIndexOutOfRange: "rules[editor-rule].action.share.slotIndex"
            case .aspectRatioInverted: "rules[editor-rule].match.aspectRatio"
            case .aspectRatioNonPositive: "rules[editor-rule].match.aspectRatio.minimum"
            case .retryAttemptsTooLow: "defaults.retry.attempts"
            case .negativeDuration: "defaults.retry.initialDelay"
            case .nonPositiveWindowSize: "defaults.minimumWindowSize.width"
            case .invalidTitlePattern: "rules[editor-rule].match.titlePattern"
            case .duplicateProfileFingerprint: "profiles[duplicate].fingerprint"
            case .unknownDisplayInFingerprint: "profiles[solo].fingerprint.displays[1]"
            case .emptyProfileFingerprint: "profiles[solo].fingerprint.displays"
            case .unusedRole: "roles[unused]"
            case .shadowedRule: "rules[editor-rule]"
            }
        }

        func configuration() -> Configuration {
            TestConfigurations.minimal { configuration in
                switch self {
                case .duplicateDisplayAlias:
                    configuration.displays.append(configuration.displays[0])
                case .duplicateRoleID:
                    configuration.roles.append(ZoneRole(id: "editor", name: "Duplicate editor"))
                case .duplicateRuleID:
                    var rule = configuration.rules[0]
                    rule.enabled = false
                    configuration.rules.append(rule)
                case .duplicateProfileID:
                    let display = secondaryDisplay()
                    configuration.displays.append(display)
                    configuration.profiles.append(profile(id: "solo", display: display.alias))
                case .duplicateLayoutID:
                    configuration.displays[0].layouts.append(configuration.displays[0].layouts[0])
                case .duplicateZoneID:
                    configuration.displays[0].layouts[0].zones.append(Zone(
                        id: "left",
                        name: "Duplicate left",
                        frame: RelativeRect(x: 0, y: 0, width: 0.25, height: 1)
                    ))
                case .unknownRoleInRule:
                    configuration.rules.append(PlacementRule(
                        id: "missing-role-rule",
                        name: "Missing role",
                        match: WindowMatch(bundleIdentifier: "com.example.missing"),
                        action: PlacementAction(role: "missing-role")
                    ))
                case .unknownDisplayInBinding:
                    configuration.profiles[0].layouts["missing-display"] = "halves"
                case .unknownLayoutInProfile:
                    configuration.profiles[0].layouts["main"] = "missing-layout"
                case .unknownZoneInBinding:
                    configuration.profiles[0].roleBindings[0].zone = "missing-zone"
                case .unknownDefaultLayout:
                    configuration.displays[0].defaultLayoutID = "missing-layout"
                case .relativeRectOutOfRange:
                    configuration.displays[0].layouts[0].zones[0].frame.x = -0.1
                case .relativeRectNonPositiveSize:
                    configuration.displays[0].layouts[0].zones[0].frame.width = 0
                case .relativeRectOverflow:
                    configuration.displays[0].layouts[0].zones[0].frame.x = 0.75
                    configuration.displays[0].layouts[0].zones[0].frame.width = 0.5
                case .zoneShareTooFewSlots:
                    configuration.rules[0].action.share = ZoneShare(axis: .horizontal, slots: 1, slotIndex: 0)
                case .zoneShareSlotIndexOutOfRange:
                    configuration.rules[0].action.share = ZoneShare(axis: .horizontal, slots: 2, slotIndex: 2)
                case .aspectRatioInverted:
                    configuration.rules[0].match.aspectRatio = AspectRatioRange(minimum: 2, maximum: 1)
                case .aspectRatioNonPositive:
                    configuration.rules[0].match.aspectRatio = AspectRatioRange(minimum: 0, maximum: 2)
                case .retryAttemptsTooLow:
                    configuration.defaults.retry.attempts = 0
                case .negativeDuration:
                    configuration.defaults.retry.initialDelay = -0.1
                case .nonPositiveWindowSize:
                    configuration.defaults.minimumWindowSize.width = 0
                case .invalidTitlePattern:
                    configuration.rules[0].match.titlePattern = "["
                case .duplicateProfileFingerprint:
                    configuration.profiles.append(profile(id: "duplicate", display: "main"))
                case .unknownDisplayInFingerprint:
                    configuration.profiles[0].fingerprint.displays.append("missing-display")
                case .emptyProfileFingerprint:
                    configuration.profiles[0].fingerprint.displays = []
                case .unusedRole:
                    configuration.roles.append(ZoneRole(id: "unused", name: "Unused"))
                case .shadowedRule:
                    configuration.rules.insert(PlacementRule(
                        id: "earlier-editor-rule",
                        name: "Earlier editor",
                        priority: 20,
                        match: WindowMatch(bundleIdentifier: "com.example.editor"),
                        action: PlacementAction(role: "editor")
                    ), at: 0)
                }
            }
        }

        private func secondaryDisplay() -> DisplayDescriptor {
            DisplayDescriptor(
                alias: "secondary",
                displayName: "Secondary",
                identity: .edid(vendorNumber: 1, modelNumber: 2, serialNumber: 3),
                layouts: [
                    Layout(
                        id: "halves",
                        name: "Halves",
                        zones: [
                            Zone(id: "left", name: "Left", frame: RelativeRect(x: 0, y: 0, width: 0.5, height: 1)),
                            Zone(id: "right", name: "Right", frame: RelativeRect(x: 0.5, y: 0, width: 0.5, height: 1))
                        ]
                    )
                ],
                defaultLayoutID: "halves"
            )
        }

        private func profile(id: ProfileID, display: DisplayAlias) -> Profile {
            Profile(
                id: id,
                name: id.rawValue,
                fingerprint: ProfileFingerprint(displays: [display]),
                layouts: [display: "halves"],
                roleBindings: [
                    RoleBinding(role: "editor", display: display, zone: "left"),
                    RoleBinding(role: "communication", display: display, zone: "right")
                ],
                fallback: RoleBinding(role: "editor", display: display, zone: "left")
            )
        }
    }
}

private extension ValidationReport {
    var stableFindingDescriptions: [String] {
        findings.map { "\($0.severity.rawValue)|\($0.path.description)|\($0.code.rawValue)|\($0.message)" }
    }
}
