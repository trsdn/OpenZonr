import Foundation

/// One window, reduced to the three operations placement actually needs.
///
/// This is the seam between the logic and the Accessibility API. Everything
/// above it — rule evaluation, zone resolution, the retry loop — works against
/// this protocol and is therefore testable without a window server. The real
/// implementation wraps an `AXUIElement`; the tests use a fake that can be told
/// to behave like Outlook and resize itself after being placed.
@MainActor
public protocol PlaceableWindow: AnyObject {
    /// The window as it looked when it was discovered.
    var snapshot: WindowSnapshot { get }
    /// Reads the current frame, `nil` if the window is gone.
    func readFrame() -> WindowFrame?
    /// Writes position and size. Returns `false` if the API call itself failed.
    @discardableResult
    func write(frame: WindowFrame) -> Bool
}

/// Writes position and size to a window, retrying while the app fights back.
@MainActor
public protocol WindowPlacer {
    func place(
        _ window: any PlaceableWindow,
        at placement: ResolvedPlacement,
        retry: RetryPolicy
    ) async -> PlacementOutcome
}

/// A single write-and-verify cycle, the unit of the retry log.
///
/// The whole point of the tracer bullet is to find out how many of these are
/// needed in practice, so the record is a first-class type rather than a log
/// string.
public struct PlacementAttempt: Hashable, Sendable {
    /// 1-based attempt number.
    public var number: Int
    /// Frame that was requested.
    public var requested: WindowFrame
    /// Frame the window actually had afterwards, `nil` if it could not be read.
    public var actual: WindowFrame?
    /// Largest per-edge deviation, `nil` if `actual` is `nil`.
    public var deviation: Double?
    /// `true` if the deviation was within ``RetryPolicy/tolerance``.
    public var accepted: Bool
    /// Wall clock time spent in this attempt, including the wait before it.
    public var elapsed: Duration

    public init(
        number: Int,
        requested: WindowFrame,
        actual: WindowFrame?,
        deviation: Double?,
        accepted: Bool,
        elapsed: Duration
    ) {
        self.number = number
        self.requested = requested
        self.actual = actual
        self.deviation = deviation
        self.accepted = accepted
        self.elapsed = elapsed
    }
}

/// Places a window and verifies the result, repeating according to
/// ``RetryPolicy``.
///
/// Why verify at all: setting `kAXPositionAttribute` and `kAXSizeAttribute`
/// reports success even when the application immediately overrides the frame.
/// Office and Electron apps routinely resize themselves a few hundred
/// milliseconds after their window appears, so a fire-and-forget write is not
/// placement, it is a suggestion.
///
/// Why size is written twice: an app may clamp a size that does not fit at the
/// *old* position (for example because the old screen is smaller). Writing
/// position, then size, then position again is the sequence that survives that,
/// and it costs nothing when the app is well behaved.
@MainActor
public struct RetryingWindowPlacer: WindowPlacer {

    /// Injected so tests can run the retry loop without real waiting.
    public var wait: @Sendable (Duration) async -> Void

    /// Receives every attempt, in order. The CLI prints them; a future UI could
    /// show them.
    public var record: ((PlacementAttempt) -> Void)?

    /// Reads the clock. Injected for deterministic tests.
    public var now: @Sendable () -> ContinuousClock.Instant

    public init(
        wait: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now },
        record: ((PlacementAttempt) -> Void)? = nil
    ) {
        self.wait = wait
        self.now = now
        self.record = record
    }

    public func place(
        _ window: any PlaceableWindow,
        at placement: ResolvedPlacement,
        retry: RetryPolicy
    ) async -> PlacementOutcome {
        let target = placement.frame
        var lastActual: WindowFrame?
        let attempts = max(1, retry.attempts)

        for attempt in 1...attempts {
            let started = now()

            // The initial delay gives an app that is still laying out its window
            // the chance to settle first; without it the first attempt is
            // almost guaranteed to be overwritten.
            let delay = attempt == 1 ? retry.initialDelay : retry.interval
            if delay > 0 { await wait(.seconds(delay)) }

            window.write(frame: target)

            guard let actual = window.readFrame() else {
                record?(
                    PlacementAttempt(
                        number: attempt,
                        requested: target,
                        actual: nil,
                        deviation: nil,
                        accepted: false,
                        elapsed: now() - started
                    )
                )
                return .rejectedByApplication(actual: lastActual ?? window.snapshot.frame, attempts: attempt)
            }

            let deviation = actual.maximumDeviation(from: target)
            let accepted = deviation <= retry.tolerance
            lastActual = actual

            record?(
                PlacementAttempt(
                    number: attempt,
                    requested: target,
                    actual: actual,
                    deviation: deviation,
                    accepted: accepted,
                    elapsed: now() - started
                )
            )

            if accepted {
                // One more read after the last configured interval would be the
                // honest check for "does it *stay*", but that is a watching
                // behaviour the concept explicitly rules out. The window belongs
                // to the user the moment it is in place.
                return .placed(attempts: attempt)
            }
        }

        return .rejectedByApplication(
            actual: lastActual ?? window.snapshot.frame,
            attempts: attempts
        )
    }
}
