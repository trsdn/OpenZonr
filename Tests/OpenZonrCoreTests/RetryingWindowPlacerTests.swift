import Foundation
import Testing

@testable import OpenZonrCore

/// A window that can be told to fight back, the way real applications do.
///
/// Office and Electron applications lay out their window *after* it appears and
/// overwrite whatever was set in between. `resistUntilAttempt` reproduces that:
/// the window accepts the frame, then silently reverts to its own idea of a
/// good size until the given attempt number.
@MainActor
final class FakeWindow: PlaceableWindow {

    private(set) var snapshot: WindowSnapshot
    private var frame: WindowFrame
    private(set) var writes: [WindowFrame] = []

    /// Attempts before this number are reverted, imitating a self-resizing app.
    var resistUntilAttempt: Int = 0
    /// Frame the application insists on while it is still resisting.
    var preferredFrame: WindowFrame
    /// When `true`, the window is gone and cannot be read any more.
    var isVanished = false
    /// When `true`, writing fails outright, as a Java toolkit would.
    var rejectsWrites = false

    init(frame: WindowFrame) {
        self.frame = frame
        self.preferredFrame = frame
        self.snapshot = WindowSnapshot(
            bundleIdentifier: "com.microsoft.Outlook",
            processIdentifier: 4242,
            title: "yesterbox • torstenmahr@microsoft.com",
            role: "AXWindow",
            subrole: "AXStandardWindow",
            frame: frame,
            isFirstWindowAfterLaunch: true,
            observedAt: Date()
        )
    }

    func readFrame() -> WindowFrame? {
        isVanished ? nil : frame
    }

    @discardableResult
    func write(frame: WindowFrame) -> Bool {
        guard !rejectsWrites else { return false }
        writes.append(frame)
        // The application "wins" for as long as it is configured to resist.
        self.frame = writes.count < resistUntilAttempt ? preferredFrame : frame
        return true
    }
}

@Suite("Platzierung mit Wiederholung")
struct RetryingWindowPlacerTests {

    static let target = ResolvedPlacement(
        frame: WindowFrame(x: 0, y: 65, width: 1706, height: 1344),
        display: DisplayAlias(rawValue: "ultrawide"),
        zone: ZoneID(rawValue: "left"),
        usedFallback: false
    )

    /// A placer that never actually sleeps, so the retry policy can be exercised
    /// in microseconds instead of seconds.
    @MainActor
    private func placer(record: @escaping (PlacementAttempt) -> Void = { _ in }) -> RetryingWindowPlacer {
        RetryingWindowPlacer(wait: { _ in }, record: record)
    }

    @Test("Ein kooperatives Fenster sitzt nach einem Versuch")
    @MainActor
    func cooperativeWindowTakesOneAttempt() async {
        let window = FakeWindow(frame: WindowFrame(x: 500, y: 500, width: 800, height: 600))
        let outcome = await placer().place(window, at: Self.target, retry: RetryPolicy())

        #expect(outcome == .placed(attempts: 1))
        #expect(window.readFrame() == Self.target.frame)
    }

    @Test("Ein Fenster, das sich selbst wieder skaliert, wird erneut gesetzt")
    @MainActor
    func selfResizingWindowNeedsMoreAttempts() async {
        let window = FakeWindow(frame: WindowFrame(x: 500, y: 500, width: 800, height: 600))
        // Imitates Outlook: the first two writes are undone by the app itself.
        window.resistUntilAttempt = 3

        var attempts: [PlacementAttempt] = []
        let outcome = await placer { attempts.append($0) }
            .place(window, at: Self.target, retry: RetryPolicy(attempts: 3, tolerance: 2))

        #expect(outcome == .placed(attempts: 3))
        #expect(attempts.count == 3)
        #expect(attempts[0].accepted == false)
        #expect(attempts[1].accepted == false)
        #expect(attempts[2].accepted)
    }

    @Test("Reichen die Versuche nicht, wird die App als Ursache benannt")
    @MainActor
    func stubbornWindowIsReportedAsRejecting() async {
        let window = FakeWindow(frame: WindowFrame(x: 500, y: 500, width: 800, height: 600))
        window.resistUntilAttempt = .max

        let outcome = await placer().place(
            window,
            at: Self.target,
            retry: RetryPolicy(attempts: 3, tolerance: 2)
        )

        #expect(outcome == .rejectedByApplication(actual: window.preferredFrame, attempts: 3))
    }

    @Test("Die Toleranz entscheidet, nicht die exakte Gleichheit")
    @MainActor
    func toleranceDecides() async {
        let window = FakeWindow(frame: WindowFrame(x: 500, y: 500, width: 800, height: 600))
        window.resistUntilAttempt = .max
        // The app clamps the height by three points — within a tolerance of
        // four, that is a success, not a fight.
        window.preferredFrame = WindowFrame(
            x: Self.target.frame.x,
            y: Self.target.frame.y,
            width: Self.target.frame.width,
            height: Self.target.frame.height - 3
        )

        let outcome = await placer().place(
            window,
            at: Self.target,
            retry: RetryPolicy(attempts: 3, tolerance: 4)
        )
        #expect(outcome == .placed(attempts: 1))

        let strict = FakeWindow(frame: window.preferredFrame)
        strict.resistUntilAttempt = .max
        strict.preferredFrame = window.preferredFrame
        let strictOutcome = await placer().place(
            strict,
            at: Self.target,
            retry: RetryPolicy(attempts: 2, tolerance: 1)
        )
        #expect(strictOutcome == .rejectedByApplication(actual: strict.preferredFrame, attempts: 2))
    }

    @Test("Ein verschwundenes Fenster beendet die Schleife sofort")
    @MainActor
    func vanishedWindowStopsImmediately() async {
        let window = FakeWindow(frame: WindowFrame(x: 0, y: 0, width: 800, height: 600))
        window.isVanished = true

        var attempts: [PlacementAttempt] = []
        let outcome = await placer { attempts.append($0) }
            .place(window, at: Self.target, retry: RetryPolicy(attempts: 5))

        #expect(attempts.count == 1)
        if case let .rejectedByApplication(_, count) = outcome {
            #expect(count == 1)
        } else {
            Issue.record("Erwartet wurde ein Abbruch nach dem ersten Versuch, war: \(outcome)")
        }
    }

    @Test("Jeder Versuch wird mit Soll, Ist und Abweichung protokolliert")
    @MainActor
    func everyAttemptIsRecorded() async {
        let window = FakeWindow(frame: WindowFrame(x: 500, y: 500, width: 800, height: 600))
        window.resistUntilAttempt = 2

        var attempts: [PlacementAttempt] = []
        _ = await placer { attempts.append($0) }
            .place(window, at: Self.target, retry: RetryPolicy(attempts: 3, tolerance: 2))

        // These four values are the evidence the tracer bullet is supposed to
        // produce; without them the retry policy cannot be judged.
        #expect(attempts.first?.number == 1)
        #expect(attempts.first?.requested == Self.target.frame)
        #expect(attempts.first?.actual != nil)
        #expect(attempts.first?.deviation != nil)
    }

    @Test("Mindestens ein Versuch findet auch bei attempts = 0 statt")
    @MainActor
    func zeroAttemptsStillTriesOnce() async {
        let window = FakeWindow(frame: WindowFrame(x: 0, y: 0, width: 800, height: 600))
        let outcome = await placer().place(window, at: Self.target, retry: RetryPolicy(attempts: 0))

        #expect(outcome == .placed(attempts: 1))
    }
}
