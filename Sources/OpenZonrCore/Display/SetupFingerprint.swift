import Foundation

/// The identity of a *display arrangement*, used to pick the active ``Profile``.
///
/// The fingerprint is the order-independent set of all currently active
/// ``DisplayIdentity`` values. Order independence matters: whether the external
/// monitor is attached before or after the dock is connected must not change
/// which profile is selected.
///
/// Examples:
/// - `{builtin}` → "Unterwegs"
/// - `{builtin, DellU2723-SN1234}` → "Büro"
/// - `{builtin, LG38-SN9876}` → "Home"
///
/// Changes are observed through `CGDisplayRegisterReconfigurationCallback`.
/// Reconfiguration fires several times while displays are waking up, so the
/// observer debounces before recomputing the fingerprint.
///
/// If a fingerprint is unknown, OpenZonr **asks the user** to create a profile
/// instead of guessing a close match. Guessing would silently place windows on
/// the wrong screen, which is worse than doing nothing.
public struct SetupFingerprint: Hashable, Sendable {
    /// All active display identities, deduplicated.
    public let displays: Set<DisplayIdentity>

    public init(displays: Set<DisplayIdentity>) {
        self.displays = displays
    }
}

/// The fingerprint as written in the configuration file.
///
/// Profiles reference displays by ``DisplayAlias`` rather than by raw identity,
/// so the file stays readable. Resolution to a ``SetupFingerprint`` happens via
/// the ``DisplayDescriptor`` table.
///
/// Matching is exact on the alias set: a setup with an extra, unknown display is
/// *not* the same profile as the subset. Whether a "best subset match" mode
/// should exist is deliberately left open — see `docs/offene-fragen.md`.
public struct ProfileFingerprint: Codable, Hashable, Sendable {
    /// Aliases of all displays that must be present, in any order.
    public var displays: [DisplayAlias]

    public init(displays: [DisplayAlias]) {
        self.displays = displays
    }

    /// Order-independent comparison key.
    public var normalized: Set<DisplayAlias> { Set(displays) }
}
