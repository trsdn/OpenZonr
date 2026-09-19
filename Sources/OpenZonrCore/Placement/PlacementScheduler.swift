import Foundation

/// Owns pending placement work: one live job per window, all of it cancellable.
///
/// Placement is not instantaneous. The retry loop waits before and between
/// writes, and an application that is still laying out its window is exactly
/// why. Work that outlives the decision needs an owner, or "paused" and
/// "stopped" stop being true: a write can land seconds after the user said stop.
///
/// Two independent guards make a job abandon itself:
/// - its own ticket — a newer job for the same window replaced it;
/// - the scheduler `generation` — pause, stop, reload or a profile change
///   called ``cancelAll()``.
/// Cooperative `Task` cancellation is checked as well.
@MainActor
public final class PlacementScheduler {

    public typealias Work = @MainActor (_ isCurrent: @MainActor @escaping () -> Bool) async -> Void

    /// Advances whenever everything is cancelled at once. Delayed callbacks that
    /// are not jobs (the frame-read retry, the observer retry) capture it and
    /// compare before acting.
    public private(set) var generation = 0

    private var nextTicket = 0
    private var currentTicket: [WindowIdentifier: Int] = [:]
    private var live: [Int: Task<Void, Never>] = [:]
    private var windowOfTicket: [Int: WindowIdentifier] = [:]

    public init() {}

    /// Jobs that are still the current one for their window.
    public var pendingCount: Int { currentTicket.count }

    /// Starts `work` for `window`, cancelling any older job for the same window.
    public func submit(_ window: WindowIdentifier, work: @escaping Work) {
        cancel(window)

        nextTicket += 1
        let ticket = nextTicket
        let startedGeneration = generation
        currentTicket[window] = ticket
        windowOfTicket[ticket] = window

        live[ticket] = Task { @MainActor [weak self] in
            let isCurrent: @MainActor () -> Bool = { [weak self] in
                guard let self, !Task.isCancelled else { return false }
                return self.generation == startedGeneration && self.currentTicket[window] == ticket
            }
            await work(isCurrent)
            self?.finish(ticket)
        }
    }

    /// Cancels the job for one window, if any.
    public func cancel(_ window: WindowIdentifier) {
        guard let ticket = currentTicket.removeValue(forKey: window) else { return }
        live[ticket]?.cancel()
    }

    /// Cancels the jobs of every window the predicate selects.
    public func cancel(where matches: (WindowIdentifier) -> Bool) {
        for window in currentTicket.keys.filter(matches) { cancel(window) }
    }

    /// Cancels everything and moves on to a new generation.
    public func cancelAll() {
        generation += 1
        for task in live.values { task.cancel() }
        currentTicket.removeAll()
    }

    /// Returns once every started job — cancelled ones included — has unwound.
    public func idle() async {
        while let task = live.values.first {
            await task.value
        }
    }

    private func finish(_ ticket: Int) {
        live[ticket] = nil
        if let window = windowOfTicket.removeValue(forKey: ticket), currentTicket[window] == ticket {
            currentTicket[window] = nil
        }
    }
}
