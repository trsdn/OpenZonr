import Foundation

/// Everything that can go wrong around a configuration file, kept as distinct
/// cases on purpose.
///
/// "Could not load the configuration" is not a useful thing to tell a user.
/// A missing file calls for onboarding, an unreadable one for a look at
/// permissions, broken JSON for an editor, and a version from the future for an
/// app update. Collapsing those into one error throws away exactly the
/// information that decides what to do next.
///
/// The underlying system error is carried as a string rather than as an `Error`
/// so the type stays `Equatable` and `Sendable` without contortions; the raw
/// error is only ever shown, never inspected.
public enum ConfigurationStoreError: Error, Hashable, Sendable, CustomStringConvertible {

    /// The file exists but could not be read — permissions, a broken symlink, a
    /// disk that went away.
    case unreadable(URL, underlying: String)

    /// The file is not valid JSON, or does not match the schema.
    case invalidJSON(URL, underlying: String)

    /// The file declares a version this build does not know.
    ///
    /// Rejected outright instead of interpreted as far as it goes: a newer
    /// schema may have moved fields, and a half-understood configuration would
    /// place windows somewhere nobody asked for.
    case unsupportedVersion(found: Int, supported: Int)

    /// The file declares a version below the current one, but the migration
    /// chain has no step for it.
    case missingMigrationStep(from: Int, to: Int)

    /// The version field is missing or not an integer.
    case malformedVersion(URL)

    /// Writing failed. The destination file is unchanged.
    case writeFailed(URL, underlying: String)

    public var description: String {
        switch self {
        case let .unreadable(url, underlying):
            return L.string(
                "configurationStoreError.unreadable",
                "Configuration %@ is not readable: %@",
                url.path, underlying
            )
        case let .invalidJSON(url, underlying):
            return L.string(
                "configurationStoreError.invalidJSON",
                "Configuration %@ is not valid JSON: %@",
                url.path, underlying
            )
        case let .unsupportedVersion(found, supported):
            return L.string(
                "configurationStoreError.unsupportedVersion",
                "The configuration has version %lld; this version of OpenZonr knows at most %lld.",
                found, supported
            )
        case let .missingMigrationStep(from, to):
            return L.string(
                "configurationStoreError.missingMigrationStep",
                "There is no migration step from version %lld to %lld.",
                from, to
            )
        case let .malformedVersion(url):
            return L.string(
                "configurationStoreError.malformedVersion",
                "Configuration %@ has no valid \"version\" field.",
                url.path
            )
        case let .writeFailed(url, underlying):
            return L.string(
                "configurationStoreError.writeFailed",
                "Configuration %@ could not be written: %@",
                url.path, underlying
            )
        }
    }
}
