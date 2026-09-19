import Foundation
import Testing
@testable import OpenZonrCore

@Suite("Platzierungsauftrag mit Verdraengung")
@MainActor
struct PlacementJobTests {

    private static let now = Date(timeIntervalSince1970: 1_700_000_000)
    private static let retry = RetryPolicy(attempts: 2, initialDelay: 0, interval: 0, tolerance: 2)

    private static func placement(zone: ZoneID, x: Double) -> ResolvedPlacement {
        ResolvedPlacement(
            frame: WindowFrame(x: x, y: 0, width: 960, height: 1080),
            display: "main",
            zone: zone,
            usedFallback: false
        )
    }

    private static let left = placement(zone: "left", x: 0)
    private static let right = placement(zone: "right", x: 960)

    @MainActor
    private struct Scenario {
        var occupancy = ZoneOccupancy()
        let occupant = TestConfigurations.identifier("occupant")
        let newcomer = TestConfigurations.identifier("newcomer")
        var claims: [OccupancyClaim] = []
        var displacements: [Displacement] = []

        /// Occupant sits in "left"; the newcomer targets "left" under `replace`.
        init() {
            occupancy.register(occupant, at: PlacementJobTests.left)
            let before = occupancy
            let resolution = occupancy.apply(
                newcomer,
                target: PlacementJobTests.left,
                policy: ConflictPolicy(occupiedZone: .replace),
                fallback: PlacementJobTests.right,
                now: PlacementJobTests.now
            )
            if case let .placeDisplacing(list) = resolution { displacements = list }
            claims = occupancy.claims(for: [newcomer, occupant], since: before)
        }
    }

    private func job(windows: [WindowIdentifier: FakeWindow]) -> PlacementJob {
        PlacementJob(
            placer: RetryingWindowPlacer(wait: { _ in }),
            windowFor: { windows[$0] }
        )
    }

    @Test("Der verdraengte Bewohner wird tatsaechlich in die Fallback-Zone bewegt")
    func occupantIsMovedToFallback() async {
        var scenario = Scenario()
        let occupantWindow = FakeWindow(frame: Self.left.frame)
        let newcomerWindow = FakeWindow(frame: WindowFrame(x: 300, y: 300, width: 500, height: 400))

        let result = await job(windows: [scenario.occupant: occupantWindow]).run(
            window: newcomerWindow,
            at: Self.left,
            displacing: scenario.displacements,
            retry: Self.retry,
            isCurrent: { true }
        )
        scenario.occupancy.settle(result, claims: scenario.claims, window: scenario.newcomer)

        #expect(occupantWindow.readFrame() == Self.right.frame)
        #expect(newcomerWindow.readFrame() == Self.left.frame)
        #expect(result.displaced == [DisplacementReport(window: scenario.occupant, outcome: .moved(attempts: 1))])
        #expect(result.outcome == .placed(attempts: 1))
        #expect(scenario.occupancy.occupants(of: "left", on: "main") == [scenario.newcomer])
        #expect(scenario.occupancy.occupants(of: "right", on: "main") == [scenario.occupant])
    }

    @Test("Laesst sich der Bewohner nicht bewegen, bleibt sein Anspruch auf die Zone bestehen")
    func unmovableOccupantKeepsItsClaim() async {
        var scenario = Scenario()
        let occupantWindow = FakeWindow(frame: Self.left.frame)
        occupantWindow.resistUntilAttempt = .max
        occupantWindow.preferredFrame = Self.left.frame
        let newcomerWindow = FakeWindow(frame: WindowFrame(x: 300, y: 300, width: 500, height: 400))

        let result = await job(windows: [scenario.occupant: occupantWindow]).run(
            window: newcomerWindow,
            at: Self.left,
            displacing: scenario.displacements,
            retry: Self.retry,
            isCurrent: { true }
        )
        scenario.occupancy.settle(result, claims: scenario.claims, window: scenario.newcomer)

        guard case .failed = result.displaced.first?.outcome else {
            Issue.record("Erwartet: failed, geliefert: \(String(describing: result.displaced.first?.outcome))")
            return
        }
        // Das neue Fenster wird trotzdem gesetzt; beide Fenster stapeln sich ehrlich.
        #expect(result.outcome == .placed(attempts: 1))
        #expect(scenario.occupancy.occupants(of: "right", on: "main").isEmpty)
        #expect(Set(scenario.occupancy.occupants(of: "left", on: "main")) == [scenario.occupant, scenario.newcomer])
    }

    @Test("Ein verschwundener Bewohner wird vergessen, das neue Fenster trotzdem platziert")
    func vanishedOccupantIsForgotten() async {
        var scenario = Scenario()
        let occupantWindow = FakeWindow(frame: Self.left.frame)
        occupantWindow.isVanished = true
        let newcomerWindow = FakeWindow(frame: WindowFrame(x: 300, y: 300, width: 500, height: 400))

        let result = await job(windows: [scenario.occupant: occupantWindow]).run(
            window: newcomerWindow,
            at: Self.left,
            displacing: scenario.displacements,
            retry: Self.retry,
            isCurrent: { true }
        )
        scenario.occupancy.settle(result, claims: scenario.claims, window: scenario.newcomer)

        #expect(result.displaced.first?.outcome == .windowGone)
        #expect(scenario.occupancy.placement(of: scenario.occupant) == nil)
        #expect(scenario.occupancy.occupants(of: "left", on: "main") == [scenario.newcomer])
    }

    @Test("Ein nicht auffindbarer Bewohner (kein Fenster registriert) gilt als verschwunden")
    func unknownOccupantCountsAsGone() async {
        var scenario = Scenario()
        let newcomerWindow = FakeWindow(frame: WindowFrame(x: 300, y: 300, width: 500, height: 400))

        let result = await job(windows: [:]).run(
            window: newcomerWindow,
            at: Self.left,
            displacing: scenario.displacements,
            retry: Self.retry,
            isCurrent: { true }
        )
        scenario.occupancy.settle(result, claims: scenario.claims, window: scenario.newcomer)

        #expect(result.displaced.first?.outcome == .windowGone)
        #expect(result.outcome == .placed(attempts: 1))
        #expect(scenario.occupancy.placement(of: scenario.occupant) == nil)
        #expect(scenario.occupancy.occupants(of: "left", on: "main") == [scenario.newcomer])
    }

    @Test("Ein abgebrochener Auftrag schreibt nichts und nimmt alle Anspruecke zurueck")
    func cancelledJobWritesNothingAndRollsBack() async {
        var scenario = Scenario()
        let occupantWindow = FakeWindow(frame: Self.left.frame)
        let newcomerWindow = FakeWindow(frame: WindowFrame(x: 300, y: 300, width: 500, height: 400))

        let result = await job(windows: [scenario.occupant: occupantWindow]).run(
            window: newcomerWindow,
            at: Self.left,
            displacing: scenario.displacements,
            retry: Self.retry,
            isCurrent: { false }
        )
        scenario.occupancy.settle(result, claims: scenario.claims, window: scenario.newcomer)

        #expect(occupantWindow.writes.isEmpty)
        #expect(newcomerWindow.writes.isEmpty)
        #expect(result.outcome == .cancelled(attempts: 0))
        #expect(scenario.occupancy.occupants(of: "left", on: "main") == [scenario.occupant])
        #expect(scenario.occupancy.occupants(of: "right", on: "main").isEmpty)
        #expect(scenario.occupancy.placement(of: scenario.newcomer) == nil)
    }

    @Test("Lehnt die App das neue Fenster ab, wird dessen Anspruch zurueckgenommen")
    func rejectedNewcomerReleasesItsClaim() async {
        var scenario = Scenario()
        let occupantWindow = FakeWindow(frame: Self.left.frame)
        let newcomerWindow = FakeWindow(frame: WindowFrame(x: 300, y: 300, width: 500, height: 400))
        newcomerWindow.resistUntilAttempt = .max

        let result = await job(windows: [scenario.occupant: occupantWindow]).run(
            window: newcomerWindow,
            at: Self.left,
            displacing: scenario.displacements,
            retry: Self.retry,
            isCurrent: { true }
        )
        scenario.occupancy.settle(result, claims: scenario.claims, window: scenario.newcomer)

        guard case .rejectedByApplication = result.outcome else {
            Issue.record("Erwartet: rejectedByApplication, geliefert: \(result.outcome)")
            return
        }
        #expect(scenario.occupancy.placement(of: scenario.newcomer) == nil)
        // Der Bewohner wurde bereits erfolgreich verschoben und bleibt dort.
        #expect(scenario.occupancy.occupants(of: "right", on: "main") == [scenario.occupant])
    }

    @Test("Eine neuere Anfrage fuer den verschwundenen Bewohner bleibt beim Abschluss erhalten")
    func newerClaimSurvivesForgetOfVanishedOccupant() async {
        var scenario = Scenario()
        let occupantWindow = FakeWindow(frame: Self.left.frame)
        occupantWindow.isVanished = true
        let newcomerWindow = FakeWindow(frame: WindowFrame(x: 300, y: 300, width: 500, height: 400))

        let result = await job(windows: [scenario.occupant: occupantWindow]).run(
            window: newcomerWindow,
            at: Self.left,
            displacing: scenario.displacements,
            retry: Self.retry,
            isCurrent: { true }
        )
        // Waehrend des Auftrags belegt eine neuere Anfrage den Bewohner erneut.
        scenario.occupancy.register(scenario.occupant, at: Self.right)
        scenario.occupancy.settle(result, claims: scenario.claims, window: scenario.newcomer)

        #expect(result.displaced.first?.outcome == .windowGone)
        #expect(scenario.occupancy.placement(of: scenario.occupant) == Self.right)
    }

    @Test("Abbruch nach dem Verschieben: Bewohner bleibt in der Fallback-Zone, neues Fenster unberuehrt")
    func cancellationBetweenDisplacementAndIncomingPlacement() async {
        var scenario = Scenario()
        let occupantWindow = FakeWindow(frame: Self.left.frame)
        let newcomerWindow = FakeWindow(frame: WindowFrame(x: 300, y: 300, width: 500, height: 400))

        let result = await job(windows: [scenario.occupant: occupantWindow]).run(
            window: newcomerWindow,
            at: Self.left,
            displacing: scenario.displacements,
            retry: Self.retry,
            isCurrent: { occupantWindow.writes.isEmpty }
        )
        scenario.occupancy.settle(result, claims: scenario.claims, window: scenario.newcomer)

        #expect(result.displaced == [DisplacementReport(window: scenario.occupant, outcome: .moved(attempts: 1))])
        #expect(result.outcome == .cancelled(attempts: 0))
        #expect(newcomerWindow.writes.isEmpty)
        #expect(scenario.occupancy.occupants(of: "right", on: "main") == [scenario.occupant])
        #expect(scenario.occupancy.placement(of: scenario.newcomer) == nil)
    }

    @Test("Ein durch eine neuere Anfrage ersetzter Anspruch wird nicht zurueckgenommen")
    func staleClaimIsNotRolledBack() async {
        var scenario = Scenario()
        let occupantWindow = FakeWindow(frame: Self.left.frame)
        let newcomerWindow = FakeWindow(frame: WindowFrame(x: 300, y: 300, width: 500, height: 400))

        let result = await job(windows: [scenario.occupant: occupantWindow]).run(
            window: newcomerWindow,
            at: Self.left,
            displacing: scenario.displacements,
            retry: Self.retry,
            isCurrent: { false }
        )
        scenario.occupancy.register(scenario.newcomer, at: Self.right)
        scenario.occupancy.settle(result, claims: scenario.claims, window: scenario.newcomer)

        #expect(scenario.occupancy.placement(of: scenario.newcomer) == Self.right)
    }
}
