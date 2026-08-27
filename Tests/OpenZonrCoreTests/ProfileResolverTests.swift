import Foundation
import Testing
@testable import OpenZonrCore

/// Profile selection is the one decision OpenZonr refuses to guess at. These
/// tests pin that refusal down, because a resolver that "helpfully" picks a
/// near match would move windows onto screens nobody pointed at.
struct ProfileResolverTests {

    private let resolver = DefaultProfileResolver()

    private static let dell = DisplayIdentity.edid(vendorNumber: 4268, modelNumber: 42145, serialNumber: 1_194_485_571)
    private static let lg = DisplayIdentity.edid(vendorNumber: 7789, modelNumber: 23847, serialNumber: 909_876)
    private static let projector = DisplayIdentity.edid(vendorNumber: 1, modelNumber: 2, serialNumber: 3)

    @Test("Das Büro-Setup wählt das Büro-Profil")
    func resolvesOffice() throws {
        let configuration = try TestConfigurations.example()
        let profile = try #require(
            resolver.activeProfile(
                for: SetupFingerprint(displays: [.builtin, Self.dell]),
                in: configuration
            )
        )
        #expect(profile.id == "office")
    }

    @Test("Das Home-Setup wählt das Home-Profil")
    func resolvesHome() throws {
        let configuration = try TestConfigurations.example()
        let profile = try #require(
            resolver.activeProfile(
                for: SetupFingerprint(displays: [.builtin, Self.lg]),
                in: configuration
            )
        )
        #expect(profile.id == "home")
    }

    @Test("Das integrierte Display allein wählt das Unterwegs-Profil")
    func resolvesMobile() throws {
        let configuration = try TestConfigurations.example()
        let profile = try #require(
            resolver.activeProfile(for: SetupFingerprint(displays: [.builtin]), in: configuration)
        )
        #expect(profile.id == "mobile")
    }

    @Test("Die Reihenfolge der Erkennung ändert das Profil nicht")
    func matchingIsOrderIndependent() throws {
        let configuration = try TestConfigurations.example()
        // Ein Set kennt keine Reihenfolge; der Test hält fest, dass die
        // Auflösung auch nicht heimlich eine annimmt.
        let first = resolver.activeProfile(
            for: SetupFingerprint(displays: [.builtin, Self.dell]),
            in: configuration
        )
        let second = resolver.activeProfile(
            for: SetupFingerprint(displays: [Self.dell, .builtin]),
            in: configuration
        )
        #expect(first?.id == second?.id)
        #expect(first?.id == "office")
    }

    @Test("Ein zusätzlicher Beamer macht das Setup unbekannt")
    func extraDisplayYieldsNoProfile() throws {
        let configuration = try TestConfigurations.example()
        let profile = resolver.activeProfile(
            for: SetupFingerprint(displays: [.builtin, Self.dell, Self.projector]),
            in: configuration
        )
        #expect(profile == nil)
    }

    @Test("Eine Teilmenge eines Profils wird nicht als Treffer gewertet")
    func subsetIsNotAMatch() throws {
        var configuration = try TestConfigurations.example()
        // Das Unterwegs-Profil entfernen, damit {builtin} keine echte
        // Entsprechung mehr hat: Übrig bleiben nur Profile, deren Fingerprint
        // eine echte Obermenge ist.
        configuration.profiles.removeAll { $0.id == "mobile" }

        let profile = resolver.activeProfile(for: SetupFingerprint(displays: [.builtin]), in: configuration)
        #expect(profile == nil)
    }

    @Test("Ein unbekanntes Display macht das gesamte Setup unbekannt")
    func unknownDisplayYieldsNoProfile() throws {
        let configuration = try TestConfigurations.example()
        let profile = resolver.activeProfile(
            for: SetupFingerprint(displays: [Self.projector]),
            in: configuration
        )
        #expect(profile == nil)
    }

    @Test("Ein leeres Setup liefert kein Profil")
    func emptyFingerprintYieldsNoProfile() throws {
        let configuration = try TestConfigurations.example()
        #expect(resolver.activeProfile(for: SetupFingerprint(displays: []), in: configuration) == nil)
    }

    @Test("Die Fallback-Identität ohne Seriennummer wird ebenso exakt verglichen")
    func matchesFallbackIdentity() {
        let identity = DisplayIdentity.fallback(
            vendorNumber: 4268,
            modelNumber: 42145,
            pixelWidth: 3840,
            pixelHeight: 2160,
            portIndex: 1
        )
        var configuration = TestConfigurations.minimal()
        configuration.displays.append(
            DisplayDescriptor(
                alias: "extern",
                displayName: "Ohne Seriennummer",
                identity: identity,
                layouts: [
                    Layout(
                        id: "voll",
                        name: "Vollbild",
                        zones: [Zone(id: "full", name: "Vollbild", frame: .full)]
                    )
                ],
                defaultLayoutID: "voll"
            )
        )
        configuration.profiles.append(
            Profile(
                id: "dock",
                name: "Dock",
                fingerprint: ProfileFingerprint(displays: ["main", "extern"]),
                roleBindings: [RoleBinding(role: "editor", display: "extern", zone: "full")],
                fallback: RoleBinding(role: "editor", display: "extern", zone: "full")
            )
        )

        let profile = resolver.activeProfile(
            for: SetupFingerprint(displays: [.builtin, identity]),
            in: configuration
        )
        #expect(profile?.id == "dock")

        // Ein anderer Port ist eine andere Identität — genau die Schwäche, vor
        // der das Datenmodell warnt, hier als Verhalten festgehalten.
        let otherPort = DisplayIdentity.fallback(
            vendorNumber: 4268,
            modelNumber: 42145,
            pixelWidth: 3840,
            pixelHeight: 2160,
            portIndex: 2
        )
        #expect(
            resolver.activeProfile(
                for: SetupFingerprint(displays: [.builtin, otherPort]),
                in: configuration
            ) == nil
        )
    }
}
