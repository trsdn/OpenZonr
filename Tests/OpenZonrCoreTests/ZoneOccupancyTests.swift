import Foundation
import Testing
@testable import OpenZonrCore

struct ZoneOccupancyTests {

    @Test("Registrieren Abfragen Verschieben und Vergessen funktioniert")
    func registerQueryMoveAndForget() {
        var occupancy = ZoneOccupancy()
        let window = TestConfigurations.identifier("a")
        let first = Self.placement(zone: "left")
        let second = Self.placement(zone: "right")

        occupancy.register(window, at: first)
        #expect(occupancy.occupants(of: "left", on: "main") == [window])
        #expect(occupancy.placement(of: window) == first)

        occupancy.register(window, at: second)
        #expect(occupancy.occupants(of: "left", on: "main").isEmpty)
        #expect(occupancy.occupants(of: "right", on: "main") == [window])
        #expect(occupancy.placement(of: window) == second)

        occupancy.forget(window)
        #expect(occupancy.occupants(of: "right", on: "main").isEmpty)
        #expect(occupancy.placement(of: window) == nil)
    }

    @Test("Stack legt zwei Fenster in dieselbe Zone")
    func stackPlacesTwoWindowsInOneZone() {
        var occupancy = ZoneOccupancy()
        let first = TestConfigurations.identifier("a")
        let second = TestConfigurations.identifier("b")
        let target = Self.placement(zone: "left")
        let policy = ConflictPolicy(occupiedZone: .stack)

        let firstResult = occupancy.apply(first, target: target, policy: policy, fallback: nil, now: Self.now)
        let secondResult = occupancy.apply(second, target: target, policy: policy, fallback: nil, now: Self.now)

        #expect(firstResult == .place)
        #expect(secondResult == .place)
        #expect(occupancy.occupants(of: "left", on: "main") == [first, second])
    }

    @Test("Skip lässt das zweite Fenster unverändert")
    func skipLeavesSecondWindowUnchanged() {
        var occupancy = ZoneOccupancy()
        let first = TestConfigurations.identifier("a")
        let second = TestConfigurations.identifier("b")
        let target = Self.placement(zone: "left")
        let policy = ConflictPolicy(occupiedZone: .skip)

        _ = occupancy.apply(first, target: target, policy: policy, fallback: nil, now: Self.now)
        let before = occupancy.occupants(of: "left", on: "main")
        let result = occupancy.apply(second, target: target, policy: policy, fallback: nil, now: Self.now)

        #expect(result == .skip)
        #expect(occupancy.occupants(of: "left", on: "main") == before)
        #expect(occupancy.placement(of: second) == nil)
    }

    @Test("Replace verschiebt den bisherigen Insassen in den Fallback")
    func replaceDisplacesPreviousOccupantToFallback() {
        var occupancy = ZoneOccupancy()
        let first = TestConfigurations.identifier("a")
        let second = TestConfigurations.identifier("b")
        let target = Self.placement(zone: "left")
        let fallback = Self.placement(zone: "right", x: 960)
        let policy = ConflictPolicy(occupiedZone: .replace)

        _ = occupancy.apply(first, target: target, policy: policy, fallback: fallback, now: Self.now)
        let result = occupancy.apply(second, target: target, policy: policy, fallback: fallback, now: Self.now)

        #expect(result == .placeDisplacing([Displacement(window: first, newPlacement: fallback)]))
        #expect(occupancy.occupants(of: "left", on: "main") == [second])
        #expect(occupancy.occupants(of: "right", on: "main") == [first])
        #expect(occupancy.placement(of: first) == fallback)
        #expect(occupancy.placement(of: second) == target)
    }

    @Test("Replace ohne Fallback stapelt")
    func replaceWithoutFallbackStacks() {
        var occupancy = ZoneOccupancy()
        let first = TestConfigurations.identifier("a")
        let second = TestConfigurations.identifier("b")
        let target = Self.placement(zone: "left")
        let policy = ConflictPolicy(occupiedZone: .replace)

        _ = occupancy.apply(first, target: target, policy: policy, fallback: nil, now: Self.now)
        let result = occupancy.apply(second, target: target, policy: policy, fallback: nil, now: Self.now)

        #expect(result == .place)
        #expect(occupancy.occupants(of: "left", on: "main") == [first, second])
    }

    @Test("Replace verdrängt manuell übersteuerte Insassen nicht")
    func replaceDoesNotDisplaceManualOverride() {
        var occupancy = ZoneOccupancy()
        let first = TestConfigurations.identifier("a")
        let second = TestConfigurations.identifier("b")
        let target = Self.placement(zone: "left")
        let fallback = Self.placement(zone: "right", x: 960)
        let policy = ConflictPolicy(occupiedZone: .replace, honorManualOverride: true)

        occupancy.register(first, at: target)
        occupancy.markManuallyOverridden(first, at: Self.now)
        let result = occupancy.apply(second, target: target, policy: policy, fallback: fallback, now: Self.now)

        #expect(result == .place)
        #expect(occupancy.occupants(of: "left", on: "main") == [first, second])
        #expect(occupancy.occupants(of: "right", on: "main").isEmpty)
        #expect(occupancy.placement(of: first) == target)
    }

    @Test("Manuelle Übersteuerung beachtet Richtlinie und Ablaufgrenze")
    func manualOverrideHonorsPolicyAndExpirationBoundary() {
        var occupancy = ZoneOccupancy()
        let window = TestConfigurations.identifier("a")
        let start = Self.now
        occupancy.markManuallyOverridden(window, at: start)

        #expect(occupancy.isManuallyOverridden(
            window,
            now: start.addingTimeInterval(10_000),
            policy: ConflictPolicy(honorManualOverride: true, manualOverrideTimeout: nil)
        ))
        #expect(!occupancy.isManuallyOverridden(
            window,
            now: start,
            policy: ConflictPolicy(honorManualOverride: false, manualOverrideTimeout: nil)
        ))
        #expect(occupancy.isManuallyOverridden(
            window,
            now: start.addingTimeInterval(60),
            policy: ConflictPolicy(honorManualOverride: true, manualOverrideTimeout: 60)
        ))
        #expect(!occupancy.isManuallyOverridden(
            window,
            now: start.addingTimeInterval(60.001),
            policy: ConflictPolicy(honorManualOverride: true, manualOverrideTimeout: 60)
        ))
    }

    @Test("Abgelaufene Übersteuerungen werden bereinigt")
    func pruneExpiredOverridesRemovesOnlyExpiredEntries() {
        var occupancy = ZoneOccupancy()
        let expired = TestConfigurations.identifier("a")
        let live = TestConfigurations.identifier("b")
        let policy = ConflictPolicy(honorManualOverride: true, manualOverrideTimeout: 60)

        occupancy.markManuallyOverridden(expired, at: Self.now)
        occupancy.markManuallyOverridden(live, at: Self.now.addingTimeInterval(30))
        occupancy.pruneExpiredOverrides(now: Self.now.addingTimeInterval(60.001), policy: policy)

        // Geprüft wird der gespeicherte Zustand, nicht seine Auslegung durch die
        // Richtlinie: `isManuallyOverridden` wendet die Frist ohnehin an und
        // antwortete auch dann richtig, wenn gar nichts bereinigt worden wäre.
        // Der eigentliche Zweck der Methode — die Tabelle wächst nicht ewig —
        // lässt sich nur an der Tabelle selbst ablesen.
        #expect(occupancy.manualOverrideDate(of: expired) == nil)
        #expect(occupancy.manualOverrideDate(of: live) == Self.now.addingTimeInterval(30))
        #expect(occupancy.manualOverrideCount == 1)
    }

    @Test("Ohne Ablaufgrenze wird nichts bereinigt")
    func pruneKeepsEverythingWithoutATimeout() {
        var occupancy = ZoneOccupancy()
        let window = TestConfigurations.identifier("a")
        let policy = ConflictPolicy(honorManualOverride: true, manualOverrideTimeout: nil)

        occupancy.markManuallyOverridden(window, at: Self.now)
        occupancy.pruneExpiredOverrides(now: Self.now.addingTimeInterval(86_400), policy: policy)

        // Eine Übersteuerung ohne Frist gilt, solange das Fenster existiert.
        #expect(occupancy.manualOverrideDate(of: window) == Self.now)
    }

    @Test("Ist die Übersteuerung abgeschaltet, bereinigt das Aufräumen nichts")
    func pruneKeepsEverythingWhenOverridesAreIgnored() {
        var occupancy = ZoneOccupancy()
        let window = TestConfigurations.identifier("a")
        let policy = ConflictPolicy(honorManualOverride: false, manualOverrideTimeout: 60)

        occupancy.markManuallyOverridden(window, at: Self.now)
        occupancy.pruneExpiredOverrides(now: Self.now.addingTimeInterval(600), policy: policy)

        // Der Eintrag bleibt erhalten: die Richtlinie kann sich ändern, und dann
        // wäre eine im Vorbeigehen gelöschte Übersteuerung nicht mehr zu retten.
        #expect(occupancy.manualOverrideDate(of: window) == Self.now)
    }

    @Test("Ein vergessenes Fenster verliert auch seine Übersteuerung")
    func forgettingAWindowClearsItsOverride() {
        var occupancy = ZoneOccupancy()
        let window = TestConfigurations.identifier("a")

        occupancy.markManuallyOverridden(window, at: Self.now)
        occupancy.forget(window)

        #expect(occupancy.manualOverrideDate(of: window) == nil)
        #expect(occupancy.manualOverrideCount == 0)
    }

    private static let now = Date(timeIntervalSince1970: 1_700_000_000)

    private static func placement(
        display: DisplayAlias = "main",
        zone: ZoneID,
        x: Double = 0,
        y: Double = 0,
        width: Double = 960,
        height: Double = 1080,
        usedFallback: Bool = false
    ) -> ResolvedPlacement {
        ResolvedPlacement(
            frame: WindowFrame(x: x, y: y, width: width, height: height),
            display: display,
            zone: zone,
            usedFallback: usedFallback
        )
    }
}
