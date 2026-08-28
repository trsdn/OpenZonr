import Foundation

/// The numbers a drag-detection path produces, and nothing else.
///
/// Pure and separate from the trackers on purpose. The measurement is the part
/// of this comparison that has to be trustworthy, and a statistic computed
/// inside the thing it measures is one refactoring away from being wrong in a
/// way nobody notices. This type takes samples and reports; it never observes.
public struct DragMeasurement: Sendable {

    /// One observed event.
    public struct Sample: Hashable, Sendable {
        /// When the event reached this process, on a monotonic clock.
        public var arrival: Duration
        /// Delivery latency, when the source provides a stamp to compare with.
        /// `nil` for sources that do not — Accessibility notifications carry no
        /// timestamp, and inventing one would be a fabricated number.
        public var latency: Duration?

        public init(arrival: Duration, latency: Duration? = nil) {
            self.arrival = arrival
            self.latency = latency
        }
    }

    public private(set) var samples: [Sample] = []

    public init() {}

    public mutating func add(_ sample: Sample) {
        samples.append(sample)
    }

    public var count: Int { samples.count }

    /// Time from the first to the last event.
    public var span: Duration {
        guard let first = samples.first?.arrival, let last = samples.last?.arrival else { return .zero }
        return last - first
    }

    /// Events per second over ``span``.
    ///
    /// `nil` for fewer than two events: one event has no rate, and reporting
    /// zero would read as "nothing arrived", which is a different finding.
    public var eventsPerSecond: Double? {
        guard samples.count >= 2 else { return nil }
        let seconds = span.seconds
        guard seconds > 0 else { return nil }
        return Double(samples.count - 1) / seconds
    }

    /// Longest gap between two consecutive events.
    ///
    /// The interesting number for an overlay: the worst case is what the user
    /// perceives as the highlight lagging behind the pointer.
    public var largestGap: Duration? {
        guard samples.count >= 2 else { return nil }
        var largest = Duration.zero
        for index in 1..<samples.count {
            let gap = samples[index].arrival - samples[index - 1].arrival
            if gap > largest { largest = gap }
        }
        return largest
    }

    /// Latency at a percentile between `0` and `1`, `nil` when nothing carried a
    /// latency.
    public func latency(percentile: Double) -> Duration? {
        let latencies = samples.compactMap(\.latency).sorted()
        guard !latencies.isEmpty else { return nil }
        let clamped = min(max(percentile, 0), 1)
        let index = Int((Double(latencies.count - 1) * clamped).rounded())
        return latencies[index]
    }

    public var medianLatency: Duration? { latency(percentile: 0.5) }
    public var worstLatency: Duration? { latency(percentile: 1) }
}

extension Duration {
    /// The duration in seconds as a `Double`.
    public var seconds: Double {
        let components = self.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    /// Milliseconds, with enough digits to stay honest below one millisecond.
    public var millisecondsText: String {
        let milliseconds = seconds * 1000
        return String(format: milliseconds < 1 ? "%.3f ms" : "%.1f ms", milliseconds)
    }
}
