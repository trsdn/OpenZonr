import Foundation
import OpenZonrCore

/// A profile resolver that honours a manual choice before asking the hardware.
///
/// The automatic match is exact and refuses to guess, which is right: it never
/// places windows on a screen nobody pointed at. But "refuses to guess" and
/// "the user knows better" are different situations, and the menu bar app has
/// to offer the second one — a display that reports a different EDID after a
/// firmware update should not make the tool unusable until the configuration is
/// edited.
///
/// The override is deliberately not persisted. It is a correction for the
/// session in front of the user, not a new rule; a pinned profile that survived
/// a reboot into a different setup would silently place windows on the wrong
/// screen, which is exactly the failure the exact match exists to prevent.
public struct PinnedProfileResolver: ProfileResolver {

    /// The profile the user selected by hand, if any.
    public let pinned: ProfileID?

    private let automatic = DefaultProfileResolver()

    public init(pinned: ProfileID?) {
        self.pinned = pinned
    }

    public func activeProfile(for fingerprint: SetupFingerprint, in configuration: Configuration) -> Profile? {
        if let pinned, let profile = configuration.profiles.first(where: { $0.id == pinned }) {
            return profile
        }
        return automatic.activeProfile(for: fingerprint, in: configuration)
    }
}
