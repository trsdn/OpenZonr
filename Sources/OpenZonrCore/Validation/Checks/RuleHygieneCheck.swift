import Foundation

public struct RuleHygieneCheck: ConfigurationCheck {

    public init() {}

    /// A role nothing points at is almost always a leftover after renaming: it is
    /// harmless at runtime, but keeping it makes the role vocabulary lie.
    public func findings(in configuration: Configuration) -> [ValidationFinding] {
        var findings: [ValidationFinding] = []
        let usedRoles = Set(configuration.rules.map(\.action.role))

        for role in configuration.roles where !usedRoles.contains(role.id) {
            findings.append(ValidationFinding(
                code: .unusedRole,
                path: ConfigurationPath().element("roles", role.id),
                message: "Die Rolle \(role.id) wird von keiner Regel verwendet."
            ))
        }

        let orderedRules = configuration.rules.enumerated().filter { $0.element.enabled }
        for candidateIndex in orderedRules.indices {
            let candidate = orderedRules[candidateIndex]
            for earlierIndex in orderedRules.indices where earlierIndex != candidateIndex {
                let earlier = orderedRules[earlierIndex]
                guard isEvaluated(earlier.element, at: earlier.offset, before: candidate.element, at: candidate.offset) else { continue }
                guard isWeakerOrEqual(earlier.element.match, than: candidate.element.match, defaults: configuration.defaults) else { continue }

                findings.append(ValidationFinding(
                    code: .shadowedRule,
                    path: ConfigurationPath().element("rules", candidate.element.id),
                    message: "Die Regel \(candidate.element.id) wird vollständig von Regel \(earlier.element.id) überdeckt."
                ))
                break
            }
        }

        return findings
    }

    private func isEvaluated(_ lhs: PlacementRule, at lhsIndex: Int, before rhs: PlacementRule, at rhsIndex: Int) -> Bool {
        lhs.priority > rhs.priority || (lhs.priority == rhs.priority && lhsIndex < rhsIndex)
    }

    private func isWeakerOrEqual(_ lhs: WindowMatch, than rhs: WindowMatch, defaults: GlobalDefaults) -> Bool {
        optionalConstraint(lhs.bundleIdentifier, isWeakerOrEqualTo: rhs.bundleIdentifier)
            && optionalConstraint(lhs.titlePattern, isWeakerOrEqualTo: rhs.titlePattern)
            && optionalConstraint(lhs.roles, isWeakerOrEqualTo: rhs.roles)
            && optionalConstraint(lhs.subroles, isWeakerOrEqualTo: rhs.subroles)
            && optionalConstraint(lhs.minimumSize, isWeakerOrEqualTo: rhs.minimumSize)
            && optionalConstraint(lhs.maximumSize, isWeakerOrEqualTo: rhs.maximumSize)
            && optionalConstraint(lhs.aspectRatio, isWeakerOrEqualTo: rhs.aspectRatio)
            && effectiveOnlyFirstWindow(lhs, defaults: defaults) == effectiveOnlyFirstWindow(rhs, defaults: defaults)
    }

    private func optionalConstraint<T: Equatable>(_ lhs: T?, isWeakerOrEqualTo rhs: T?) -> Bool {
        lhs == nil || lhs == rhs
    }

    private func effectiveOnlyFirstWindow(_ match: WindowMatch, defaults: GlobalDefaults) -> Bool {
        match.onlyFirstWindowAfterLaunch ?? defaults.onlyFirstWindowAfterLaunch
    }
}
