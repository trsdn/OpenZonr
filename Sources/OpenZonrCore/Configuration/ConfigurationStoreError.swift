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
            return "Konfiguration \(url.path) ist nicht lesbar: \(underlying)"
        case let .invalidJSON(url, underlying):
            return "Konfiguration \(url.path) ist kein gültiges JSON: \(underlying)"
        case let .unsupportedVersion(found, supported):
            return "Konfiguration hat Version \(found), diese Version von OpenZonr kennt höchstens \(supported)."
        case let .missingMigrationStep(from, to):
            return "Für die Migration von Version \(from) nach \(to) existiert kein Schritt."
        case let .malformedVersion(url):
            return "Konfiguration \(url.path) enthält kein gültiges Feld \"version\"."
        case let .writeFailed(url, underlying):
            return "Konfiguration \(url.path) konnte nicht geschrieben werden: \(underlying)"
        }
    }
}
