import Foundation

/// The outcome of loading a configuration file.
///
/// Deliberately not `throws` for every case: "there is no file yet" is a normal
/// state on first launch and leads to onboarding, not to an error dialog. The
/// remaining cases are genuinely different situations that call for different
/// answers, which is why they stay apart instead of collapsing into one failure.
public enum ConfigurationLoadResult {

    /// No file at the resolved location. First launch, or the user deleted it.
    case missing(URL)

    /// The file loaded and validated. `report` may still hold warnings.
    case loaded(Configuration, report: ValidationReport, url: URL)

    /// The file parsed but is not usable. Every finding of the file is present,
    /// so the user can fix all of them in one pass.
    case invalid(ValidationReport, url: URL)

    /// The file could not be read, parsed, or migrated.
    case failed(ConfigurationStoreError)

    /// The configuration, if one could be loaded.
    public var configuration: Configuration? {
        if case let .loaded(configuration, _, _) = self { return configuration }
        return nil
    }

    /// Findings for the cases that produced any.
    public var report: ValidationReport? {
        switch self {
        case let .loaded(_, report, _), let .invalid(report, _):
            return report
        case .missing, .failed:
            return nil
        }
    }
}

/// Loads, validates, migrates and writes the configuration file.
///
/// The store owns the order of those steps, and that order matters: a document
/// is migrated **before** it is decoded, because an older schema need not be
/// decodable into today's `Configuration` at all. Validation runs after
/// decoding, on the finished value, so a check never has to reason about JSON.
///
/// Everything the store touches beyond pure computation — the file system, the
/// environment, the home directory — arrives through an initialiser parameter.
/// That is what lets the atomic-write guarantee be proven by a test that makes
/// the write fail on purpose.
public struct ConfigurationStore {

    private let fileSystem: any ConfigurationFileSystem
    private let writer: AtomicFileWriter
    private let validator: ConfigurationValidator
    private let migrator: ConfigurationMigrator

    public init(
        fileSystem: any ConfigurationFileSystem = DiskFileSystem(),
        validator: ConfigurationValidator = ConfigurationValidator(),
        migrator: ConfigurationMigrator = ConfigurationMigrator()
    ) {
        self.fileSystem = fileSystem
        self.writer = AtomicFileWriter(fileSystem: fileSystem)
        self.validator = validator
        self.migrator = migrator
    }

    // MARK: - Loading

    /// Loads the configuration from `url`.
    public func load(at url: URL) -> ConfigurationLoadResult {
        guard fileSystem.fileExists(at: url) else {
            return .missing(url)
        }

        let data: Data
        do {
            data = try fileSystem.contents(at: url)
        } catch {
            return .failed(.unreadable(url, underlying: String(describing: error)))
        }

        return load(data, from: url)
    }

    /// Loads the configuration from the resolved default location.
    ///
    /// - Parameters:
    ///   - explicitPath: Path from a command line flag; wins over everything else.
    ///   - environment: Environment consulted for `OPENZONR_CONFIG`.
    ///   - homeDirectory: Home directory used to build the default path.
    public func loadDefault(
        explicitPath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> ConfigurationLoadResult {
        load(
            at: ConfigurationLocation.resolve(
                explicitPath: explicitPath,
                environment: environment,
                homeDirectory: homeDirectory
            )
        )
    }

    /// Loads a configuration from bytes that are already in hand.
    ///
    /// `url` only labels the findings and errors; nothing is read from disk.
    public func load(_ data: Data, from url: URL) -> ConfigurationLoadResult {
        let document: [String: Any]
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failed(.invalidJSON(url, underlying: "top-level value is not an object"))
            }
            document = object
        } catch {
            return .failed(.invalidJSON(url, underlying: String(describing: error)))
        }

        let migrated: [String: Any]
        do {
            migrated = try migrator.migrate(document, from: url)
        } catch let error as ConfigurationStoreError {
            return .failed(error)
        } catch {
            return .failed(.invalidJSON(url, underlying: String(describing: error)))
        }

        let configuration: Configuration
        do {
            // Re-serialising the migrated document is the price of migrating
            // before decoding. It is paid once per load and keeps the decoder
            // free of any knowledge about older schemas.
            let migratedData = try JSONSerialization.data(withJSONObject: migrated, options: [.sortedKeys])
            configuration = try ConfigurationCoding.decode(migratedData)
        } catch {
            return .failed(.invalidJSON(url, underlying: String(describing: error)))
        }

        let report = validator.validate(configuration)
        guard report.isUsable else {
            return .invalid(report, url: url)
        }
        return .loaded(configuration, report: report, url: url)
    }

    // MARK: - Writing

    /// Writes `configuration` to `url` atomically.
    ///
    /// The configuration is **not** validated first: refusing to save what the
    /// user is currently editing would make an editor unusable. Callers that
    /// want a guarantee call ``validate(_:)`` themselves.
    public func save(_ configuration: Configuration, to url: URL) throws {
        let data: Data
        do {
            data = try ConfigurationCoding.encode(configuration)
        } catch {
            throw ConfigurationStoreError.writeFailed(url, underlying: String(describing: error))
        }
        try writer.write(data, to: url)
    }

    /// Writes `configuration` to the resolved default location.
    public func saveDefault(
        _ configuration: Configuration,
        explicitPath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) throws {
        try save(
            configuration,
            to: ConfigurationLocation.resolve(
                explicitPath: explicitPath,
                environment: environment,
                homeDirectory: homeDirectory
            )
        )
    }

    /// Validates without touching disk.
    public func validate(_ configuration: Configuration) -> ValidationReport {
        validator.validate(configuration)
    }
}
