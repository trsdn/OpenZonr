import Foundation

/// The cheap, global pre-filter that runs before any rule is looked at.
///
/// Its job is to keep the obvious non-candidates out of rule evaluation:
/// sheets, palettes, progress windows and the dialogs an application opens
/// after its main window. The criteria are applied in increasing order of cost,
/// which is the same order in which they are introduced in
/// `docs/konzept.md` section 3.
///
/// The filter answers with a reason rather than a plain `false`, because the
/// only interesting question at this stage is *why* a window was not placed,
/// and a diagnostics view cannot reconstruct that from a boolean.
///
/// ## The exemption for "first window after launch"
///
/// `onlyFirstWindowAfterLaunch` is a global default that individual rules are
/// meant to switch off — that is exactly how the Outlook compose window in the
/// shipped example gets placed. A filter that enforced the default before any
/// rule is consulted would make those rules unreachable, because a compose
/// window is by definition not the first one.
///
/// The filter therefore derives its exemptions from the rule set once, at
/// construction time: every enabled rule that sets the flag to `false` exempts
/// the windows it could possibly match — by bundle identifier, or all windows
/// when the rule names none. Cheap to compute, cheap to apply, and it can never
/// reject a window that a rule would have wanted.
public struct DefaultWindowFilter: WindowFilter {

    /// Bundle identifiers of applications that have at least one rule opting out
    /// of the "first window only" default.
    private let exemptBundleIdentifiers: Set<String>

    /// `true` when a rule opts out without naming a bundle identifier, which
    /// makes the exemption apply to every window.
    private let exemptsEveryWindow: Bool

    /// A filter that enforces the "first window after launch" default without
    /// exceptions. Suitable when no rules are involved.
    public init() {
        self.exemptBundleIdentifiers = []
        self.exemptsEveryWindow = false
    }

    /// A filter that knows which rules opt out of the "first window after
    /// launch" default, so those rules stay reachable.
    public init(rules: CompiledRuleSet) {
        var identifiers: Set<String> = []
        var global = false

        for entry in rules.entries where entry.rule.match.onlyFirstWindowAfterLaunch == false {
            if let bundleIdentifier = entry.rule.match.bundleIdentifier {
                identifiers.insert(bundleIdentifier)
            } else {
                global = true
            }
        }

        self.exemptBundleIdentifiers = identifiers
        self.exemptsEveryWindow = global
    }

    public func evaluate(_ window: WindowSnapshot, defaults: GlobalDefaults) -> WindowFilterResult {
        // Subrole first: one string comparison, and it removes sheets, dialogs
        // and most popups without any configuration at all.
        guard let subrole = window.subrole, defaults.allowedSubroles.contains(subrole) else {
            return .rejected(.disallowedSubrole(window.subrole))
        }

        let minimum = defaults.minimumWindowSize
        if window.frame.width < minimum.width || window.frame.height < minimum.height {
            return .rejected(
                .tooSmall(
                    actual: WindowSize(width: window.frame.width, height: window.frame.height),
                    minimum: minimum
                )
            )
        }

        // Whether this is the first window since launch is not decided here — it
        // arrives on the snapshot. This layer only acts on it.
        if defaults.onlyFirstWindowAfterLaunch,
           !window.isFirstWindowAfterLaunch,
           !isExempt(window) {
            return .rejected(.notFirstWindowAfterLaunch)
        }

        return .accepted
    }

    private func isExempt(_ window: WindowSnapshot) -> Bool {
        if exemptsEveryWindow { return true }
        guard let bundleIdentifier = window.bundleIdentifier else { return false }
        return exemptBundleIdentifiers.contains(bundleIdentifier)
    }
}
