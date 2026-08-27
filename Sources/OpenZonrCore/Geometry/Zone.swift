import Foundation

/// Stable identifier of a zone, unique within its ``Layout``.
public struct ZoneID: StringIdentifier {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// A named target area on a display.
///
/// A zone is pure geometry plus identity. It carries no knowledge of which app
/// belongs into it — that link is established indirectly through a ``ZoneRole``
/// binding inside a ``Profile``.
public struct Zone: Codable, Hashable, Sendable, Identifiable {
    public var id: ZoneID
    /// Human readable label shown in the UI, e.g. "rechts oben".
    public var name: String
    /// Geometry relative to the visible frame of the owning display.
    public var frame: RelativeRect

    public init(id: ZoneID, name: String, frame: RelativeRect) {
        self.id = id
        self.name = name
        self.frame = frame
    }
}

/// Stable identifier of a layout, unique within its display descriptor.
public struct LayoutID: StringIdentifier {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// A complete set of zones for one display.
///
/// Layouts belong to a **display**, not to a profile: a 38" ultrawide wants a
/// three-column layout, a 24" office monitor a two-column one, and that stays
/// true no matter which setup profile is currently active. A display may own
/// several layouts (e.g. "3 Spalten" and "2 Spalten + Fokus"); the active
/// profile selects which one is in use.
///
/// Zones within a layout may overlap. Overlap is a legitimate design (a large
/// "focus" zone stacked on top of two half zones), so it is not rejected — but
/// the rule engine resolves ambiguity through ``ZoneRole`` bindings, never by
/// guessing from geometry.
public struct Layout: Codable, Hashable, Sendable, Identifiable {
    public var id: LayoutID
    public var name: String
    public var zones: [Zone]

    public init(id: LayoutID, name: String, zones: [Zone]) {
        self.id = id
        self.name = name
        self.zones = zones
    }
}
