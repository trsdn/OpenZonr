import Foundation
import Testing
@testable import OpenZonrCore

struct ZoneResolverTests {
    private let resolver = DefaultZoneResolver()

    @Test("Rollenindirektion nutzt je Profil andere Zielbereiche")
    func roleIndirectionResolvesPerProfile() throws {
        let configuration = try TestConfigurations.example()
        let frames: VisibleFrames = [
            "builtin": TestConfigurations.mainVisibleFrame,
            "dell-u2723": VisibleFrame(x: 100, y: 200, width: 2560, height: 1400),
            "lg-38": VisibleFrame(x: -3840, y: 50, width: 3840, height: 1600)
        ]

        let office = try resolve(role: "communication", profileID: "office", in: configuration, frames: frames)
        #expect(office.display == "dell-u2723")
        #expect(office.zone == "right-half")
        #expect(office.frame == WindowFrame(x: 1380, y: 200, width: 1280, height: 1400))

        let home = try resolve(role: "communication", profileID: "home", in: configuration, frames: frames)
        #expect(home.display == "lg-38")
        #expect(home.zone == "right-quarter")
        #expect(home.frame == WindowFrame(x: -960, y: 50, width: 960, height: 1600))

        let mobile = try resolve(role: "communication", profileID: "mobile", in: configuration, frames: frames)
        #expect(mobile.display == "builtin")
        #expect(mobile.zone == "right-half")
        #expect(mobile.frame == WindowFrame(x: 960, y: 70, width: 960, height: 985))
    }

    @Test("Fallback wird nur für ungebundene Rollen verwendet")
    func fallbackIsUsedOnlyForUnboundRoles() throws {
        let configuration = TestConfigurations.minimal()
        let profile = try #require(configuration.profiles.first)
        let frames: VisibleFrames = ["main": TestConfigurations.mainVisibleFrame]

        let mapped = try resolved(resolver.resolve(
            role: "communication",
            share: nil,
            profile: profile,
            configuration: configuration,
            visibleFrames: frames
        ))
        #expect(mapped.zone == "right")
        #expect(mapped.usedFallback == false)

        let fallback = try resolved(resolver.resolve(
            role: "unknown-role",
            share: nil,
            profile: profile,
            configuration: configuration,
            visibleFrames: frames
        ))
        #expect(fallback.zone == "left")
        #expect(fallback.usedFallback == true)
    }

    @Test("Fehlende Zone liefert Fehler statt Absturz")
    func missingZoneReturnsFailure() throws {
        let configuration = TestConfigurations.minimal { configuration in
            configuration.profiles[0].roleBindings[0].zone = "missing"
        }
        let profile = try #require(configuration.profiles.first)

        #expect(failure(for: resolver.resolve(
            role: "editor",
            share: nil,
            profile: profile,
            configuration: configuration,
            visibleFrames: ["main": TestConfigurations.mainVisibleFrame]
        )) == .unknownZone("missing", layout: "halves", display: "main"))
    }

    @Test("Unbekanntes Display liefert Fehler")
    func unknownDisplayReturnsFailure() throws {
        let configuration = TestConfigurations.minimal { configuration in
            configuration.profiles[0].roleBindings[0].display = "missing"
        }
        let profile = try #require(configuration.profiles.first)

        #expect(failure(for: resolver.resolve(
            role: "editor",
            share: nil,
            profile: profile,
            configuration: configuration,
            visibleFrames: ["main": TestConfigurations.mainVisibleFrame]
        )) == .unknownDisplay("missing"))
    }

    @Test("Unbekanntes Layout liefert Fehler")
    func unknownLayoutReturnsFailure() throws {
        let configuration = TestConfigurations.minimal { configuration in
            configuration.profiles[0].layouts["main"] = "missing-layout"
        }
        let profile = try #require(configuration.profiles.first)

        #expect(failure(for: resolver.resolve(
            role: "editor",
            share: nil,
            profile: profile,
            configuration: configuration,
            visibleFrames: ["main": TestConfigurations.mainVisibleFrame]
        )) == .unknownLayout("missing-layout", display: "main"))
    }

    @Test("Fehlender sichtbarer Frame liefert Fehler")
    func missingVisibleFrameReturnsFailure() throws {
        let configuration = TestConfigurations.minimal()
        let profile = try #require(configuration.profiles.first)

        #expect(failure(for: resolver.resolve(
            role: "editor",
            share: nil,
            profile: profile,
            configuration: configuration,
            visibleFrames: [:]
        )) == .missingVisibleFrame("main"))
    }

    @Test("Koordinatenumrechnung beachtet Menüleiste und Dock")
    func coordinateConversionUsesVisibleFrame() throws {
        let configuration = quarterConfiguration(displayAlias: "main", frame: RelativeRect(x: 0, y: 0, width: 0.5, height: 0.5))
        let profile = try #require(configuration.profiles.first)
        let frames: VisibleFrames = ["main": TestConfigurations.mainVisibleFrame]

        let quarter = try resolved(resolver.resolve(
            role: "editor",
            share: nil,
            profile: profile,
            configuration: configuration,
            visibleFrames: frames
        ))
        #expect(quarter.frame == WindowFrame(x: 0, y: 563, width: 960, height: 492))

        let fullConfiguration = quarterConfiguration(displayAlias: "main", frame: .full)
        let fullProfile = try #require(fullConfiguration.profiles.first)
        let full = try resolved(resolver.resolve(
            role: "editor",
            share: nil,
            profile: fullProfile,
            configuration: fullConfiguration,
            visibleFrames: frames
        ))
        #expect(full.frame == WindowFrame(x: 0, y: 70, width: 1920, height: 985))
    }

    @Test("Negative Displayursprünge bleiben erhalten")
    func negativeOriginsRemainCorrect() throws {
        let configuration = quarterConfiguration(displayAlias: "left", frame: RelativeRect(x: 0, y: 0, width: 0.5, height: 0.5))
        let profile = try #require(configuration.profiles.first)

        let placement = try resolved(resolver.resolve(
            role: "editor",
            share: nil,
            profile: profile,
            configuration: configuration,
            visibleFrames: ["left": TestConfigurations.leftVisibleFrame]
        ))

        #expect(placement.frame == WindowFrame(x: -1440, y: 450, width: 720, height: 450))
    }

    @Test("Vertikale Zonenteilung deckt die Zone lückenlos ab")
    func verticalShareTilesZoneWithoutGaps() throws {
        let configuration = TestConfigurations.minimal()
        let profile = try #require(configuration.profiles.first)
        let frames: VisibleFrames = ["main": TestConfigurations.mainVisibleFrame]

        let upper = try resolved(resolver.resolve(
            role: "communication",
            share: ZoneShare(axis: .vertical, slots: 2, slotIndex: 0),
            profile: profile,
            configuration: configuration,
            visibleFrames: frames
        ))
        let lower = try resolved(resolver.resolve(
            role: "communication",
            share: ZoneShare(axis: .vertical, slots: 2, slotIndex: 1),
            profile: profile,
            configuration: configuration,
            visibleFrames: frames
        ))
        let original = try resolved(resolver.resolve(
            role: "communication",
            share: nil,
            profile: profile,
            configuration: configuration,
            visibleFrames: frames
        ))

        #expect(upper.frame.height + lower.frame.height == original.frame.height)
        #expect(upper.frame.y == lower.frame.y + lower.frame.height)
        #expect(upper.frame.y > lower.frame.y)
    }

    @Test("Horizontale Zonenteilung deckt die Zone lückenlos ab")
    func horizontalShareTilesZoneWithoutGaps() throws {
        let configuration = TestConfigurations.minimal()
        let profile = try #require(configuration.profiles.first)
        let frames: VisibleFrames = ["main": TestConfigurations.mainVisibleFrame]

        let left = try resolved(resolver.resolve(
            role: "communication",
            share: ZoneShare(axis: .horizontal, slots: 2, slotIndex: 0),
            profile: profile,
            configuration: configuration,
            visibleFrames: frames
        ))
        let right = try resolved(resolver.resolve(
            role: "communication",
            share: ZoneShare(axis: .horizontal, slots: 2, slotIndex: 1),
            profile: profile,
            configuration: configuration,
            visibleFrames: frames
        ))
        let original = try resolved(resolver.resolve(
            role: "communication",
            share: nil,
            profile: profile,
            configuration: configuration,
            visibleFrames: frames
        ))

        #expect(left.frame.width + right.frame.width == original.frame.width)
        #expect(left.frame.x + left.frame.width == right.frame.x)
    }

    @Test("Ungültige Zonenteilung liefert Fehler")
    func invalidShareReturnsFailure() throws {
        let configuration = TestConfigurations.minimal()
        let profile = try #require(configuration.profiles.first)
        let frames: VisibleFrames = ["main": TestConfigurations.mainVisibleFrame]
        let tooFewSlots = ZoneShare(axis: .horizontal, slots: 1, slotIndex: 0)
        let indexOutOfRange = ZoneShare(axis: .vertical, slots: 2, slotIndex: 2)

        #expect(failure(for: resolver.resolve(
            role: "communication",
            share: tooFewSlots,
            profile: profile,
            configuration: configuration,
            visibleFrames: frames
        )) == .invalidShare(tooFewSlots))
        #expect(failure(for: resolver.resolve(
            role: "communication",
            share: indexOutOfRange,
            profile: profile,
            configuration: configuration,
            visibleFrames: frames
        )) == .invalidShare(indexOutOfRange))
    }

    @Test("Ungerade Teilung rundet gemeinsame Kanten ohne Lücken")
    func oddShareRoundingTilesWithoutGaps() throws {
        let configuration = quarterConfiguration(displayAlias: "main", frame: .full)
        let profile = try #require(configuration.profiles.first)
        let frames: VisibleFrames = ["main": VisibleFrame(x: 0, y: 0, width: 901, height: 1001)]

        let first = try resolved(resolver.resolve(role: "editor", share: ZoneShare(axis: .vertical, slots: 3, slotIndex: 0), profile: profile, configuration: configuration, visibleFrames: frames))
        let second = try resolved(resolver.resolve(role: "editor", share: ZoneShare(axis: .vertical, slots: 3, slotIndex: 1), profile: profile, configuration: configuration, visibleFrames: frames))
        let third = try resolved(resolver.resolve(role: "editor", share: ZoneShare(axis: .vertical, slots: 3, slotIndex: 2), profile: profile, configuration: configuration, visibleFrames: frames))

        #expect(first.frame.height + second.frame.height + third.frame.height == 1001)
        #expect(first.frame.y == second.frame.y + second.frame.height)
        #expect(second.frame.y == third.frame.y + third.frame.height)
    }

    private func resolve(role: RoleID, profileID: ProfileID, in configuration: Configuration, frames: VisibleFrames) throws -> ResolvedPlacement {
        let profile = try #require(configuration.profiles.first { $0.id == profileID })
        return try resolved(resolver.resolve(role: role, share: nil, profile: profile, configuration: configuration, visibleFrames: frames))
    }

    private func resolved(_ result: Result<ResolvedPlacement, ZoneResolutionFailure>) throws -> ResolvedPlacement {
        switch result {
        case let .success(placement):
            return placement
        case let .failure(failure):
            Issue.record("Unerwarteter Fehler: \(failure)")
            throw TestFailure()
        }
    }

    private func failure(for result: Result<ResolvedPlacement, ZoneResolutionFailure>) -> ZoneResolutionFailure? {
        if case let .failure(failure) = result {
            return failure
        }
        return nil
    }

    private func quarterConfiguration(displayAlias: DisplayAlias, frame: RelativeRect) -> Configuration {
        Configuration(
            version: Configuration.currentVersion,
            displays: [
                DisplayDescriptor(
                    alias: displayAlias,
                    displayName: "Testdisplay",
                    identity: .builtin,
                    layouts: [
                        Layout(
                            id: "layout",
                            name: "Layout",
                            zones: [Zone(id: "target", name: "Ziel", frame: frame)]
                        )
                    ],
                    defaultLayoutID: "layout"
                )
            ],
            roles: [ZoneRole(id: "editor", name: "Editor")],
            profiles: [
                Profile(
                    id: "profile",
                    name: "Profil",
                    fingerprint: ProfileFingerprint(displays: [displayAlias]),
                    layouts: [displayAlias: "layout"],
                    roleBindings: [RoleBinding(role: "editor", display: displayAlias, zone: "target")],
                    fallback: RoleBinding(role: "editor", display: displayAlias, zone: "target")
                )
            ],
            rules: []
        )
    }

    private struct TestFailure: Error {}
}
