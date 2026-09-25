import Foundation

public struct ReferenceIntegrityCheck: ConfigurationCheck {

    public init() {}

    public func findings(in configuration: Configuration) -> [ValidationFinding] {
        let roles = Set(configuration.roles.map(\.id))
        let displaysByAlias = Dictionary(configuration.displays.map { ($0.alias, $0) }, uniquingKeysWith: { first, _ in first })
        var findings: [ValidationFinding] = []

        for rule in configuration.rules where !roles.contains(rule.action.role) {
            findings.append(ValidationFinding(
                code: .unknownRoleInRule,
                path: ConfigurationPath().element("rules", rule.id).field("action").field("role"),
                message: L.string(
                    "referenceIntegrity.unknownRoleInRule",
                    "Rule %@ refers to the unknown role %@.",
                    "\(rule.id)", "\(rule.action.role)"
                )
            ))
        }

        for display in configuration.displays {
            if !display.layouts.contains(where: { $0.id == display.defaultLayoutID }) {
                findings.append(ValidationFinding(
                    code: .unknownDefaultLayout,
                    path: ConfigurationPath().element("displays", display.alias).field("defaultLayoutID"),
                    message: L.string(
                        "referenceIntegrity.unknownDefaultLayout",
                        "The default layout %@ does not exist on display %@.",
                        "\(display.defaultLayoutID)", "\(display.alias)"
                    )
                ))
            }
        }

        for profile in configuration.profiles {
            let profilePath = ConfigurationPath().element("profiles", profile.id)

            for (alias, layoutID) in profile.layouts {
                let path = profilePath.field("layouts").key(alias)
                guard let display = displaysByAlias[alias] else {
                    findings.append(ValidationFinding(
                        code: .unknownDisplayInBinding,
                        path: path,
                        message: L.string(
                            "referenceIntegrity.unknownDisplayInBinding.profileLayouts",
                            "Profile %@ refers to the unknown display %@.",
                            "\(profile.id)", "\(alias)"
                        )
                    ))
                    continue
                }

                if !display.layouts.contains(where: { $0.id == layoutID }) {
                    findings.append(ValidationFinding(
                        code: .unknownLayoutInProfile,
                        path: path,
                        message: L.string(
                            "referenceIntegrity.unknownLayoutInProfile",
                            "Display %@ has no layout %@.",
                            "\(alias)", "\(layoutID)"
                        )
                    ))
                }
            }

            for (index, binding) in profile.roleBindings.enumerated() {
                findings.append(contentsOf: validateBinding(
                    binding,
                    in: profile,
                    displaysByAlias: displaysByAlias,
                    displayPath: profilePath.element("roleBindings", at: index).field("display"),
                    zonePath: profilePath.element("roleBindings", at: index).field("zone")
                ))
            }

            findings.append(contentsOf: validateBinding(
                profile.fallback,
                in: profile,
                displaysByAlias: displaysByAlias,
                displayPath: profilePath.field("fallback").field("display"),
                zonePath: profilePath.field("fallback").field("zone")
            ))
        }

        return findings
    }

    private func validateBinding(
        _ binding: RoleBinding,
        in profile: Profile,
        displaysByAlias: [DisplayAlias: DisplayDescriptor],
        displayPath: ConfigurationPath,
        zonePath: ConfigurationPath
    ) -> [ValidationFinding] {
        guard let display = displaysByAlias[binding.display] else {
            return [ValidationFinding(
                code: .unknownDisplayInBinding,
                path: displayPath,
                message: L.string(
                    "referenceIntegrity.unknownDisplayInBinding.roleBinding",
                    "This role binding refers to the unknown display %@.",
                    "\(binding.display)"
                )
            )]
        }

        let layoutID = profile.layouts[binding.display] ?? display.defaultLayoutID
        guard let layout = display.layouts.first(where: { $0.id == layoutID }) else {
            return []
        }

        guard layout.zones.contains(where: { $0.id == binding.zone }) else {
            return [ValidationFinding(
                code: .unknownZoneInBinding,
                path: zonePath,
                message: L.string(
                    "referenceIntegrity.unknownZoneInBinding",
                    "Layout %@ on display %@ has no zone %@.",
                    "\(layoutID)", "\(binding.display)", "\(binding.zone)"
                )
            )]
        }

        return []
    }
}
