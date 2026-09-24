import Foundation

/// Which of a rule's criteria can be answered at all without an actually
/// observed window — and which cannot?
///
/// This type is the real value of the dry-run line for Case B: for a bundle
/// whose app is not currently running, there is no `WindowSnapshot`. Anyone
/// who "computes" the rule anyway, implicitly ignoring or inventing title,
/// role, subrole, size, aspect ratio and "only the first window", is handing
/// out a guess dressed up as a computation — the same class of failure this
/// project fights elsewhere.
///
/// The trigger for this type is spelled out in Issue #19: in the
/// real-existing configuration, all three rules check the bundle
/// exclusively. A naive dry run would there be accidentally exact, and would
/// go silently wrong the moment the first title or size rule was added.
///
/// The pure-function shape is deliberate: no dependency on `NSScreen`, none
/// on AppKit, none on the window system — the test runs on any machine,
/// including CI.
public enum RuleCriteria {

    /// A single criterion that a rule checks.
    public enum Criterion: Hashable, Sendable, CustomStringConvertible {
        case bundleIdentifier(String)
        case title(pattern: String)
        case roles([String])
        case subroles([String])
        case minimumSize(WindowSize)
        case maximumSize(WindowSize)
        case aspectRatio(AspectRatioRange)
        case onlyFirstWindowAfterLaunch(Bool)

        /// Caption for the UI. Deliberately short — the dry-run line is one
        /// line, not a list.
        public var description: String {
            switch self {
            case .bundleIdentifier: return L.string("ruleCriteria.criterion.bundleIdentifier", "bundle identifier")
            case .title:            return L.string("ruleCriteria.criterion.title", "window title")
            case .roles:            return L.string("ruleCriteria.criterion.roles", "role (AX)")
            case .subroles:         return L.string("ruleCriteria.criterion.subroles", "subrole (AX)")
            case .minimumSize:      return L.string("ruleCriteria.criterion.minimumSize", "minimum size")
            case .maximumSize:      return L.string("ruleCriteria.criterion.maximumSize", "maximum size")
            case .aspectRatio:      return L.string("ruleCriteria.criterion.aspectRatio", "aspect ratio")
            case .onlyFirstWindowAfterLaunch:
                                    return L.string(
                                        "ruleCriteria.criterion.onlyFirstWindowAfterLaunch",
                                        "first window after launch"
                                    )
            }
        }
    }

    /// Evaluation of a `WindowMatch` together with the global defaults,
    /// under the assumption that only the bundle identifier is known.
    ///
    /// - `decidable` are criteria whose truth value follows purely from the
    ///   bundle identifier and the defaults. Exactly one: the bundle
    ///   identifier itself, when the rule sets one at all.
    /// - `undecidable` are all criteria that only become measurable on the
    ///   real window.
    public struct Report: Hashable, Sendable {
        public var decidable: [Criterion]
        public var undecidable: [Criterion]

        public init(decidable: [Criterion], undecidable: [Criterion]) {
            self.decidable = decidable
            self.undecidable = undecidable
        }

        /// `true` when saying "this rule applies" without a window can only
        /// be a partial answer.
        public var requiresObservation: Bool { !undecidable.isEmpty }
    }

    /// Splits a `WindowMatch` into the two lists.
    ///
    /// The filter in `DefaultWindowFilter` (layer 0, `allowedSubroles`,
    /// `minimumWindowSize`) also checks window data. It is not part of
    /// `WindowMatch` and so is not reported here — ``report(for:defaults:)``
    /// exists for that.
    public static func report(for match: WindowMatch) -> Report {
        var decidable: [Criterion] = []
        var undecidable: [Criterion] = []

        if let bundleIdentifier = match.bundleIdentifier {
            decidable.append(.bundleIdentifier(bundleIdentifier))
        }
        if let titlePattern = match.titlePattern {
            undecidable.append(.title(pattern: titlePattern))
        }
        if let roles = match.roles {
            undecidable.append(.roles(roles))
        }
        if let subroles = match.subroles {
            undecidable.append(.subroles(subroles))
        }
        if let minimumSize = match.minimumSize {
            undecidable.append(.minimumSize(minimumSize))
        }
        if let maximumSize = match.maximumSize {
            undecidable.append(.maximumSize(maximumSize))
        }
        if let aspectRatio = match.aspectRatio {
            undecidable.append(.aspectRatio(aspectRatio))
        }
        if let onlyFirstWindowAfterLaunch = match.onlyFirstWindowAfterLaunch {
            undecidable.append(.onlyFirstWindowAfterLaunch(onlyFirstWindowAfterLaunch))
        }

        return Report(decidable: decidable, undecidable: undecidable)
    }

    /// Splits a `WindowMatch` together with the global defaults.
    ///
    /// In addition to ``report(for:)``, the "only the first window" rule
    /// inherited from the defaults shows through under ``Report/undecidable``
    /// as long as the rule itself sets no explicit value and the default is
    /// active. Other filters of `DefaultWindowFilter` (layer,
    /// `allowedSubroles`, `minimumWindowSize`) are also observation-dependent,
    /// but they are system filters, not rule-specific criteria — they do not
    /// appear in the line for *this* rule, because they apply to every rule.
    public static func report(for match: WindowMatch, defaults: GlobalDefaults) -> Report {
        var report = self.report(for: match)
        if match.onlyFirstWindowAfterLaunch == nil, defaults.onlyFirstWindowAfterLaunch {
            report.undecidable.append(.onlyFirstWindowAfterLaunch(true))
        }
        return report
    }
}
