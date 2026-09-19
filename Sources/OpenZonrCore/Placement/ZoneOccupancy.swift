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

/// What a decision claimed for one window, so a failed or cancelled placement can undo exactly that.
///
/// `epoch` is the window's claim counter right after the decision. A rollback
/// applies only while the counter is unchanged, which keeps an older, cancelled
/// job from undoing what a newer request for the same window has claimed since.
public struct OccupancyClaim: Hashable, Sendable {
    public var window: WindowIdentifier
    public var epoch: Int
    /// The placement the window held before the decision, `nil` if it held none.
    public var restoring: ResolvedPlacement?

    public init(window: WindowIdentifier, epoch: Int, restoring: ResolvedPlacement?) {
        self.window = window
        self.epoch = epoch
        self.restoring = restoring
    }
}

/// What the caller could observe about a window that occupancy still lists.
public enum OccupantStatus: Sendable {
    /// Still open and still where it was put.
    case present
    /// Open, but no longer in its zone (moved by hand, or by the app itself).
    case movedAway
    /// Closed, or its application ended.
    case gone
}

public struct ZoneOccupancy: Sendable {
    private struct ZoneKey: Hashable, Sendable {
        var display: DisplayAlias
        var zone: ZoneID
    }

    private var occupantsByZone: [ZoneKey: [WindowIdentifier]]
    private var placementsByWindow: [WindowIdentifier: ResolvedPlacement]
    private var manualOverrides: [WindowIdentifier: Date]
    private var epochs: [WindowIdentifier: Int]

    public init() {
        occupantsByZone = [:]
        placementsByWindow = [:]
        manualOverrides = [:]
        epochs = [:]
    }

    /// Records that `window` now occupies `placement`, removing it from any zone it held before.
    public mutating func register(_ window: WindowIdentifier, at placement: ResolvedPlacement) {
        removeFromCurrentZone(window)

        placementsByWindow[window] = placement
        epochs[window, default: 0] += 1
        let key = ZoneKey(display: placement.display, zone: placement.zone)
        occupantsByZone[key, default: []].append(window)
    }

    /// Forgets a window entirely — it was closed.
    public mutating func forget(_ window: WindowIdentifier) {
        removeFromCurrentZone(window)
        placementsByWindow[window] = nil
        manualOverrides[window] = nil
        epochs[window] = nil
    }

    /// Forgets a window only while nothing has claimed it since `epoch`.
    ///
    /// The guarded counterpart of ``forget(_:)`` for callers that decided to
    /// forget earlier and awaited in between: a newer claim, its manual
    /// override and its epoch must not be wiped by the older decision.
    public mutating func forget(_ window: WindowIdentifier, ifUnchangedSince epoch: Int) {
        guard (epochs[window] ?? 0) == epoch else { return }
        forget(window)
    }

    /// Every window that currently holds a zone.
    public var trackedWindows: Set<WindowIdentifier> { Set(placementsByWindow.keys) }

    /// Frees the window's zone but keeps its manual override on record.
    public mutating func release(_ window: WindowIdentifier) {
        removeFromCurrentZone(window)
        placementsByWindow[window] = nil
        epochs[window, default: 0] += 1
    }

    /// The claims a decision made, taken right after it ran.
    ///
    /// `earlier` is a copy of the occupancy from *before* the decision; it
    /// supplies what to restore.
    public func claims(for windows: [WindowIdentifier], since earlier: ZoneOccupancy) -> [OccupancyClaim] {
        windows.map {
            OccupancyClaim(window: $0, epoch: epochs[$0] ?? 0, restoring: earlier.placement(of: $0))
        }
    }

    /// Undoes claims whose window has not been claimed again since.
    public mutating func rollback(_ claims: [OccupancyClaim]) {
        for claim in claims where (epochs[claim.window] ?? 0) == claim.epoch {
            if let previous = claim.restoring {
                register(claim.window, at: previous)
            } else {
                release(claim.window)
            }
        }
    }

    /// Forgets every window of a process — its application terminated.
    public mutating func forgetApplication(processIdentifier: Int32) {
        let doomed = Set(placementsByWindow.keys).union(manualOverrides.keys)
            .filter { $0.processIdentifier == processIdentifier }
        for window in doomed { forget(window) }
    }

    /// Drops what the caller can no longer confirm.
    ///
    /// Occupancy is a claim about the screen, and the screen changes without
    /// telling us: windows are closed, dragged away, or resized by their app.
    /// Checking lazily, right before a decision reads the table, avoids
    /// watching windows after placement.
    public mutating func reconcile(_ status: (WindowIdentifier, ResolvedPlacement) -> OccupantStatus) {
        for (window, placement) in placementsByWindow {
            switch status(window, placement) {
            case .present: break
            case .movedAway: release(window)
            case .gone: forget(window)
            }
        }
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

    /// When the user moved this window by hand, if that is still on record.
    ///
    /// Unlike ``isManuallyOverridden(_:now:policy:)`` this reports the stored
    /// state itself rather than the state as a policy interprets it, which is
    /// the only way to observe whether ``pruneExpiredOverrides(now:policy:)``
    /// actually dropped anything.
    func manualOverrideDate(of window: WindowIdentifier) -> Date? {
        manualOverrides[window]
    }

    /// Number of windows currently on record as manually overridden.
    var manualOverrideCount: Int { manualOverrides.count }

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
