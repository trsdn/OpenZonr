import Foundation

/// Evaluates ``PlacementRule`` values against a window, highest priority first.
///
/// Deliberately "first match wins": a rule set where several rules contribute to
/// one decision is impossible to reason about once it grows past a handful of
/// entries. Priority makes the order explicit instead of depending on the order
/// of lines in the configuration file.
public struct DefaultRuleEngine: RuleEngine {

    public init() {}

    public func firstMatch(
        for window: WindowSnapshot,
        in rules: [PlacementRule],
        defaults: GlobalDefaults
    ) -> PlacementRule? {
        orderedCandidates(in: rules)
            .first { matches(window, rule: $0, defaults: defaults) }
    }

    /// Enabled rules in evaluation order.
    ///
    /// Ties are broken by rule id so that evaluation is deterministic; two rules
    /// with the same priority must not depend on file order.
    public func orderedCandidates(in rules: [PlacementRule]) -> [PlacementRule] {
        rules
            .filter(\.enabled)
            .sorted { lhs, rhs in
                lhs.priority == rhs.priority ? lhs.id < rhs.id : lhs.priority > rhs.priority
            }
    }

    /// Whether a single rule applies to a window.
    ///
    /// All criteria present in the match must hold — absent criteria never
    /// restrict. A match with no criteria at all therefore matches everything,
    /// which is exactly what the (disabled by default) catch-all rule wants.
    public func matches(_ window: WindowSnapshot, rule: PlacementRule, defaults: GlobalDefaults) -> Bool {
        let match = rule.match

        if let bundleIdentifier = match.bundleIdentifier {
            guard window.bundleIdentifier == bundleIdentifier else { return false }
        }

        if let pattern = match.titlePattern {
            guard let title = window.title,
                  title.range(of: pattern, options: [.regularExpression]) != nil
            else { return false }
        }

        if let roles = match.roles {
            guard let role = window.role, roles.contains(role) else { return false }
        }

        if let subroles = match.subroles {
            guard let subrole = window.subrole, subroles.contains(subrole) else { return false }
        }

        if let minimum = match.minimumSize {
            guard window.frame.width >= minimum.width, window.frame.height >= minimum.height else {
                return false
            }
        }

        if let maximum = match.maximumSize {
            guard window.frame.width <= maximum.width, window.frame.height <= maximum.height else {
                return false
            }
        }

        if let aspectRatio = match.aspectRatio {
            guard window.frame.height > 0 else { return false }
            let ratio = window.frame.width / window.frame.height
            guard ratio >= aspectRatio.minimum, ratio <= aspectRatio.maximum else { return false }
        }

        // The rule may override the global default in either direction: an
        // Outlook compose window is by definition *not* the first window after
        // launch, so its rule opts out.
        let onlyFirst = match.onlyFirstWindowAfterLaunch ?? defaults.onlyFirstWindowAfterLaunch
        if onlyFirst, !window.isFirstWindowAfterLaunch { return false }

        return true
    }
}
