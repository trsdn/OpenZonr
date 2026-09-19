import Foundation

/// How moving one displaced occupant went.
public enum DisplacementOutcome: Hashable, Sendable {
    case moved(attempts: Int)
    /// Closed, or not known to the caller any more: nothing to move.
    case windowGone
    case failed(PlacementOutcome)
    case cancelled
}

public struct DisplacementReport: Hashable, Sendable {
    public var window: WindowIdentifier
    public var outcome: DisplacementOutcome

    public init(window: WindowIdentifier, outcome: DisplacementOutcome) {
        self.window = window
        self.outcome = outcome
    }
}

public struct PlacementJobResult: Hashable, Sendable {
    public var displaced: [DisplacementReport]
    /// Outcome for the incoming window itself.
    public var outcome: PlacementOutcome

    public init(displaced: [DisplacementReport], outcome: PlacementOutcome) {
        self.displaced = displaced
        self.outcome = outcome
    }
}

/// One incoming window: first move the occupants it displaces, then place it.
///
/// ``ZoneOccupancy`` decides who has to give way and books them at the fallback
/// zone; this type is what makes that booking true. Occupants move first so the
/// incoming window never lands on top of a window that is still there. Every
/// step checks `isCurrent` before it writes, so a pause, stop or newer request
/// lets the job abandon itself between windows and between attempts.
@MainActor
public struct PlacementJob {

    public var placer: RetryingWindowPlacer
    /// Finds the live window behind an identifier, `nil` if it is not known.
    public var windowFor: (WindowIdentifier) -> (any PlaceableWindow)?
    /// Converts a placement into the space the windows are written in.
    public var toWindowSpace: (ResolvedPlacement) -> ResolvedPlacement

    public init(
        placer: RetryingWindowPlacer,
        windowFor: @escaping (WindowIdentifier) -> (any PlaceableWindow)?,
        toWindowSpace: @escaping (ResolvedPlacement) -> ResolvedPlacement = { $0 }
    ) {
        self.placer = placer
        self.windowFor = windowFor
        self.toWindowSpace = toWindowSpace
    }

    public func run(
        window: any PlaceableWindow,
        at target: ResolvedPlacement,
        displacing displacements: [Displacement],
        retry: RetryPolicy,
        isCurrent: () -> Bool
    ) async -> PlacementJobResult {
        var reports: [DisplacementReport] = []

        // An occupant has been on screen for a while: no initial delay.
        let occupantRetry = RetryPolicy(
            attempts: retry.attempts,
            initialDelay: 0,
            interval: retry.interval,
            tolerance: retry.tolerance
        )

        for (index, displacement) in displacements.enumerated() {
            guard isCurrent() else {
                reports += displacements[index...].map {
                    DisplacementReport(window: $0.window, outcome: .cancelled)
                }
                return PlacementJobResult(displaced: reports, outcome: .cancelled(attempts: 0))
            }

            guard let occupant = windowFor(displacement.window), occupant.readFrame() != nil else {
                reports.append(DisplacementReport(window: displacement.window, outcome: .windowGone))
                continue
            }

            let outcome = await placer.place(
                occupant,
                at: toWindowSpace(displacement.newPlacement),
                retry: occupantRetry,
                isCurrent: isCurrent
            )
            let mapped: DisplacementOutcome
            switch outcome {
            case let .placed(attempts): mapped = .moved(attempts: attempts)
            case .cancelled: mapped = .cancelled
            default: mapped = .failed(outcome)
            }
            reports.append(DisplacementReport(window: displacement.window, outcome: mapped))
        }

        let own = await placer.place(window, at: toWindowSpace(target), retry: retry, isCurrent: isCurrent)
        return PlacementJobResult(displaced: reports, outcome: own)
    }
}

extension ZoneOccupancy {

    /// Brings the occupancy in line with what the job actually achieved.
    ///
    /// `claims` are those taken right after the decision (the incoming window
    /// and everyone it displaced). Achieved claims stay, the others are undone.
    /// A claim that a newer request has replaced is left alone by
    /// ``rollback(_:)``.
    public mutating func settle(
        _ result: PlacementJobResult,
        claims: [OccupancyClaim],
        window: WindowIdentifier
    ) {
        var undo: [OccupancyClaim] = []

        for claim in claims {
            if claim.window == window {
                if case .placed = result.outcome { continue }
                undo.append(claim)
                continue
            }

            guard let report = result.displaced.first(where: { $0.window == claim.window }) else {
                undo.append(claim)
                continue
            }
            switch report.outcome {
            case .moved:
                continue
            case .windowGone:
                forget(claim.window, ifUnchangedSince: claim.epoch)
            case .failed, .cancelled:
                undo.append(claim)
            }
        }

        rollback(undo)
    }
}
