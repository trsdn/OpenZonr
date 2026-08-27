import Foundation

/// Stable identifier of a ``ZoneRole``.
public struct RoleID: StringIdentifier {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// A semantic placement target — the central indirection of OpenZonr.
///
/// Rules never point at a zone. They point at a role such as "Kommunikation",
/// "Editor" or "Referenz". Every ``Profile`` maps roles onto its own displays
/// and zones:
///
/// ```text
/// Rule:              Outlook  → role "communication"
/// Profile "Büro":    communication = dell-u2723, zone "right-half"
/// Profile "Home":    communication = lg-38,      zone "right-quarter"
/// Profile "Mobile":  communication = builtin,    zone "full"
/// ```
///
/// Without this indirection every app rule would have to be duplicated per
/// setup, and adding a new monitor would mean rewriting the whole rule set.
public struct ZoneRole: Codable, Hashable, Sendable, Identifiable {
    public var id: RoleID
    /// Label shown in the UI.
    public var name: String
    /// Optional note explaining what belongs into this role.
    public var summary: String?

    public init(id: RoleID, name: String, summary: String? = nil) {
        self.id = id
        self.name = name
        self.summary = summary
    }
}

/// Binds a role to a concrete zone on a concrete display, within one profile.
public struct RoleBinding: Codable, Hashable, Sendable {
    public var role: RoleID
    /// Display the zone lives on.
    public var display: DisplayAlias
    /// Zone within the layout that the profile activates for that display.
    public var zone: ZoneID

    public init(role: RoleID, display: DisplayAlias, zone: ZoneID) {
        self.role = role
        self.display = display
        self.zone = zone
    }
}
