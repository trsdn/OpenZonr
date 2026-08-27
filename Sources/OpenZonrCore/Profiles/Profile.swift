import Foundation

/// Stable identifier of a ``Profile``.
public struct ProfileID: StringIdentifier {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// One display setup and its role mapping — "Büro", "Home", "Unterwegs".
///
/// A profile is selected automatically by comparing the current
/// ``SetupFingerprint`` against ``fingerprint``. It answers exactly one
/// question: *given this arrangement of screens, where does each role live?*
public struct Profile: Codable, Hashable, Sendable, Identifiable {
    public var id: ProfileID
    public var name: String

    /// The display set that activates this profile.
    public var fingerprint: ProfileFingerprint

    /// Which layout each display uses while this profile is active.
    ///
    /// Displays missing from this map fall back to their
    /// ``DisplayDescriptor/defaultLayoutID``. The map exists because the same
    /// panel can be used differently per setup — the built-in screen is the main
    /// workspace while travelling, but a secondary chat screen in the office.
    public var layouts: [DisplayAlias: LayoutID]

    /// Role → zone mapping for this setup.
    public var roleBindings: [RoleBinding]

    /// Where windows go when their role has no binding in this profile.
    ///
    /// Mandatory on purpose: an unmapped role must never mean "somewhere". If a
    /// role is missing, the window lands in a defined place and the event is
    /// logged so the gap becomes visible.
    public var fallback: RoleBinding

    public init(
        id: ProfileID,
        name: String,
        fingerprint: ProfileFingerprint,
        layouts: [DisplayAlias: LayoutID] = [:],
        roleBindings: [RoleBinding],
        fallback: RoleBinding
    ) {
        self.id = id
        self.name = name
        self.fingerprint = fingerprint
        self.layouts = layouts
        self.roleBindings = roleBindings
        self.fallback = fallback
    }
}
