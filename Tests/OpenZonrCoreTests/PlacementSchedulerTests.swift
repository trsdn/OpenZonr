import Foundation
import Testing
@testable import OpenZonrCore

@MainActor
private final class Outcomes {
    var values: [PlacementOutcome] = []
}

@Suite("Platzierungs-Scheduler")
@MainActor
struct PlacementSchedulerTests {

    private let target = ResolvedPlacement(
        frame: WindowFrame(x: 0, y: 65, width: 1706, height: 1344),
        display: "ultrawide",
        zone: "left",
        usedFallback: false
    )
    private let start = WindowFrame(x: 500, y: 500, width: 800, height: 600)

    private func submit(
        _ scheduler: PlacementScheduler,
        _ id: WindowIdentifier,
        _ window: FakeWindow,
        retry: RetryPolicy,
        outcomes: Outcomes,
        wait: @escaping @Sendable (Duration) async -> Void
    ) {
        let target = self.target
        scheduler.submit(id) { isCurrent in
            let placer = RetryingWindowPlacer(wait: wait)
            outcomes.values.append(await placer.place(window, at: target, retry: retry, isCurrent: isCurrent))
        }
    }

    @Test("hasPendingJob: wahr solange die Anfrage laeuft, sonst falsch")
    func pendingJobQuery() async {
        let scheduler = PlacementScheduler()
        let a = TestConfigurations.identifier("a")
        let b = TestConfigurations.identifier("b")
        let window = FakeWindow(frame: start)
        let outcomes = Outcomes()

        submit(scheduler, a, window,
               retry: RetryPolicy(attempts: 3, initialDelay: 0.5, interval: 0.2, tolerance: 2),
               outcomes: outcomes,
               wait: { _ in await Task.yield() })

        #expect(scheduler.hasPendingJob(for: a))
        #expect(!scheduler.hasPendingJob(for: b))

        await scheduler.idle()
        #expect(!scheduler.hasPendingJob(for: a))

        submit(scheduler, a, window,
               retry: RetryPolicy(attempts: 3, initialDelay: 0.5, interval: 0.2, tolerance: 2),
               outcomes: outcomes,
               wait: { _ in await Task.yield() })
        #expect(scheduler.hasPendingJob(for: a))
        scheduler.cancel(a)
        #expect(!scheduler.hasPendingJob(for: a))
        await scheduler.idle()
    }

    @Test("Ein cancelAll waehrend der Anfangsverzoegerung verhindert jeden Schreibzugriff")
    func stopDuringInitialDelay() async {
        let scheduler = PlacementScheduler()
        let window = FakeWindow(frame: start)
        let outcomes = Outcomes()

        submit(scheduler, TestConfigurations.identifier("a"), window,
               retry: RetryPolicy(attempts: 3, initialDelay: 0.5, interval: 0.2, tolerance: 2),
               outcomes: outcomes,
               wait: { _ in await scheduler.cancelAll() })
        await scheduler.idle()

        #expect(window.writes.isEmpty)
        #expect(outcomes.values == [.cancelled(attempts: 0)])
        #expect(scheduler.pendingCount == 0)
    }

    @Test("Ein cancelAll zwischen zwei Versuchen beendet die Wiederholungen")
    func stopBetweenRetries() async {
        let scheduler = PlacementScheduler()
        let window = FakeWindow(frame: start)
        window.resistUntilAttempt = .max
        let outcomes = Outcomes()

        submit(scheduler, TestConfigurations.identifier("a"), window,
               retry: RetryPolicy(attempts: 5, initialDelay: 0, interval: 0.2, tolerance: 2),
               outcomes: outcomes,
               wait: { _ in await scheduler.cancelAll() })
        await scheduler.idle()

        #expect(window.writes.count == 1)
        #expect(outcomes.values == [.cancelled(attempts: 1)])
    }

    @Test("Eine neuere Anfrage ersetzt die aeltere fuer dasselbe Fenster")
    func newerRequestSupersedesOlder() async {
        let scheduler = PlacementScheduler()
        let id = TestConfigurations.identifier("a")
        let older = FakeWindow(frame: start)
        let newer = FakeWindow(frame: start)
        let outcomes = Outcomes()
        let retry = RetryPolicy(attempts: 2, initialDelay: 0.1, interval: 0.1, tolerance: 2)

        // Waehrend die aeltere Anfrage wartet, trifft die neuere ein.
        submit(scheduler, id, older, retry: retry, outcomes: outcomes, wait: { _ in
            await MainActor.run {
                self.submit(scheduler, id, newer, retry: retry, outcomes: outcomes, wait: { _ in })
            }
        })
        await scheduler.idle()

        #expect(older.writes.isEmpty)
        #expect(newer.writes.count == 1)
        #expect(outcomes.values.contains(.placed(attempts: 1)))
        #expect(outcomes.values.contains(.cancelled(attempts: 0)))
    }

    @Test("Ein Abbruch fuer ein Fenster laesst andere Fenster unberuehrt")
    func cancellingOneWindowLeavesOthersAlone() async {
        let scheduler = PlacementScheduler()
        let first = TestConfigurations.identifier("a")
        let second = TestConfigurations.identifier("b")
        let firstWindow = FakeWindow(frame: start)
        let secondWindow = FakeWindow(frame: start)
        let outcomes = Outcomes()
        let retry = RetryPolicy(attempts: 2, initialDelay: 0.1, interval: 0.1, tolerance: 2)

        submit(scheduler, first, firstWindow, retry: retry, outcomes: outcomes,
               wait: { _ in await scheduler.cancel(first) })
        submit(scheduler, second, secondWindow, retry: retry, outcomes: outcomes, wait: { _ in })
        await scheduler.idle()

        #expect(firstWindow.writes.isEmpty)
        #expect(secondWindow.writes.count == 1)
    }

    @Test("cancel(where:) trifft nur die passenden Fenster, etwa die eines beendeten Programms")
    func cancelByPredicate() async {
        let scheduler = PlacementScheduler()
        let dying = TestConfigurations.identifier("a", processIdentifier: 7)
        let living = TestConfigurations.identifier("b", processIdentifier: 8)
        let dyingWindow = FakeWindow(frame: start)
        let livingWindow = FakeWindow(frame: start)
        let outcomes = Outcomes()
        let retry = RetryPolicy(attempts: 1, initialDelay: 0.1, interval: 0.1, tolerance: 2)

        submit(scheduler, dying, dyingWindow, retry: retry, outcomes: outcomes, wait: { _ in })
        submit(scheduler, living, livingWindow, retry: retry, outcomes: outcomes, wait: { _ in })
        scheduler.cancel(where: { $0.processIdentifier == 7 })
        await scheduler.idle()

        #expect(dyingWindow.writes.isEmpty)
        #expect(livingWindow.writes.count == 1)
    }

    @Test("Nach cancelAll erhoeht sich die Generation, neue Arbeit laeuft normal")
    func generationAdvancesAndNewWorkRuns() async {
        let scheduler = PlacementScheduler()
        let generation = scheduler.generation
        scheduler.cancelAll()
        #expect(scheduler.generation == generation + 1)

        let window = FakeWindow(frame: start)
        let outcomes = Outcomes()
        submit(scheduler, TestConfigurations.identifier("a"), window,
               retry: RetryPolicy(attempts: 1, initialDelay: 0, interval: 0, tolerance: 2),
               outcomes: outcomes, wait: { _ in })
        await scheduler.idle()

        #expect(outcomes.values == [.placed(attempts: 1)])
    }
}
