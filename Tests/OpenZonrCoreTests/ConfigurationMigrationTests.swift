import Foundation
import Testing
@testable import OpenZonrCore

struct ConfigurationMigrationTests {

    @Test("Aktuelle Version bleibt unverändert")
    func aktuelleVersionBleibtUnveraendert() throws {
        let document: [String: Any] = ["version": Configuration.currentVersion, "name": "current"]

        let migrated = try ConfigurationMigrator().migrate(document)

        #expect(documentsEqual(migrated, document))
    }

    @Test("Neuere Version wird abgelehnt")
    func neuereVersionWirdAbgelehnt() throws {
        let document: [String: Any] = [
            "version": Configuration.currentVersion + 1,
            "marker": "unchanged"
        ]
        let migrator = ConfigurationMigrator(steps: [
            TestStep(fromVersion: Configuration.currentVersion + 1, key: "marker", value: "changed")
        ])

        let error = try requireStoreError {
            _ = try migrator.migrate(document)
        }

        #expect(error == .unsupportedVersion(found: Configuration.currentVersion + 1, supported: Configuration.currentVersion))
        #expect((document["marker"] as? String) == "unchanged")
    }

    @Test("Fehlende Version ist fehlerhaft")
    func fehlendeVersionIstFehlerhaft() throws {
        let url = URL(fileURLWithPath: "/config/config.json")

        let error = try requireStoreError {
            _ = try ConfigurationMigrator().migrate(["name": "missing"], from: url)
        }

        #expect(error == .malformedVersion(url))
    }

    @Test("Nichtzahlige Version ist fehlerhaft")
    func nichtzahligeVersionIstFehlerhaft() throws {
        let url = URL(fileURLWithPath: "/config/config.json")

        let error = try requireStoreError {
            _ = try ConfigurationMigrator().migrate(["version": "eins"], from: url)
        }

        #expect(error == .malformedVersion(url))
    }

    @Test("Migrationskette fuehrt alle Schritte aus")
    func migrationsketteFuehrtAlleSchritteAus() throws {
        let document: [String: Any] = ["version": 1]
        let migrator = ConfigurationMigrator(
            steps: [
                TestStep(fromVersion: 1, key: "first", value: true),
                TestStep(fromVersion: 2, key: "second", value: "done")
            ],
            targetVersion: 3
        )

        let migrated = try migrator.migrate(document)

        #expect((migrated["version"] as? Int) == 3)
        #expect((migrated["first"] as? Bool) == true)
        #expect((migrated["second"] as? String) == "done")
    }

    @Test("Luecke in der Kette wird gemeldet")
    func lueckeInDerKetteWirdGemeldet() throws {
        let migrator = ConfigurationMigrator(
            steps: [
                TestStep(fromVersion: 1, key: "first", value: true),
                TestStep(fromVersion: 3, key: "third", value: true)
            ],
            targetVersion: 4
        )

        let error = try requireStoreError {
            _ = try migrator.migrate(["version": 1])
        }

        #expect(error == .missingMigrationStep(from: 2, to: 3))
    }

    @Test("Schrittreihenfolge ist egal")
    func schrittreihenfolgeIstEgal() throws {
        let migrator = ConfigurationMigrator(
            steps: [
                TestStep(fromVersion: 2, key: "second", value: "done"),
                TestStep(fromVersion: 1, key: "first", value: "done")
            ],
            targetVersion: 3
        )

        let migrated = try migrator.migrate(["version": 1])

        #expect((migrated["version"] as? Int) == 3)
        #expect((migrated["first"] as? String) == "done")
        #expect((migrated["second"] as? String) == "done")
    }

    @Test("Backup entsteht vor dem Ersetzen")
    func backupEntstehtVorDemErsetzen() throws {
        let url = URL(fileURLWithPath: "/config/config.json")
        let originalData = Data(#"{"version":1,"name":"old"}"#.utf8)
        let fileSystem = InMemoryFileSystem(files: [url: originalData])
        fileSystem.failures.replace = true
        let migrator = ConfigurationMigrator(
            steps: [TestStep(fromVersion: 1, key: "name", value: "new")],
            targetVersion: 2
        )

        let error = try requireStoreError {
            _ = try migrator.migrateAndWrite(
                at: url,
                fileSystem: fileSystem,
                writer: AtomicFileWriter(fileSystem: fileSystem)
            )
        }

        let backupURL = URL(fileURLWithPath: "/config/config.json.v1.backup")
        #expect(error == .writeFailed(url, underlying: "injected(\"replaceItem\")"))
        #expect(fileSystem.data(at: backupURL) == originalData)
        #expect(fileSystem.data(at: url) == originalData)
    }

    @Test("Schreibvariante ersetzt migrierte Datei")
    func schreibvarianteErsetztMigrierteDatei() throws {
        let url = URL(fileURLWithPath: "/config/config.json")
        let originalData = Data(#"{"version":1,"name":"old"}"#.utf8)
        let fileSystem = InMemoryFileSystem(files: [url: originalData])
        let migrator = ConfigurationMigrator(
            steps: [TestStep(fromVersion: 1, key: "name", value: "new")],
            targetVersion: 2
        )

        let migrated = try migrator.migrateAndWrite(
            at: url,
            fileSystem: fileSystem,
            writer: AtomicFileWriter(fileSystem: fileSystem)
        )

        let backupURL = URL(fileURLWithPath: "/config/config.json.v1.backup")
        let writtenData = try #require(fileSystem.data(at: url))
        let writtenDocument = try #require(JSONSerialization.jsonObject(with: writtenData) as? [String: Any])
        #expect((migrated["version"] as? Int) == 2)
        #expect(fileSystem.data(at: backupURL) == originalData)
        #expect((writtenDocument["version"] as? Int) == 2)
        #expect((writtenDocument["name"] as? String) == "new")
    }

    @Test("Schreibfehler laesst Ziel unveraendert")
    func schreibfehlerLaesstZielUnveraendert() throws {
        let url = URL(fileURLWithPath: "/config/config.json")
        let originalData = Data(#"{"version":1,"name":"old"}"#.utf8)
        let fileSystem = InMemoryFileSystem(files: [url: originalData])
        fileSystem.failures.write = true
        let migrator = ConfigurationMigrator(
            steps: [TestStep(fromVersion: 1, key: "name", value: "new")],
            targetVersion: 2
        )

        let error = try requireStoreError {
            _ = try migrator.migrateAndWrite(
                at: url,
                fileSystem: fileSystem,
                writer: AtomicFileWriter(fileSystem: fileSystem)
            )
        }

        #expect(error == .writeFailed(url, underlying: "injected(\"write\")"))
        #expect(fileSystem.data(at: url) == originalData)
    }

    @Test("Produktionsmigrator hat keine Schritte")
    func produktionsmigratorHatKeineSchritte() throws {
        let document: [String: Any] = ["version": Configuration.currentVersion, "name": "current"]

        let migrated = try ConfigurationMigrator().migrate(document)

        #expect(documentsEqual(migrated, document))
    }

    private struct TestStep: MigrationStep {
        let fromVersion: Int
        let toVersion: Int
        let key: String
        let value: Any

        init(fromVersion: Int, key: String, value: Any) {
            self.fromVersion = fromVersion
            self.toVersion = fromVersion + 1
            self.key = key
            self.value = value
        }

        func migrate(_ document: [String: Any]) throws -> [String: Any] {
            var migrated = document
            migrated[key] = value
            return migrated
        }
    }

    private func documentsEqual(_ lhs: [String: Any], _ rhs: [String: Any]) -> Bool {
        NSDictionary(dictionary: lhs).isEqual(to: rhs)
    }

    private func requireStoreError(_ operation: () throws -> Void) throws -> ConfigurationStoreError {
        do {
            try operation()
        } catch let error as ConfigurationStoreError {
            return error
        }
        Issue.record("Expected ConfigurationStoreError")
        throw TestFailure.expectedConfigurationStoreError
    }

    private enum TestFailure: Error {
        case expectedConfigurationStoreError
    }
}
