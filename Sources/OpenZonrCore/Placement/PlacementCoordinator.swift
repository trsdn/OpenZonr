import Foundation

/// What OpenZonr decided to do with a newly appeared window — and why.
///
/// Every branch carries its reason. A window manager that acts on window
/// creation is only debuggable if it can explain the cases in which it did
/// *nothing*, which is why "no rule matched" is a first-class result rather than
/// an early `return nil`.
public enum PlacementDecision: Sendable {
    /// The window never reached rule evaluation.
    case filtered(DefaultWindowFilter.Rejection)
    /// No enabled rule matched.
    case noRuleMatched
    /// A rule matched but its role could not be resolved to geometry.
    case unresolvable(PlacementRule, DefaultZoneResolver.Problem)
    /// A rule matched and asked for ``PlacementMode/suggest``.
    case suggestion(PlacementRule, ResolvedPlacement)
    /// A rule matched and the window should be moved.
    case place(PlacementRule, ResolvedPlacement)
}

/// Runs the full pipeline for one window: filter → rule → role → geometry.
///
/// Pure logic, no Accessibility calls — writing the frame is the caller's job.
/// That split is what makes the interesting half of `watch` testable.
public struct PlacementCoordinator: Sendable {

    public var filter: DefaultWindowFilter
    public var ruleEngine: DefaultRuleEngine
    public var zoneResolver: DefaultZoneResolver

    public init(
        filter: DefaultWindowFilter = DefaultWindowFilter(),
        ruleEngine: DefaultRuleEngine = DefaultRuleEngine(),
        zoneResolver: DefaultZoneResolver = DefaultZoneResolver()
    ) {
        self.filter = filter
        self.ruleEngine = ruleEngine
        self.zoneResolver = zoneResolver
    }

    public func decide(
        for window: WindowSnapshot,
        configuration: Configuration,
        profile: Profile,
        geometry: DisplayGeometry
    ) -> PlacementDecision {
        if let rejection = filter.rejection(for: window, defaults: configuration.defaults) {
            return .filtered(rejection)
        }

        guard let rule = ruleEngine.firstMatch(
            for: window,
            in: configuration.rules,
            defaults: configuration.defaults
        ) else {
            return .noRuleMatched
        }

        let resolved = zoneResolver.resolvePlacement(
            role: rule.action.role,
            share: rule.action.share,
            profile: profile,
            configuration: configuration,
            geometry: geometry
        )

        switch resolved {
        case let .failure(problem):
            return .unresolvable(rule, problem)
        case let .success(placement):
            // `suggest` needs an overlay to suggest anything with. Until that
            // exists it is reported, not silently upgraded to a move.
            if rule.action.mode == .suggest {
                return .suggestion(rule, placement)
            }
            return .place(rule, placement)
        }
    }
}
