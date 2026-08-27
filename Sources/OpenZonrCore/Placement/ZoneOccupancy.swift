import Foundation

public struct Displacement: Hashable, Sendable {
    public var window: WindowIdentifier
    public var newPlacement: ResolvedPlacement

    public init(window: WindowIdentifier, newPlacement: ResolvedPlacement) {
        self.window = window
        self.newPlacement = newPlacement
    }
}

public enum ConflictResolution: Hashable, Sendable {
    /// Place the window as requested; nothing had to give way.
    case place
    /// Place the window and move the listed occupants elsewhere.
    case placeDisplacing([Displacement])
    /// Leave the window where the system opened it.
    case skip
}

public struct ZoneOccupancy: Sendable {
    private struct ZoneKey: Hashable, Sendable {
        var display: DisplayAlias
        var zone: ZoneID
    }

    private var occupantsByZone: [ZoneKey: [WindowIdentifier]]
    private var placementsByWindow: [WindowIdentifier: ResolvedPlacement]
    private var manualOverrides: [WindowIdentifier: Date]

    public init() {
        occupantsByZone = [:]
        placementsByWindow = [:]
        manualOverrides = [:]
    }

    /// Records that `window` now occupies `placement`, removing it from any zone it held before.
    public mutating func register(_ window: WindowIdentifier, at placement: ResolvedPlacement) {
        removeFromCurrentZone(window)

        placementsByWindow[window] = placement
        let key = ZoneKey(display: placement.display, zone: placement.zone)
        occupantsByZone[key, default: []].append(window)
    }

    /// Forgets a window entirely — it was closed.
    public mutating func forget(_ window: WindowIdentifier) {
        removeFromCurrentZone(window)
        placementsByWindow[window] = nil
        manualOverrides[window] = nil
    }

    /// Windows currently held by a zone, in the order they were registered.
    public func occupants(of zone: ZoneID, on display: DisplayAlias) -> [WindowIdentifier] {
        occupantsByZone[ZoneKey(display: display, zone: zone)] ?? []
    }

    /// The placement a window currently holds, if any.
    public func placement(of window: WindowIdentifier) -> ResolvedPlacement? {
        placementsByWindow[window]
    }

    /// Records that the user moved this window by hand.
    public mutating func markManuallyOverridden(_ window: WindowIdentifier, at date: Date) {
        manualOverrides[window] = date
    }

    /// Whether the window is currently off limits because the user moved it.
    public func isManuallyOverridden(_ window: WindowIdentifier, now: Date, policy: ConflictPolicy) -> Bool {
        guard policy.honorManualOverride, let overriddenAt = manualOverrides[window] else {
            return false
        }

        guard let timeout = policy.manualOverrideTimeout else {
            return true
        }

        return now.timeIntervalSince(overriddenAt) <= timeout
    }

    /// Drops override records that have expired, so the table does not grow forever.
    public mutating func pruneExpiredOverrides(now: Date, policy: ConflictPolicy) {
        guard policy.honorManualOverride, let timeout = policy.manualOverrideTimeout else {
            return
        }

        manualOverrides = manualOverrides.filter { _, overriddenAt in
            now.timeIntervalSince(overriddenAt) <= timeout
        }
    }

    /// Decides what happens to `window` aiming at `target`, and applies the decision to the occupancy state.
    ///
    /// The incoming window's manual override state is not checked here: callers own
    /// that gate so displacement rules and placement eligibility stay separate.
    public mutating func apply(
        _ window: WindowIdentifier,
        target: ResolvedPlacement,
        policy: ConflictPolicy,
        fallback: ResolvedPlacement?,
        now: Date
    ) -> ConflictResolution {
        let targetOccupants = occupants(of: target.zone, on: target.display).filter { $0 != window }

        guard !targetOccupants.isEmpty else {
            register(window, at: target)
            return .place
        }

        switch policy.occupiedZone {
        case .stack:
            register(window, at: target)
            return .place
        case .skip:
            return .skip
        case .replace:
            guard let fallback else {
                register(window, at: target)
                return .place
            }

            let displacedWindows = targetOccupants.filter {
                !isManuallyOverridden($0, now: now, policy: policy)
            }

            register(window, at: target)

            let displacements = displacedWindows.map {
                register($0, at: fallback)
                return Displacement(window: $0, newPlacement: fallback)
            }

            if displacements.isEmpty {
                return .place
            }

            return .placeDisplacing(displacements)
        }
    }

    private mutating func removeFromCurrentZone(_ window: WindowIdentifier) {
        guard let placement = placementsByWindow[window] else {
            return
        }

        let key = ZoneKey(display: placement.display, zone: placement.zone)
        occupantsByZone[key]?.removeAll { $0 == window }
        if occupantsByZone[key]?.isEmpty == true {
            occupantsByZone[key] = nil
        }
    }
}
