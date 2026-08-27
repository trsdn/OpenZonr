import Foundation

/// Default implementation of the rule evaluator.
///
/// The engine only sees usable entries from ``CompiledRuleSet``. A rule whose
/// title pattern cannot be compiled has already been isolated in
/// ``CompiledRuleSet/unusableRules`` and can therefore never abort evaluation.
public struct DefaultRuleEngine: RuleEngine {

    public init() {}

    public func firstMatch(
        for window: WindowSnapshot,
        in rules: CompiledRuleSet,
        defaults: GlobalDefaults
    ) -> PlacementRule? {
        for entry in rules.entries where matches(window, entry: entry, defaults: defaults) {
            return entry.rule
        }

        return nil
    }

    private func matches(
        _ window: WindowSnapshot,
        entry: CompiledRuleSet.Entry,
        defaults: GlobalDefaults
    ) -> Bool {
        let match = entry.rule.match

        if let bundleIdentifier = match.bundleIdentifier,
           window.bundleIdentifier != bundleIdentifier {
            return false
        }

        if let titleExpression = entry.titleExpression {
            guard let title = window.title, titleExpression.matches(title) else { return false }
        }

        if let roles = match.roles {
            // An empty allow-list is a deliberate way to make a rule unreachable.
            guard let role = window.role, roles.contains(role) else { return false }
        }

        if let subroles = match.subroles {
            // An empty allow-list is a deliberate way to make a rule unreachable.
            guard let subrole = window.subrole, subroles.contains(subrole) else { return false }
        }

        if let minimumSize = match.minimumSize,
           !has(window.frame, atLeast: minimumSize) {
            return false
        }

        if let maximumSize = match.maximumSize,
           !has(window.frame, atMost: maximumSize) {
            return false
        }

        if let aspectRatio = match.aspectRatio,
           !has(window.frame, within: aspectRatio) {
            return false
        }

        let onlyFirstWindowAfterLaunch = match.onlyFirstWindowAfterLaunch ?? defaults.onlyFirstWindowAfterLaunch
        if onlyFirstWindowAfterLaunch, !window.isFirstWindowAfterLaunch {
            return false
        }

        return true
    }

    private func has(_ frame: WindowFrame, atLeast minimumSize: WindowSize) -> Bool {
        frame.width >= minimumSize.width && frame.height >= minimumSize.height
    }

    private func has(_ frame: WindowFrame, atMost maximumSize: WindowSize) -> Bool {
        frame.width <= maximumSize.width && frame.height <= maximumSize.height
    }

    private func has(_ frame: WindowFrame, within aspectRatio: AspectRatioRange) -> Bool {
        guard frame.height != 0 else { return false }

        let ratio = frame.width / frame.height
        guard ratio.isFinite else { return false }

        return ratio >= aspectRatio.minimum && ratio <= aspectRatio.maximum
    }
}
