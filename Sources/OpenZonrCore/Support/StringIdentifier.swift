import Foundation

/// Shared behaviour for the string-backed identifier types used throughout the
/// configuration (zone, layout, role, rule, profile and display identifiers).
///
/// The explicit `Codable` implementation matters: it guarantees that an
/// identifier is written as a bare JSON string (`"communication"`) instead of a
/// wrapper object, which keeps the configuration file readable and hand-editable.
public protocol StringIdentifier:
    RawRepresentable,
    Codable,
    CodingKeyRepresentable,
    Hashable,
    Sendable,
    Comparable,
    CustomStringConvertible,
    ExpressibleByStringLiteral
where RawValue == String {
    init(rawValue: String)
}

extension StringIdentifier {
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    public var description: String { rawValue }
}
