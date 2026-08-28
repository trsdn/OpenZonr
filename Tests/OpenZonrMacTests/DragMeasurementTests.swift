import Foundation
import Testing

@testable import OpenZonrCore
@testable import OpenZonrMac

/// The statistics `openzonr dragprobe` reports.
///
/// Tested separately from the trackers on purpose: a number computed inside the
/// thing it measures is one refactoring away from being wrong in a way nobody
/// notices, and the whole point of the probe is that its numbers can be trusted.
struct DragMeasurementTests {

    private func measurement(arrivalsInMilliseconds: [Int], latencies: [Int?] = []) -> DragMeasurement {
        var measurement = DragMeasurement()
        for (index, arrival) in arrivalsInMilliseconds.enumerated() {
            let latency = index < latencies.count ? latencies[index] : nil
            measurement.add(
                DragMeasurement.Sample(
                    arrival: .milliseconds(arrival),
                    latency: latency.map { Duration.milliseconds($0) }
                )
            )
        }
        return measurement
    }

    @Test("Die Rate ergibt sich aus Abständen, nicht aus der Messdauer")
    func rateComesFromIntervals() {
        // Ten events, nine intervals of 10 ms — 100 per second. Dividing the
        // count by the span instead would report 111 and the error would grow
        // as the sample shrinks.
        let measurement = measurement(arrivalsInMilliseconds: Array(stride(from: 0, through: 90, by: 10)))
        #expect(measurement.count == 10)
        #expect(measurement.eventsPerSecond == 100)
    }

    @Test("Ein einzelnes Ereignis hat keine Rate")
    func oneEventHasNoRate() {
        // Not zero. Zero reads as "nothing arrived", which is a different and
        // much more interesting finding than "too little to compute a rate".
        #expect(measurement(arrivalsInMilliseconds: [5]).eventsPerSecond == nil)
        #expect(DragMeasurement().eventsPerSecond == nil)
    }

    @Test("Die größte Lücke ist der Wert, den der Nutzer sieht")
    func theLargestGapIsWhatTheUserNotices() {
        let measurement = measurement(arrivalsInMilliseconds: [0, 10, 60, 70])
        #expect(measurement.largestGap == .milliseconds(50))
    }

    @Test("Die Spanne reicht vom ersten bis zum letzten Ereignis")
    func theSpanCoversFirstToLast() {
        #expect(measurement(arrivalsInMilliseconds: [10, 40, 110]).span == .milliseconds(100))
        #expect(DragMeasurement().span == .zero)
    }

    @Test("Ohne Zeitstempel gibt es keine Latenz")
    func noLatencyWithoutTimestamps() {
        // An Accessibility notification carries no timestamp. Reporting 0 ms
        // there would be an invented measurement.
        let measurement = measurement(arrivalsInMilliseconds: [0, 10, 20])
        #expect(measurement.medianLatency == nil)
        #expect(measurement.worstLatency == nil)
    }

    @Test("Perzentile werden über die sortierten Latenzen gebildet")
    func percentilesUseSortedLatencies() {
        let measurement = measurement(
            arrivalsInMilliseconds: [0, 10, 20, 30, 40],
            latencies: [9, 1, 5, 3, 7]
        )
        #expect(measurement.medianLatency == .milliseconds(5))
        #expect(measurement.worstLatency == .milliseconds(9))
        #expect(measurement.latency(percentile: 0) == .milliseconds(1))
    }

    @Test("Ereignisse ohne Latenz zählen für die Rate, aber nicht für die Latenz")
    func samplesWithoutLatencyStillCount() {
        let measurement = measurement(
            arrivalsInMilliseconds: [0, 10, 20],
            latencies: [nil, 4, nil]
        )
        #expect(measurement.count == 3)
        #expect(measurement.medianLatency == .milliseconds(4))
    }

    @Test("Unter einer Millisekunde wird genauer gedruckt")
    func subMillisecondValuesKeepTheirDigits() {
        // "0.0 ms" for 300 µs would look like a measurement that came out zero.
        #expect(Duration.microseconds(300).millisecondsText == "0.300 ms")
        #expect(Duration.milliseconds(42).millisecondsText == "42.0 ms")
    }
}

/// Converting a point between the two coordinate systems.
struct PointFlipTests {

    @Test("Ein Punkt wird an derselben Achse gespiegelt wie ein Rahmen")
    func aPointFlipsAroundTheSameAxisAsAFrame() {
        // The frame formula subtracts the height; reusing it for a point by
        // passing height 0 happens to work, and is exactly the kind of reuse
        // that breaks the day someone adds a bounds check. A point has its own
        // overload.
        let primaryTopY: Double = 1440
        #expect(ScreenArrangement.flipVertically(ScreenPoint(x: 100, y: 0), primaryTopY: primaryTopY).y == 1440)
        #expect(ScreenArrangement.flipVertically(ScreenPoint(x: 100, y: 1440), primaryTopY: primaryTopY).y == 0)
    }

    @Test("Zweimal spiegeln ergibt den Ausgangspunkt")
    func flippingTwiceReturnsTheOriginalPoint() {
        let point = ScreenPoint(x: 640, y: 2000)
        let there = ScreenArrangement.flipVertically(point, primaryTopY: 1440)
        let back = ScreenArrangement.flipVertically(there, primaryTopY: 1440)
        #expect(back == point)
    }

    @Test("Ein Display über dem Hauptmonitor bekommt eine negative Koordinate")
    func aDisplayAboveThePrimaryGetsANegativeCoordinate() {
        // The real arrangement of the measuring machine: a 1920×1080 display
        // above a 5120×1440 primary. AppKit reports its bottom edge at y = 1440,
        // Accessibility at y = -1080. Getting this wrong puts the window on the
        // wrong screen, not merely a few points off.
        let flipped = ScreenArrangement.flipVertically(ScreenPoint(x: 0, y: 2520), primaryTopY: 1440)
        #expect(flipped.y == -1080)
    }
}
