import Foundation

/// "Diese App immer hier öffnen" — the 90 % case from the concept, as one pure
/// function.
///
/// The user names an application and a place. Everything the model needs beyond
/// that — a rule, a role, a role binding, a priority that actually wins — is
/// derived here, so that the person pressing the menu item never learns the word
/// "Rolle". The whole point is that this is the *only* place where that
/// derivation happens: the menu item and the editor's "Regel hinzufügen" button
/// both call it, so both produce the same shape of configuration.
///
/// Nothing is written. The caller hands the result to ``ConfigurationStore``,
/// which is the only thing in the project allowed to touch the file.
public enum QuickPin {

    /// Where the window should land: a zone on a display.
    public struct Target: Hashable, Sendable {
        public var display: DisplayAlias
        public var zone: ZoneID

        public init(display: DisplayAlias, zone: ZoneID) {
            self.display = display
            self.zone = zone
        }
    }

    /// What the user asked for.
    public struct Request: Hashable, Sendable {
        /// Bundle identifier of the application, e.g. `com.microsoft.Outlook`.
        public var bundleIdentifier: String
        /// Name shown to the user, used for the rule's label.
        public var applicationName: String
        /// Profile the binding is written into — the one that is active now.
        public var profile: ProfileID
        public var target: Target

        public init(
            bundleIdentifier: String,
            applicationName: String,
            profile: ProfileID,
            target: Target
        ) {
            self.bundleIdentifier = bundleIdentifier
            self.applicationName = applicationName
            self.profile = profile
            self.target = target
        }
    }

    /// Why a pin could not be derived.
    ///
    /// Each case is something the caller can say out loud. "Ging nicht" is not
    /// an acceptable answer for a menu item that promises one click.
    public enum Failure: Error, Hashable, Sendable, CustomStringConvertible {
        case missingBundleIdentifier
        case unknownProfile(ProfileID)
        case unknownDisplay(DisplayAlias)
        case unknownLayout(DisplayAlias)
        case unknownZone(ZoneID, display: DisplayAlias)

        public var description: String {
            switch self {
            case .missingBundleIdentifier:
                return "Die App meldet keine Bundle-Kennung; ohne sie lässt sich keine Regel schreiben."
            case let .unknownProfile(id):
                return "Das Profil \(id) steht nicht in der Konfiguration."
            case let .unknownDisplay(alias):
                return "Das Display \(alias) steht nicht in der Konfiguration."
            case let .unknownLayout(alias):
                return "Für das Display \(alias) ist kein Layout auflösbar."
            case let .unknownZone(zone, display):
                return "Das Layout von \(display) enthält keine Zone \(zone)."
            }
        }
    }

    /// What the pin changed, so the caller can say it in one sentence.
    public struct Outcome: Sendable {
        public var configuration: Configuration
        public var rule: RuleID
        public var role: RoleID
        /// `true` when a role had to be invented because no binding pointed at
        /// the target zone yet.
        public var createdRole: Bool
        /// `true` when an existing rule was retargeted instead of a new one added.
        public var reusedRule: Bool
        /// One German sentence describing the change, ready for a log line.
        public var summary: String
    }

    /// Derives rule and binding for `request`.
    public static func pin(_ request: Request, into configuration: Configuration) throws -> Outcome {
        guard !request.bundleIdentifier.isEmpty else { throw Failure.missingBundleIdentifier }
        guard let profile = configuration.profiles.first(where: { $0.id == request.profile }) else {
            throw Failure.unknownProfile(request.profile)
        }
        guard configuration.displays.contains(where: { $0.alias == request.target.display }) else {
            throw Failure.unknownDisplay(request.target.display)
        }
        guard let layout = configuration.layout(forDisplay: request.target.display, inProfile: request.profile) else {
            throw Failure.unknownLayout(request.target.display)
        }
        guard let zone = layout.zones.first(where: { $0.id == request.target.zone }) else {
            throw Failure.unknownZone(request.target.zone, display: request.target.display)
        }

        var configuration = configuration
        var createdRole = false

        // 1. The role. Reusing the role of an existing binding for the same zone
        //    is what keeps the role list from growing one entry per click — and
        //    it is also the semantically right answer: two apps pinned to the
        //    same place do belong to the same role.
        let role: RoleID
        if let existing = profile.roleBindings.first(where: {
            $0.display == request.target.display && $0.zone == request.target.zone
        }) {
            role = existing.role
        } else {
            role = configuration.availableRoleID(basedOn: zone.name)
            configuration = configuration
                .adding(role: ZoneRole(
                    id: role,
                    name: zone.name,
                    summary: "Automatisch angelegt für „\(request.applicationName)“."
                ))
                .setting(
                    binding: RoleBinding(role: role, display: request.target.display, zone: request.target.zone),
                    inProfile: request.profile
                )
            createdRole = true
        }

        // 2. The rule. Pressing the menu item twice for the same app must not
        //    leave two rules behind — the second would be dead weight that never
        //    fires, and the user would have no way of knowing which one is live.
        //    A rule that matches this app *by bundle identifier alone* is the one
        //    this feature wrote, so it is retargeted rather than duplicated.
        if var existing = configuration.rules.first(where: { isPlainBundleRule($0, for: request.bundleIdentifier) }) {
            existing.action.role = role
            existing.enabled = true
            // The rule pointing at the right zone is only half the promise. If
            // something evaluated earlier also matches this app, the retargeted
            // rule never fires and the user is told the opposite — the exact
            // silent failure this project keeps paying for. So lift it above the
            // competition, but only when it is not already above: raising it on
            // every click would inflate the numbers for no reason.
            let contenders = highestCompetingPriority(
                for: request.bundleIdentifier,
                in: configuration,
                excluding: existing.id
            )
            if let contenders, existing.priority <= contenders {
                // `<=` and not `<`: on equal priority the file order decides, and
                // that is not something the user can see or influence here.
                existing.priority = contenders + Configuration.rulePriorityStep
            }
            configuration = configuration.updating(rule: existing)
            return Outcome(
                configuration: configuration,
                rule: existing.id,
                role: role,
                createdRole: createdRole,
                reusedRule: true,
                summary: "Regel „\(existing.name)“ zeigt jetzt auf \(zone.name) (\(request.target.display))."
            )
        }

        let id = configuration.availableRuleID(basedOn: request.applicationName)
        let rule = PlacementRule(
            id: id,
            name: "\(request.applicationName) → \(zone.name)",
            enabled: true,
            priority: priority(for: request.bundleIdentifier, in: configuration),
            match: WindowMatch(bundleIdentifier: request.bundleIdentifier),
            action: PlacementAction(role: role)
        )
        configuration = configuration.adding(rule: rule)

        return Outcome(
            configuration: configuration,
            rule: id,
            role: role,
            createdRole: createdRole,
            reusedRule: false,
            summary: "Regel „\(rule.name)“ angelegt, Priorität \(rule.priority)."
        )
    }

    /// `true` when `rule` is exactly "this bundle, nothing else".
    ///
    /// Every further criterion makes a rule more specific than what this feature
    /// writes, and a more specific rule was written deliberately — the Outlook
    /// compose rule is the example in the concept. Retargeting one of those from
    /// a menu item would silently undo somebody's careful work.
    private static func isPlainBundleRule(_ rule: PlacementRule, for bundleIdentifier: String) -> Bool {
        rule.match.bundleIdentifier == bundleIdentifier
            && rule.match.titlePattern == nil
            && rule.match.roles == nil
            && rule.match.subroles == nil
            && rule.match.minimumSize == nil
            && rule.match.maximumSize == nil
            && rule.match.aspectRatio == nil
    }

    /// A priority that makes the new rule win against everything that is not
    /// more specific.
    ///
    /// The first matching rule wins, so a pin that lands *below* a catch-all
    /// rule would do nothing at all — and do it silently, which is the failure
    /// mode this project keeps paying for. Counted as competition is every
    /// enabled rule that could match this application and is **not** more
    /// specific: a rule with a title pattern stays above, because it was written
    /// for one particular window and must keep its precedence.
    private static func priority(for bundleIdentifier: String, in configuration: Configuration) -> Int {
        guard let highest = highestCompetingPriority(for: bundleIdentifier, in: configuration, excluding: nil) else {
            return Configuration.rulePriorityStep
        }
        return highest + Configuration.rulePriorityStep
    }

    /// The highest priority among the rules that would compete with a pin for
    /// `bundleIdentifier`, or `nil` when there is no competition.
    ///
    /// `excluding` leaves out the rule being retargeted, which would otherwise
    /// compete with itself and climb by ten on every click.
    private static func highestCompetingPriority(
        for bundleIdentifier: String,
        in configuration: Configuration,
        excluding ruleID: RuleID?
    ) -> Int? {
        configuration.rules
            .filter { rule in
                guard rule.id != ruleID else { return false }
                guard rule.enabled else { return false }
                guard rule.match.titlePattern == nil else { return false }
                guard let bundle = rule.match.bundleIdentifier else { return true }
                return bundle == bundleIdentifier
            }
            .map(\.priority)
            .max()
    }
}

extension QuickPin {

    /// Why the result of a pin must not be reported as a success, if so.
    ///
    /// The quick pin has no field to hang a finding under: it says one sentence
    /// and disappears. So it has to be able to refuse, and the refusal has to be
    /// derived from the same validator the editor uses rather than guessed at
    /// the call site — which is why this lives next to ``pin(_:into:)`` and not
    /// in the interface.
    ///
    /// Two things object, and only two:
    ///
    /// - any error anywhere, because the configuration would not work at all;
    /// - a `shadowedRule` warning on this very rule, because that is the check
    ///   which knows the pinned rule is covered by an earlier one and will never
    ///   fire. Every other warning is none of the pin's business — refusing on
    ///   an unused role elsewhere would make the feature unusable.
    public static func objection(to outcome: Outcome, report: ValidationReport) -> String? {
        if let error = report.findings.first(where: { $0.severity == .error }) {
            return "Die Konfiguration hätte danach einen Fehler: \(error.message)"
        }

        let rulePath = ConfigurationPath.rule(outcome.rule)
        if let shadowed = report.findings.first(where: {
            $0.code == .shadowedRule && $0.path == rulePath
        }) {
            return shadowed.message + " Das Fenster ginge weiter woanders auf."
        }

        return nil
    }
}
