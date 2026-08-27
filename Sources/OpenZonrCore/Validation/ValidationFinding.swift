import Foundation

/// Whether a finding makes the configuration unusable or merely suspicious.
public enum ValidationSeverity: String, Codable, Hashable, Sendable, CaseIterable {
    /// The configuration cannot be used as written.
    case error
    /// The configuration works, but probably does not do what the author meant.
    case warning
}

/// The machine-readable kind of a validation finding.
///
/// A code exists so that tests can assert on a specific finding instead of
/// matching a human-readable message, and so the UI can offer a targeted fix
/// without parsing text.
public enum ValidationCode: String, Codable, Hashable, Sendable, CaseIterable {

    // MARK: Uniqueness

    case duplicateDisplayAlias
    case duplicateRoleID
    case duplicateRuleID
    case duplicateProfileID
    case duplicateLayoutID
    case duplicateZoneID

    // MARK: Referential integrity

    case unknownRoleInRule
    case unknownDisplayInBinding
    case unknownLayoutInProfile
    case unknownZoneInBinding
    case unknownDefaultLayout

    // MARK: Geometry

    case relativeRectOutOfRange
    case relativeRectNonPositiveSize
    case relativeRectOverflow
    case zoneShareTooFewSlots
    case zoneShareSlotIndexOutOfRange

    // MARK: Policies and filters

    case aspectRatioInverted
    case aspectRatioNonPositive
    case retryAttemptsTooLow
    case negativeDuration
    case nonPositiveWindowSize
    case invalidTitlePattern

    // MARK: Profiles

    case duplicateProfileFingerprint
    case unknownDisplayInFingerprint
    case emptyProfileFingerprint

    // MARK: Warnings

    case unusedRole
    case shadowedRule

    /// The severity this code is always reported with.
    ///
    /// Severity is a property of the code rather than of the individual finding:
    /// the same problem must never be an error in one place and a warning in
    /// another, or the distinction stops meaning anything.
    public var severity: ValidationSeverity {
        switch self {
        case .unusedRole, .shadowedRule:
            return .warning
        default:
            return .error
        }
    }
}

/// A single problem found in a configuration, with the place it was found.
public struct ValidationFinding: Hashable, Sendable, CustomStringConvertible {

    /// What kind of problem this is.
    public var code: ValidationCode
    /// Where in the document the problem sits.
    public var path: ConfigurationPath
    /// Human-readable explanation. German, because it is shown to the user.
    public var message: String

    /// Whether the configuration is unusable because of this finding.
    public var severity: ValidationSeverity { code.severity }

    public init(code: ValidationCode, path: ConfigurationPath, message: String) {
        self.code = code
        self.path = path
        self.message = message
    }

    public var description: String {
        "\(severity.rawValue) \(code.rawValue) at \(path): \(message)"
    }
}
