import Foundation
import OpenZonrCore
import Testing
@testable import OpenZonrMac

/// The manual profile override is the one place where the menu bar app is
/// allowed to overrule the exact hardware match. These tests pin down both
/// halves of that: that a choice is honoured, and that it cannot conjure a
/// profile the configuration does not contain.
struct PinnedProfileResolverTests {

    private static let dell = DisplayIdentity.edid(vendorNumber: 4268, modelNumber: 42145, serialNumber: 1_194_485_571)

    private static func configuration() throws -> Configuration {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // OpenZonrMacTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
            .appendingPathComponent("Examples/openzonr.config.json")
        return try ConfigurationCoding.decode(try Data(contentsOf: url))
    }

    @Test("Ohne Handauswahl entscheidet die Hardware")
    func withoutPinFallsBackToAutomatic() throws {
        let configuration = try Self.configuration()
        let resolver = PinnedProfileResolver(pinned: nil)
        let profile = try #require(
            resolver.activeProfile(for: SetupFingerprint(displays: [.builtin, Self.dell]), in: configuration)
        )
        #expect(profile.id == "office")
    }

    @Test("Die Handauswahl schlägt die Hardware")
    func pinWins() throws {
        let configuration = try Self.configuration()
        let resolver = PinnedProfileResolver(pinned: "mobile")
        let profile = try #require(
            resolver.activeProfile(for: SetupFingerprint(displays: [.builtin, Self.dell]), in: configuration)
        )
        #expect(profile.id == "mobile")
    }

    @Test("Die Handauswahl gilt auch dort, wo die Hardware nichts erkennt")
    func pinAppliesWhereAutomaticRefuses() throws {
        let configuration = try Self.configuration()
        let unknown = DisplayIdentity.edid(vendorNumber: 1, modelNumber: 2, serialNumber: 3)
        #expect(DefaultProfileResolver().activeProfile(for: SetupFingerprint(displays: [unknown]), in: configuration) == nil)

        let resolver = PinnedProfileResolver(pinned: "home")
        let profile = try #require(
            resolver.activeProfile(for: SetupFingerprint(displays: [unknown]), in: configuration)
        )
        #expect(profile.id == "home")
    }

    /// A pinned profile that no longer exists must not silently disable the
    /// automatic match — the configuration can be edited while the app runs.
    @Test("Eine Handauswahl, die es nicht mehr gibt, fällt auf die Hardware zurück")
    func stalePinFallsBack() throws {
        let configuration = try Self.configuration()
        let resolver = PinnedProfileResolver(pinned: "geloescht")
        let profile = try #require(
            resolver.activeProfile(for: SetupFingerprint(displays: [.builtin]), in: configuration)
        )
        #expect(profile.id == "mobile")
    }
}
