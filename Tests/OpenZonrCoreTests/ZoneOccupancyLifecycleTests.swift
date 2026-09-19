import Foundation
import Testing
@testable import OpenZonrCore

struct ZoneOccupancyLifecycleTests {

    private static let now = Date(timeIntervalSince1970: 1_700_000_000)
    private static let replace = ConflictPolicy(occupiedZone: .replace)
    private static let skip = ConflictPolicy(occupiedZone: .skip)

    private static func placement(zone: ZoneID) -> ResolvedPlacement {
        ResolvedPlacement(
            frame: WindowFrame(x: 0, y: 0, width: 960, height: 1080),
            display: "main",
            zone: zone,
            usedFallback: false
        )
    }

    private static let left = placement(zone: "left")
    private static let right = placement(zone: "right")

    @Test("Ein fehlgeschlagener Claim gibt die Zone wieder frei")
    func rollbackFreesTheZone() {
        var occupancy = ZoneOccupancy()
        let a = TestConfigurations.identifier("a")
        let before = occupancy

        _ = occupancy.apply(a, target: Self.left, policy: Self.skip, fallback: nil, now: Self.now)
        let claims = occupancy.claims(for: [a], since: before)
        occupancy.rollback(claims)

        #expect(occupancy.occupants(of: "left", on: "main").isEmpty)
        #expect(occupancy.placement(of: a) == nil)
    }

    @Test("Rollback stellt die vorherige Zone eines verschobenen Fensters wieder her")
    func rollbackRestoresPreviousZone() {
        var occupancy = ZoneOccupancy()
        let a = TestConfigurations.identifier("a")
        occupancy.register(a, at: Self.right)
        let before = occupancy

        _ = occupancy.apply(a, target: Self.left, policy: Self.skip, fallback: nil, now: Self.now)
        occupancy.rollback(occupancy.claims(for: [a], since: before))

        #expect(occupancy.occupants(of: "right", on: "main") == [a])
        #expect(occupancy.occupants(of: "left", on: "main").isEmpty)
    }

    @Test("Rollback macht eine Verdraengung rueckgaengig")
    func rollbackUndoesDisplacement() {
        var occupancy = ZoneOccupancy()
        let a = TestConfigurations.identifier("a")
        let b = TestConfigurations.identifier("b")
        occupancy.register(a, at: Self.left)
        let before = occupancy

        _ = occupancy.apply(b, target: Self.left, policy: Self.replace, fallback: Self.right, now: Self.now)
        #expect(occupancy.occupants(of: "right", on: "main") == [a])

        occupancy.rollback(occupancy.claims(for: [b, a], since: before))

        #expect(occupancy.occupants(of: "left", on: "main") == [a])
        #expect(occupancy.occupants(of: "right", on: "main").isEmpty)
        #expect(occupancy.placement(of: b) == nil)
    }

    @Test("Ein veralteter Claim ueberschreibt keinen neueren Claim desselben Fensters")
    func staleClaimDoesNotUndoNewerClaim() {
        var occupancy = ZoneOccupancy()
        let a = TestConfigurations.identifier("a")

        let beforeOld = occupancy
        _ = occupancy.apply(a, target: Self.left, policy: Self.skip, fallback: nil, now: Self.now)
        let oldClaims = occupancy.claims(for: [a], since: beforeOld)

        // Eine neuere Anfrage fuer dasselbe Fenster zieht es in die rechte Zone.
        _ = occupancy.apply(a, target: Self.right, policy: Self.skip, fallback: nil, now: Self.now)

        occupancy.rollback(oldClaims)

        #expect(occupancy.occupants(of: "right", on: "main") == [a])
    }

    @Test("Ein beendetes Programm gibt alle seine Zonen und Uebersteuerungen frei")
    func forgetApplicationRemovesItsWindows() {
        var occupancy = ZoneOccupancy()
        let mine1 = TestConfigurations.identifier("a", processIdentifier: 7)
        let mine2 = TestConfigurations.identifier("b", processIdentifier: 7)
        let other = TestConfigurations.identifier("c", processIdentifier: 8)
        occupancy.register(mine1, at: Self.left)
        occupancy.register(mine2, at: Self.right)
        occupancy.register(other, at: Self.right)
        occupancy.markManuallyOverridden(mine2, at: Self.now)

        occupancy.forgetApplication(processIdentifier: 7)

        #expect(occupancy.occupants(of: "left", on: "main").isEmpty)
        #expect(occupancy.occupants(of: "right", on: "main") == [other])
        #expect(occupancy.manualOverrideCount == 0)
        #expect(occupancy.trackedWindows == [other])
    }

    @Test("Reconcile entfernt geschlossene und weggezogene Fenster, behaelt anwesende")
    func reconcileDropsGoneAndMovedAway() {
        var occupancy = ZoneOccupancy()
        let present = TestConfigurations.identifier("present")
        let moved = TestConfigurations.identifier("moved")
        let gone = TestConfigurations.identifier("gone")
        for window in [present, moved, gone] { occupancy.register(window, at: Self.left) }
        occupancy.markManuallyOverridden(moved, at: Self.now)

        occupancy.reconcile { window, _ in
            switch window {
            case moved: return .movedAway
            case gone: return .gone
            default: return .present
            }
        }

        #expect(occupancy.occupants(of: "left", on: "main") == [present])
        // Weggezogen: nur die Zone wird frei, die Uebersteuerung bleibt erhalten.
        #expect(occupancy.manualOverrideDate(of: moved) == Self.now)
        #expect(occupancy.placement(of: moved) == nil)
        // Geschlossen: alles vergessen.
        #expect(occupancy.manualOverrideDate(of: gone) == nil)
    }

    @Test("Verlaesst der Bewohner die Zone vor dem naechsten Fenster, wird niemand verdraengt")
    func exitedOccupantIsNotDisplaced() {
        var occupancy = ZoneOccupancy()
        let a = TestConfigurations.identifier("a")
        let b = TestConfigurations.identifier("b")
        occupancy.register(a, at: Self.left)

        occupancy.reconcile { _, _ in .gone }
        let result = occupancy.apply(b, target: Self.left, policy: Self.replace, fallback: Self.right, now: Self.now)

        #expect(result == .place)
        #expect(occupancy.occupants(of: "left", on: "main") == [b])
    }

    @Test("Nach fehlgeschlagener Platzierung blockiert die skip-Policy die Zone nicht")
    func failedPlacementDoesNotBlockSkipPolicy() {
        var configuration = TestConfigurations.minimal()
        configuration.defaults.conflict.occupiedZone = .skip
        let decider = PlacementDecider()
        var occupancy = ZoneOccupancy()

        func decide(_ id: WindowIdentifier) -> PlacementDecision {
            decider.decide(
                for: TestConfigurations.window(),
                identifier: id,
                configuration: configuration,
                rules: CompiledRuleSet(rules: configuration.rules),
                setup: SetupFingerprint(displays: [.builtin]),
                visibleFrames: ["main": TestConfigurations.mainVisibleFrame],
                occupancy: &occupancy,
                now: Self.now
            )
        }

        let first = TestConfigurations.identifier("w1")
        let before = occupancy
        guard case .place = decide(first) else {
            Issue.record("Das erste Fenster haette platziert werden muessen")
            return
        }
        // Die App hat den Frame nicht uebernommen: Claim zuruecknehmen.
        occupancy.rollback(occupancy.claims(for: [first], since: before))

        guard case .place = decide(TestConfigurations.identifier("w2")) else {
            Issue.record("Die Zone ist nach dem Rollback frei und muss dem zweiten Fenster gehoeren")
            return
        }
    }
}
