import Foundation

/// The verdict for one window: what should happen to it, and on what grounds.
///
/// Every case carries enough context for the diagnostics view to render a full
/// sentence. That is the reason this is not an optional `ResolvedPlacement`:
/// "nothing happened" is a family of quite different situations, and telling
/// them apart is what makes the tool debuggable.
public enum PlacementDecision: Hashable, Sendable {

    /// Move the window to `placement`, displacing the listed occupants.
    case place(ResolvedPlacement, rule: PlacementRule, displacing: [Displacement])

    /// Offer the placement but leave the window alone, per ``PlacementMode/suggest``.
    case suggest(ResolvedPlacement, rule: PlacementRule)

    /// Do nothing, for the stated reason.
    case skip(PlacementOutcome, reason: SkipReason)

    /// The placement target, for the cases that have one.
    public var placement: ResolvedPlacement? {
        switch self {
        case let .place(placement, _, _), let .suggest(placement, _):
            return placement
        case .skip:
            return nil
        }
    }

    /// The rule that produced this decision, if a rule was reached at all.
    public var rule: PlacementRule? {
        switch self {
        case let .place(_, rule, _), let .suggest(_, rule):
            return rule
        case .skip:
            return nil
        }
    }
}

/// Why a window was not placed.
public enum SkipReason: Hashable, Sendable {
    /// The pre-filter rejected the window.
    case filtered(WindowRejectionReason)
    /// No enabled rule matched.
    case noMatchingRule
    /// The attached displays match no profile. OpenZonr does not guess a
    /// profile, so there is nothing to resolve against.
    case unknownSetup(SetupFingerprint)
    /// The user moved this window by hand and the conflict policy honours that.
    case manuallyOverridden
    /// The zone the rule points at could not be resolved. This is a broken
    /// configuration, not a broken window — the validator should have caught it.
    case unresolvableZone(ZoneResolutionFailure)
    /// The target zone was taken and the policy says to leave the window alone.
    case zoneOccupied(display: DisplayAlias, zone: ZoneID)
}

/// Chains the pure steps of the pipeline into a single decision.
///
/// Filter → rule → profile → zone → occupancy. Nothing here talks to macOS: the
/// window arrives as a snapshot, the screens arrive as visible frames, and the
/// clock arrives as a parameter. That is what makes the interesting half of
/// OpenZonr testable without a window server or an Accessibility grant.
public struct PlacementDecider {

    private let filter: any WindowFilter
    private let ruleEngine: any RuleEngine
    private let profileResolver: any ProfileResolver
    private let zoneResolver: any ZoneResolver

    public init(
        filter: any WindowFilter = DefaultWindowFilter(),
        ruleEngine: any RuleEngine = DefaultRuleEngine(),
        profileResolver: any ProfileResolver = DefaultProfileResolver(),
        zoneResolver: any ZoneResolver = DefaultZoneResolver()
    ) {
        self.filter = filter
        self.ruleEngine = ruleEngine
        self.profileResolver = profileResolver
        self.zoneResolver = zoneResolver
    }

    /// Builds a decider whose filter knows the rule set, so rules that opt out
    /// of the "first window after launch" default stay reachable.
    public static func standard(for rules: CompiledRuleSet) -> PlacementDecider {
        PlacementDecider(filter: DefaultWindowFilter(rules: rules))
    }

    /// Decides what happens to `window`, updating `occupancy` as a side effect.
    ///
    /// The occupancy is `inout` rather than owned because a decision and the
    /// bookkeeping that follows from it must not drift apart: a caller cannot
    /// accidentally act on a placement without recording it.
    public func decide(
        for window: WindowSnapshot,
        identifier: WindowIdentifier,
        configuration: Configuration,
        rules: CompiledRuleSet,
        setup: SetupFingerprint,
        visibleFrames: VisibleFrames,
        occupancy: inout ZoneOccupancy,
        now: Date
    ) -> PlacementDecision {
        let filterResult = filter.evaluate(window, defaults: configuration.defaults)
        if let reason = filterResult.rejectionReason {
            return .skip(.notApplicable, reason: .filtered(reason))
        }

        guard let rule = ruleEngine.firstMatch(for: window, in: rules, defaults: configuration.defaults) else {
            return .skip(.notApplicable, reason: .noMatchingRule)
        }

        guard let profile = profileResolver.activeProfile(for: setup, in: configuration) else {
            return .skip(.notApplicable, reason: .unknownSetup(setup))
        }

        // Checked after the rule so the log can still name the rule that would
        // have applied, which is what a user asking "why didn't it move?" wants
        // to know.
        if occupancy.isManuallyOverridden(identifier, now: now, policy: configuration.defaults.conflict) {
            return .skip(.skippedManualOverride, reason: .manuallyOverridden)
        }

        let resolution = zoneResolver.resolve(
            role: rule.action.role,
            share: rule.action.share,
            profile: profile,
            configuration: configuration,
            visibleFrames: visibleFrames
        )

        let placement: ResolvedPlacement
        switch resolution {
        case let .success(resolved):
            placement = resolved
        case let .failure(failure):
            return .skip(.notApplicable, reason: .unresolvableZone(failure))
        }

        // A suggestion changes nothing on screen, so it must not claim the zone
        // either — otherwise a proposal nobody accepted would displace windows.
        if rule.action.mode == .suggest {
            return .suggest(placement, rule: rule)
        }

        let fallback = fallbackPlacement(
            for: profile,
            configuration: configuration,
            visibleFrames: visibleFrames
        )

        switch occupancy.apply(
            identifier,
            target: placement,
            policy: configuration.defaults.conflict,
            fallback: fallback,
            now: now
        ) {
        case .place:
            return .place(placement, rule: rule, displacing: [])
        case let .placeDisplacing(displacements):
            return .place(placement, rule: rule, displacing: displacements)
        case .skip:
            return .skip(.notApplicable, reason: .zoneOccupied(display: placement.display, zone: placement.zone))
        }
    }

    /// Where a displaced window goes: the profile's fallback zone.
    ///
    /// Resolved through the same path as any other placement, so a fallback
    /// binding pointing at a missing zone fails here instead of producing a
    /// frame nobody computed. A `nil` result simply means nothing can be
    /// displaced, which ``ZoneOccupancy`` treats as "stack instead".
    private func fallbackPlacement(
        for profile: Profile,
        configuration: Configuration,
        visibleFrames: VisibleFrames
    ) -> ResolvedPlacement? {
        try? zoneResolver.resolveFallback(
            profile: profile,
            configuration: configuration,
            visibleFrames: visibleFrames
        ).get()
    }
}
