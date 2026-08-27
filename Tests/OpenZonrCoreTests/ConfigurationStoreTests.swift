import Foundation
import Testing
@testable import OpenZonrCore

/// The store is the seam between the user's file and everything else. These
/// tests care about two things: that the shipped example survives a full round
/// trip, and that each way a file can be wrong produces its own distinguishable
/// answer — "could not load the configuration" is not a useful thing to tell
/// anyone.
struct ConfigurationStoreTests {

    private let store = ConfigurationStore()
    private let url = URL(fileURLWithPath: "/tmp/openzonr/config.json")

    // MARK: - The shipped example

    @Test("Die Beispielkonfiguration lädt und validiert ohne Befund")
    func exampleLoadsCleanly() throws {
        let result = store.load(try TestConfigurations.exampleData(), from: TestConfigurations.exampleURL)

        guard case let .loaded(_, report, _) = result else {
            Issue.record("Die Beispielkonfiguration wurde nicht geladen: \(result)")
            return
        }
        #expect(report.errors.isEmpty)
        #expect(report.warnings.isEmpty)
    }

    @Test("Die Beispielkonfiguration schreibt sich verlustfrei zurück")
    func exampleRoundTrips() throws {
        let original = try TestConfigurations.example()

        let fileSystem = InMemoryFileSystem()
        let store = ConfigurationStore(fileSystem: fileSystem)
        try store.save(original, to: url)

        let written = try #require(fileSystem.data(at: url))
        let reloaded = try ConfigurationCoding.decode(written)
        #expect(reloaded == original)

        // Ein zweiter Durchlauf muss dieselben Bytes ergeben, sonst erzeugt
        // jedes Speichern einen Diff, der nichts bedeutet.
        try store.save(reloaded, to: url)
        #expect(fileSystem.data(at: url) == written)
    }

    @Test("Die Ausgabe ist stabil sortiert und endet mit einem Zeilenumbruch")
    func outputIsStable() throws {
        let data = try ConfigurationCoding.encode(TestConfigurations.minimal())
        let text = try #require(String(data: data, encoding: .utf8))

        #expect(text.hasSuffix("\n"))
        // "defaults" steht im Datenmodell hinter "displays", in sortierter
        // Ausgabe aber davor.
        let defaults = try #require(text.range(of: "\"defaults\""))
        let displays = try #require(text.range(of: "\"displays\""))
        #expect(defaults.lowerBound < displays.lowerBound)
    }

    // MARK: - Distinguishable load results

    @Test("Eine fehlende Datei ist kein Fehler, sondern ein eigener Zustand")
    func missingFileIsItsOwnState() {
        let store = ConfigurationStore(fileSystem: InMemoryFileSystem())

        guard case let .missing(missingURL) = store.load(at: url) else {
            Issue.record("Erwartet wurde .missing")
            return
        }
        #expect(missingURL == url)
    }

    @Test("Eine unlesbare Datei wird als unlesbar gemeldet")
    func unreadableFileIsReported() {
        let fileSystem = InMemoryFileSystem(files: [url: Data("{}".utf8)])
        fileSystem.failures.read = true
        let store = ConfigurationStore(fileSystem: fileSystem)

        guard case let .failed(error) = store.load(at: url), case .unreadable = error else {
            Issue.record("Erwartet wurde .failed(.unreadable)")
            return
        }
    }

    @Test("Ungültiges JSON ist von einer unlesbaren Datei unterscheidbar")
    func invalidJSONIsReported() {
        let fileSystem = InMemoryFileSystem(files: [url: Data("{ das ist kein JSON".utf8)])
        let store = ConfigurationStore(fileSystem: fileSystem)

        guard case let .failed(error) = store.load(at: url), case .invalidJSON = error else {
            Issue.record("Erwartet wurde .failed(.invalidJSON)")
            return
        }
    }

    @Test("Ein JSON-Array auf oberster Ebene ist ebenfalls ungültig")
    func topLevelArrayIsInvalid() {
        let fileSystem = InMemoryFileSystem(files: [url: Data("[]".utf8)])
        let store = ConfigurationStore(fileSystem: fileSystem)

        guard case let .failed(error) = store.load(at: url), case .invalidJSON = error else {
            Issue.record("Erwartet wurde .failed(.invalidJSON)")
            return
        }
    }

    @Test("Eine zu neue Version wird abgelehnt statt halb interpretiert")
    func futureVersionIsRejected() throws {
        var configuration = TestConfigurations.minimal()
        configuration.version = Configuration.currentVersion + 1
        let data = try ConfigurationCoding.encode(configuration)

        let fileSystem = InMemoryFileSystem(files: [url: data])
        let store = ConfigurationStore(fileSystem: fileSystem)

        guard
            case let .failed(error) = store.load(at: url),
            case let .unsupportedVersion(found, supported) = error
        else {
            Issue.record("Erwartet wurde .failed(.unsupportedVersion)")
            return
        }
        #expect(found == Configuration.currentVersion + 1)
        #expect(supported == Configuration.currentVersion)
    }

    @Test("Eine fehlende Version wird als solche gemeldet")
    func missingVersionIsReported() {
        let fileSystem = InMemoryFileSystem(files: [url: Data(#"{"displays": []}"#.utf8)])
        let store = ConfigurationStore(fileSystem: fileSystem)

        guard case let .failed(error) = store.load(at: url), case .malformedVersion = error else {
            Issue.record("Erwartet wurde .failed(.malformedVersion)")
            return
        }
    }

    @Test("Eine inhaltlich kaputte Konfiguration liefert alle Befunde statt eines Fehlers")
    func invalidConfigurationYieldsFindings() throws {
        var configuration = TestConfigurations.minimal()
        configuration.rules[0].action.role = "gibtsnicht"
        let data = try ConfigurationCoding.encode(configuration)

        let fileSystem = InMemoryFileSystem(files: [url: data])
        let store = ConfigurationStore(fileSystem: fileSystem)

        guard case let .invalid(report, invalidURL) = store.load(at: url) else {
            Issue.record("Erwartet wurde .invalid")
            return
        }
        #expect(invalidURL == url)
        #expect(report.isUsable == false)
        #expect(report.errors.isEmpty == false)
    }

    @Test("Warnungen verhindern das Laden nicht")
    func warningsDoNotPreventLoading() throws {
        var configuration = TestConfigurations.minimal()
        // Eine Rolle, die keine Regel verwendet: benutzbar, aber vermutlich
        // nicht gemeint.
        configuration.roles.append(ZoneRole(id: "unbenutzt", name: "Unbenutzt"))
        let data = try ConfigurationCoding.encode(configuration)

        let fileSystem = InMemoryFileSystem(files: [url: data])
        let store = ConfigurationStore(fileSystem: fileSystem)

        guard case let .loaded(_, report, _) = store.load(at: url) else {
            Issue.record("Erwartet wurde .loaded")
            return
        }
        #expect(report.errors.isEmpty)
        #expect(report.warnings.isEmpty == false)
    }

    // MARK: - Path resolution

    @Test("Ohne Angaben gilt der Standardpfad in Application Support")
    func defaultPathIsApplicationSupport() {
        let home = URL(fileURLWithPath: "/Users/testperson")
        let resolved = ConfigurationLocation.resolve(environment: [:], homeDirectory: home)

        #expect(resolved.path == "/Users/testperson/Library/Application Support/OpenZonr/config.json")
    }

    @Test("OPENZONR_CONFIG übersteuert den Standardpfad")
    func environmentOverridesDefault() {
        let home = URL(fileURLWithPath: "/Users/testperson")
        let resolved = ConfigurationLocation.resolve(
            environment: ["OPENZONR_CONFIG": "~/dotfiles/openzonr.json"],
            homeDirectory: home
        )

        #expect(resolved.path == "/Users/testperson/dotfiles/openzonr.json")
    }

    @Test("Ein expliziter Pfad übersteuert auch die Umgebungsvariable")
    func explicitPathWinsOverEnvironment() {
        let resolved = ConfigurationLocation.resolve(
            explicitPath: "/etc/openzonr.json",
            environment: ["OPENZONR_CONFIG": "/tmp/ignored.json"],
            homeDirectory: URL(fileURLWithPath: "/Users/testperson")
        )

        #expect(resolved.path == "/etc/openzonr.json")
    }

    @Test("Eine leere Umgebungsvariable zählt nicht als Angabe")
    func emptyEnvironmentValueIsIgnored() {
        let home = URL(fileURLWithPath: "/Users/testperson")
        let resolved = ConfigurationLocation.resolve(
            environment: ["OPENZONR_CONFIG": ""],
            homeDirectory: home
        )

        #expect(resolved.path.hasSuffix("Application Support/OpenZonr/config.json"))
    }

    @Test("loadDefault folgt der Pfadauflösung")
    func loadDefaultUsesResolvedPath() throws {
        let home = URL(fileURLWithPath: "/Users/testperson")
        let target = home.appendingPathComponent("dotfiles/openzonr.json")
        let data = try ConfigurationCoding.encode(TestConfigurations.minimal())

        let fileSystem = InMemoryFileSystem(files: [target: data])
        let store = ConfigurationStore(fileSystem: fileSystem)

        let result = store.loadDefault(
            environment: ["OPENZONR_CONFIG": "~/dotfiles/openzonr.json"],
            homeDirectory: home
        )
        #expect(result.configuration != nil)
    }
}
