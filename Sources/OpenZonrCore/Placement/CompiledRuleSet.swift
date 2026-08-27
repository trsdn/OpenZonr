import Foundation

/// A rule set prepared once for repeated evaluation.
///
/// Two things happen here, and both happen exactly once instead of once per
/// window:
///
/// - **Ordering.** Enabled rules are sorted by ``PlacementRule/priority``
///   descending, ties broken by their position in the file. The sort is stable,
///   so two rules with the same priority keep the order their author gave them.
/// - **Regular expressions.** Every ``WindowMatch/titlePattern`` is translated
///   into an `NSRegularExpression` up front. Compiling a pattern per window
///   would put the most expensive operation of the whole pipeline on the hot
///   path, and the pipeline is already racing the application's own layout code.
///
/// A rule whose pattern does not compile is not silently dropped and does not
/// abort the run: it is moved to ``unusableRules`` and skipped during
/// evaluation, so one typo costs one rule instead of the whole configuration.
public struct CompiledRuleSet: Sendable {

    /// One rule, ready to be evaluated.
    public struct Entry: Sendable {
        /// The rule as written in the configuration.
        public let rule: PlacementRule
        /// The compiled title pattern, or `nil` when the rule has none.
        public let titleExpression: CompiledPattern?
        /// Position of the rule in the configuration, used as the tiebreaker.
        public let fileOrder: Int
    }

    /// A rule that could not be prepared.
    public struct UnusableRule: Hashable, Sendable {
        public let rule: RuleID
        public let pattern: String
        public let reason: String
    }

    /// Enabled, usable rules in evaluation order.
    public let entries: [Entry]

    /// Rules that were skipped because their title pattern does not compile.
    public let unusableRules: [UnusableRule]

    /// Prepares `rules` for evaluation.
    ///
    /// Never throws: an unusable rule is a fact about the configuration, not a
    /// failure of the caller.
    public init(rules: [PlacementRule]) {
        var prepared: [Entry] = []
        var unusable: [UnusableRule] = []

        for (fileOrder, rule) in rules.enumerated() {
            guard rule.enabled else { continue }

            if let pattern = rule.match.titlePattern {
                guard let expression = CompiledPattern(pattern: pattern) else {
                    unusable.append(
                        UnusableRule(
                            rule: rule.id,
                            pattern: pattern,
                            reason: "Der reguläre Ausdruck konnte nicht übersetzt werden."
                        )
                    )
                    continue
                }
                prepared.append(Entry(rule: rule, titleExpression: expression, fileOrder: fileOrder))
            } else {
                prepared.append(Entry(rule: rule, titleExpression: nil, fileOrder: fileOrder))
            }
        }

        // `sorted(by:)` is not guaranteed to be stable, so the file position is
        // part of the comparison rather than a hope.
        self.entries = prepared.sorted { lhs, rhs in
            if lhs.rule.priority != rhs.rule.priority {
                return lhs.rule.priority > rhs.rule.priority
            }
            return lhs.fileOrder < rhs.fileOrder
        }
        self.unusableRules = unusable
    }
}

/// A compiled regular expression together with the pattern it came from.
///
/// The wrapper exists so that a failed compilation is expressed as a failable
/// initialiser at one place, and so the original pattern stays available for
/// diagnostics after compilation.
public struct CompiledPattern: Sendable {

    /// The pattern as written in the configuration.
    public let pattern: String

    private let expression: NSRegularExpression

    /// Compiles `pattern`, returning `nil` when it is not a valid expression.
    public init?(pattern: String) {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return nil }
        self.pattern = pattern
        self.expression = expression
    }

    /// Whether the expression matches anywhere in `string`.
    public func matches(_ string: String) -> Bool {
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        return expression.firstMatch(in: string, range: range) != nil
    }
}
