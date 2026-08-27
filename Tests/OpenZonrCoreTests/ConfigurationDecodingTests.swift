import Foundation
import Testing
@testable import OpenZonrCore

/// The example configuration is part of the documentation, so it must stay in
/// sync with the types. These tests are the guard rail for that.
struct ConfigurationDecodingTests {

    /// Locates `Examples/openzonr.config.json` relative to this source file.
    private static var exampleURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // OpenZonrCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
            .appendingPathComponent("Examples/openzonr.config.json")
    }

    private static func loadExample() throws -> Configuration {
        let data = try Data(contentsOf: exampleURL)
        return try JSONDecoder().decode(Configuration.self, from: data)
    }

    @Test("Die Beispielkonfiguration dekodiert sauber")
    func exampleDecodes() throws {
        let configuration = try Self.loadExample()

        #expect(configuration.version == Configuration.currentVersion)
        #expect(configuration.displays.count == 3)
        #expect(configuration.profiles.count == 3)
        #expect(configuration.roles.count == 5)
        #expect(!configuration.rules.isEmpty)
    }

    @Test("Kodieren und Dekodieren ist verlustfrei")
    func roundTrips() throws {
        let configuration = try Self.loadExample()
        let encoded = try JSONEncoder().encode(configuration)
        let decoded = try JSONDecoder().decode(Configuration.self, from: encoded)

        #expect(decoded == configuration)
    }

    @Test("Bezeichner werden als einfache JSON-Strings kodiert")
    func identifiersEncodeAsStrings() throws {
        let encoded = try JSONEncoder().encode(ZoneRole(id: "communication", name: "Kommunikation"))
        let json = try #require(String(data: encoded, encoding: .utf8))

        #expect(json.contains("\"id\":\"communication\""))
        #expect(!json.contains("rawValue"))
    }

    @Test("Jede Regel verweist auf eine definierte Rolle")
    func rulesReferenceKnownRoles() throws {
        let configuration = try Self.loadExample()
        let knownRoles = Set(configuration.roles.map(\.id))

        for rule in configuration.rules {
            #expect(knownRoles.contains(rule.action.role), "Unbekannte Rolle in Regel \(rule.id)")
        }
    }

    @Test("Jede Rollenbindung zeigt auf eine existierende Zone des aktiven Layouts")
    func roleBindingsResolveToZones() throws {
        let configuration = try Self.loadExample()
        let displaysByAlias = Dictionary(
            uniqueKeysWithValues: configuration.displays.map { ($0.alias, $0) }
        )

        for profile in configuration.profiles {
            for binding in profile.roleBindings + [profile.fallback] {
                let display = try #require(
                    displaysByAlias[binding.display],
                    "Profil \(profile.id) verweist auf unbekanntes Display \(binding.display)"
                )
                let layoutID = profile.layouts[binding.display] ?? display.defaultLayoutID
                let layout = try #require(
                    display.layouts.first { $0.id == layoutID },
                    "Display \(display.alias) kennt kein Layout \(layoutID)"
                )
                #expect(
                    layout.zones.contains { $0.id == binding.zone },
                    "Layout \(layout.id) enthält keine Zone \(binding.zone)"
                )
            }
        }
    }

    @Test("Profile haben eindeutige, ordnungsunabhängige Fingerprints")
    func profileFingerprintsAreUnique() throws {
        let configuration = try Self.loadExample()
        let normalized = configuration.profiles.map(\.fingerprint.normalized)

        #expect(Set(normalized).count == normalized.count)
    }

    @Test("Jedes Display kennt sein Default-Layout")
    func displaysDeclareValidDefaultLayouts() throws {
        let configuration = try Self.loadExample()

        for display in configuration.displays {
            #expect(
                display.layouts.contains { $0.id == display.defaultLayoutID },
                "Display \(display.alias) hat kein Layout \(display.defaultLayoutID)"
            )
        }
    }
}
