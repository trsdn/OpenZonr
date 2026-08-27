import Foundation
import Testing
@testable import OpenZonrCore

/// End-to-end tests of the pure pipeline: a window snapshot goes in, a decision
/// comes out. Every step in between is covered by its own suite, so these tests
/// deliberately check the *seams* — that a rejection early on stops the chain,
/// that state is only mutated when a placement really happens, and that the
/// occupancy is carried along correctly.
struct PlacementDeciderTests {

    private let decider = PlacementDecider()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func decide(
        _ window: WindowSnapshot,
        identifier: WindowIdentifier = TestConfigurations.identifier("w1"),
        configuration: Configuration = TestConfigurations.minimal(),
        setup: SetupFingerprint? = nil,
        visibleFrames: VisibleFrames? = nil,
        occupancy: inout ZoneOccupancy,
        now: Date? = nil
    ) -> PlacementDecision {
        decider.decide(
            for: window,
            identifier: identifier,
            configuration: configuration,
            rules: CompiledRuleSet(rules: configuration.rules),
            setup: setup ?? SetupFingerprint(displays: [.builtin]),
            visibleFrames: visibleFrames ?? ["main": TestConfigurations.mainVisibleFrame],
            occupancy: &occupancy,
            now: now ?? self.now
        )
    }

    @Test("Der Durchstich liefert den Frame der gebundenen Zone")
    func placesMatchingWindow() throws {
        var occupancy = ZoneOccupancy()
        let decision = decide(TestConfigurations.window(), occupancy: &occupancy)

        let placement = try #require(decision.placement)
        #expect(decision.rule?.id == "editor-rule")
        #expect(placement.display == "main")
        #expect(placement.zone == "left")
        #expect(placement.usedFallback == false)
        // Linke Hälfte von 1920×985 ab y = 70.
        #expect(placement.frame == WindowFrame(x: 0, y: 70, width: 960, height: 985))
        // Die Entscheidung wird auch gebucht, nicht nur berechnet.
        #expect(occupancy.placement(of: TestConfigurations.identifier("w1")) == placement)
    }

    @Test("Ein herausgefiltertes Fenster erreicht die Regelauswertung nicht")
    func filteredWindowIsNotPlaced() {
        var occupancy = ZoneOccupancy()
        let decision = decide(TestConfigurations.window(subrole: "AXDialog"), occupancy: &occupancy)

        #expect(decision == .skip(.notApplicable, reason: .filtered(.disallowedSubrole("AXDialog"))))
        #expect(occupancy.placement(of: TestConfigurations.identifier("w1")) == nil)
    }

    @Test("Ohne passende Regel passiert nichts")
    func unmatchedWindowIsNotPlaced() {
        var occupancy = ZoneOccupancy()
        let decision = decide(
            TestConfigurations.window(bundleIdentifier: "com.example.unknown"),
            occupancy: &occupancy
        )
        #expect(decision == .skip(.notApplicable, reason: .noMatchingRule))
    }

    @Test("Ein unbekanntes Setup führt zu keiner Platzierung")
    func unknownSetupYieldsNoPlacement() {
        var occupancy = ZoneOccupancy()
        let unknown = SetupFingerprint(displays: [
            .edid(vendorNumber: 1, modelNumber: 2, serialNumber: 3)
        ])

        let decision = decide(TestConfigurations.window(), setup: unknown, occupancy: &occupancy)

        #expect(decision == .skip(.notApplicable, reason: .unknownSetup(unknown)))
        #expect(decision.placement == nil)
        #expect(occupancy.placement(of: TestConfigurations.identifier("w1")) == nil)
    }

    @Test("Eine unauflösbare Zone meldet einen Konfigurationsfehler statt abzustürzen")
    func unresolvableZoneIsReported() {
        var configuration = TestConfigurations.minimal()
        configuration.profiles[0].roleBindings[0].zone = "gibtsnicht"

        var occupancy = ZoneOccupancy()
        let decision = decide(TestConfigurations.window(), configuration: configuration, occupancy: &occupancy)

        #expect(
            decision
                == .skip(
                    .notApplicable,
                    reason: .unresolvableZone(.unknownZone("gibtsnicht", layout: "halves", display: "main"))
                )
        )
    }

    @Test("Ein manuell verschobenes Fenster wird nicht erneut platziert")
    func manualOverrideStopsPlacement() {
        var occupancy = ZoneOccupancy()
        let window = TestConfigurations.identifier("w1")
        occupancy.markManuallyOverridden(window, at: now)

        let decision = decide(TestConfigurations.window(), occupancy: &occupancy)
        #expect(decision == .skip(.skippedManualOverride, reason: .manuallyOverridden))
    }

    @Test("Nach Ablauf der Übersteuerungsfrist wird wieder platziert")
    func expiredOverrideAllowsPlacement() {
        var configuration = TestConfigurations.minimal()
        configuration.defaults.conflict.manualOverrideTimeout = 60

        var occupancy = ZoneOccupancy()
        occupancy.markManuallyOverridden(TestConfigurations.identifier("w1"), at: now)

        let decision = decide(
            TestConfigurations.window(),
            configuration: configuration,
            occupancy: &occupancy,
            now: now.addingTimeInterval(120)
        )
        #expect(decision.placement != nil)
    }

    @Test("Der Suggest-Modus belegt die Zone nicht")
    func suggestDoesNotClaimTheZone() throws {
        var configuration = TestConfigurations.minimal()
        configuration.rules[0].action.mode = .suggest

        var occupancy = ZoneOccupancy()
        let decision = decide(TestConfigurations.window(), configuration: configuration, occupancy: &occupancy)

        guard case let .suggest(placement, rule) = decision else {
            Issue.record("Erwartet wurde ein Vorschlag, geliefert wurde \(decision)")
            return
        }
        #expect(rule.id == "editor-rule")
        #expect(placement.zone == "left")
        // Ein Vorschlag verschiebt nichts, also darf er auch nichts belegen —
        // sonst verdrängte ein Angebot, das niemand angenommen hat, ein Fenster.
        #expect(occupancy.occupants(of: "left", on: "main").isEmpty)
    }

    @Test("Bei belegter Zone greift die skip-Strategie")
    func skipStrategyLeavesSecondWindowAlone() {
        var configuration = TestConfigurations.minimal()
        configuration.defaults.conflict.occupiedZone = .skip

        var occupancy = ZoneOccupancy()
        _ = decide(
            TestConfigurations.window(),
            identifier: TestConfigurations.identifier("w1"),
            configuration: configuration,
            occupancy: &occupancy
        )
        let second = decide(
            TestConfigurations.window(),
            identifier: TestConfigurations.identifier("w2"),
            configuration: configuration,
            occupancy: &occupancy
        )

        #expect(second == .skip(.notApplicable, reason: .zoneOccupied(display: "main", zone: "left")))
        #expect(occupancy.occupants(of: "left", on: "main") == [TestConfigurations.identifier("w1")])
    }

    @Test("Bei belegter Zone verdrängt replace in die Fallback-Zone")
    func replaceStrategyDisplacesTheOccupant() throws {
        var configuration = TestConfigurations.minimal()
        configuration.defaults.conflict.occupiedZone = .replace
        // Die Fallback-Bindung zeigt bewusst auf die rechte Zone, obwohl die
        // Rolle "editor" links gebunden ist: würde der Decider den Fallback über
        // die Rolle statt über die Bindung auflösen, landete das verdrängte
        // Fenster wieder in der Zone, aus der es gerade weichen musste.
        configuration.profiles[0].fallback = RoleBinding(role: "editor", display: "main", zone: "right")

        var occupancy = ZoneOccupancy()
        _ = decide(
            TestConfigurations.window(),
            identifier: TestConfigurations.identifier("w1"),
            configuration: configuration,
            occupancy: &occupancy
        )
        let second = decide(
            TestConfigurations.window(),
            identifier: TestConfigurations.identifier("w2"),
            configuration: configuration,
            occupancy: &occupancy
        )

        guard case let .place(_, _, displacing) = second else {
            Issue.record("Erwartet wurde eine Platzierung mit Verdrängung, geliefert wurde \(second)")
            return
        }
        let displacement = try #require(displacing.first)
        #expect(displacing.count == 1)
        #expect(displacement.window == TestConfigurations.identifier("w1"))
        #expect(displacement.newPlacement.zone == "right")
        #expect(occupancy.occupants(of: "left", on: "main") == [TestConfigurations.identifier("w2")])
        #expect(occupancy.occupants(of: "right", on: "main") == [TestConfigurations.identifier("w1")])
    }

    @Test("Bei belegter Zone stapelt stack beide Fenster")
    func stackStrategyKeepsBothWindows() {
        var occupancy = ZoneOccupancy()
        _ = decide(
            TestConfigurations.window(),
            identifier: TestConfigurations.identifier("w1"),
            occupancy: &occupancy
        )
        let second = decide(
            TestConfigurations.window(),
            identifier: TestConfigurations.identifier("w2"),
            occupancy: &occupancy
        )

        #expect(second.placement?.zone == "left")
        #expect(
            occupancy.occupants(of: "left", on: "main")
                == [TestConfigurations.identifier("w1"), TestConfigurations.identifier("w2")]
        )
    }

    @Test("Eine nicht gebundene Rolle landet über den Fallback in der Fallback-Zone")
    func unmappedRoleUsesFallback() throws {
        var configuration = TestConfigurations.minimal()
        configuration.profiles[0].roleBindings.removeAll { $0.role == "communication" }

        var occupancy = ZoneOccupancy()
        let decision = decide(
            TestConfigurations.window(bundleIdentifier: "com.example.chat"),
            configuration: configuration,
            occupancy: &occupancy
        )

        let placement = try #require(decision.placement)
        #expect(placement.usedFallback)
        #expect(placement.zone == "left")
    }

    @Test("Die Beispielkonfiguration platziert Outlook je Profil unterschiedlich")
    func exampleConfigurationPlacesPerProfile() throws {
        let configuration = try TestConfigurations.example()
        let rules = CompiledRuleSet(rules: configuration.rules)
        let decider = PlacementDecider.standard(for: rules)
        let window = TestConfigurations.window(
            bundleIdentifier: "com.microsoft.Outlook",
            title: "Posteingang"
        )

        var zones: Set<ZoneID> = []
        for profile in configuration.profiles {
            let setup = SetupFingerprint(
                displays: Set(
                    profile.fingerprint.displays.compactMap { alias in
                        configuration.displays.first { $0.alias == alias }?.identity
                    }
                )
            )
            let frames = VisibleFrames(
                Dictionary(
                    uniqueKeysWithValues: profile.fingerprint.displays.map { alias in
                        (alias, TestConfigurations.mainVisibleFrame)
                    }
                )
            )

            var occupancy = ZoneOccupancy()
            let decision = decider.decide(
                for: window,
                identifier: TestConfigurations.identifier("outlook"),
                configuration: configuration,
                rules: rules,
                setup: setup,
                visibleFrames: frames,
                occupancy: &occupancy,
                now: now
            )
            zones.insert(try #require(decision.placement).zone)
        }

        // Dieselbe Regel, drei Profile — die Rollen-Indirektion muss zu
        // unterschiedlichen Zielen führen, sonst wäre sie sinnlos.
        #expect(zones.count > 1)
    }
}
