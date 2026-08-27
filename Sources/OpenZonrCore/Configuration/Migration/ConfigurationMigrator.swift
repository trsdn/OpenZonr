import Foundation

/// Lifts raw configuration JSON documents to the schema this build understands.
public struct ConfigurationMigrator {

    private static let defaultSourceURL = URL(fileURLWithPath: "config.json")

    private let stepsByFromVersion: [Int: any MigrationStep]
    private let targetVersion: Int

    /// Production migrator. There are no historical schema steps yet.
    public init() {
        self.init(steps: [], targetVersion: Configuration.currentVersion)
    }

    init(steps: [any MigrationStep], targetVersion: Int = Configuration.currentVersion) {
        var indexedSteps: [Int: any MigrationStep] = [:]
        for step in steps {
            indexedSteps[step.fromVersion] = step
        }
        self.stepsByFromVersion = indexedSteps
        self.targetVersion = targetVersion
    }

    /// Migrates `document` without touching disk.
    public func migrate(_ document: [String: Any]) throws -> [String: Any] {
        try migrate(document, from: Self.defaultSourceURL)
    }

    /// Migrates `document` without touching disk.
    ///
    /// `url` is used only to report malformed-version errors against the file
    /// that supplied the document.
    public func migrate(_ document: [String: Any], from url: URL) throws -> [String: Any] {
        let originalVersion = try version(in: document, from: url)

        if originalVersion > targetVersion {
            throw ConfigurationStoreError.unsupportedVersion(found: originalVersion, supported: targetVersion)
        }

        guard originalVersion < targetVersion else {
            return document
        }

        var migrated = document
        var currentVersion = originalVersion
        while currentVersion < targetVersion {
            let nextVersion = currentVersion + 1
            guard
                let step = stepsByFromVersion[currentVersion],
                step.toVersion == nextVersion
            else {
                throw ConfigurationStoreError.missingMigrationStep(from: currentVersion, to: nextVersion)
            }

            migrated = try step.migrate(migrated)
            migrated["version"] = nextVersion
            currentVersion = nextVersion
        }

        migrated["version"] = targetVersion
        return migrated
    }

    /// Reads, migrates and persists a configuration file using the real disk.
    @discardableResult
    public func migrateAndWrite(at url: URL) throws -> [String: Any] {
        let fileSystem = DiskFileSystem()
        return try migrateAndWrite(
            at: url,
            fileSystem: fileSystem,
            writer: AtomicFileWriter(fileSystem: fileSystem)
        )
    }

    /// Reads, migrates and persists a configuration file through testable seams.
    ///
    /// When a file is actually migrated, the original bytes are copied first to a
    /// sibling backup named `<filename>.v<oldVersion>.backup`; only then is the
    /// target replaced atomically.
    @discardableResult
    public func migrateAndWrite(
        at url: URL,
        fileSystem: any ConfigurationFileSystem,
        writer: AtomicFileWriter
    ) throws -> [String: Any] {
        let originalData: Data
        do {
            originalData = try fileSystem.contents(at: url)
        } catch {
            throw ConfigurationStoreError.unreadable(url, underlying: String(describing: error))
        }

        let document = try decodeDocument(originalData, from: url)
        let oldVersion = try version(in: document, from: url)
        let migrated = try migrate(document, from: url)

        guard oldVersion < targetVersion else {
            return migrated
        }

        let backupURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).v\(oldVersion).backup", isDirectory: false)
        do {
            try fileSystem.copyItem(at: url, to: backupURL)
        } catch {
            throw ConfigurationStoreError.writeFailed(backupURL, underlying: String(describing: error))
        }

        try writer.write(try encodeDocument(migrated, for: url), to: url)
        return migrated
    }

    private func version(in document: [String: Any], from url: URL) throws -> Int {
        guard let rawVersion = document["version"] else {
            throw ConfigurationStoreError.malformedVersion(url)
        }

        if let version = rawVersion as? Int {
            return version
        }

        if rawVersion is Bool {
            throw ConfigurationStoreError.malformedVersion(url)
        }

        if let version = rawVersion as? NSNumber {
            let value = version.doubleValue
            guard value.rounded(.towardZero) == value else {
                throw ConfigurationStoreError.malformedVersion(url)
            }
            return version.intValue
        }

        throw ConfigurationStoreError.malformedVersion(url)
    }

    private func decodeDocument(_ data: Data, from url: URL) throws -> [String: Any] {
        do {
            guard let document = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ConfigurationStoreError.invalidJSON(url, underlying: "top-level value is not an object")
            }
            return document
        } catch let error as ConfigurationStoreError {
            throw error
        } catch {
            throw ConfigurationStoreError.invalidJSON(url, underlying: String(describing: error))
        }
    }

    private func encodeDocument(_ document: [String: Any], for url: URL) throws -> Data {
        do {
            var data = try JSONSerialization.data(
                withJSONObject: document,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            if data.last != 0x0A {
                data.append(0x0A)
            }
            return data
        } catch {
            throw ConfigurationStoreError.invalidJSON(url, underlying: String(describing: error))
        }
    }
}
