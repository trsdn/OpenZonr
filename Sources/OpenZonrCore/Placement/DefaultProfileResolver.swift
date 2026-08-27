import Foundation

/// Picks the profile that belongs to the display arrangement in front of the user.
///
/// The comparison is exact and order-independent: the set of attached display
/// identities is translated into the set of aliases the configuration knows,
/// and a profile matches when its fingerprint contains exactly those aliases.
///
/// Nothing here guesses. A setup with one extra display — a projector in a
/// meeting room, a spare monitor at a desk — is a different setup, and the
/// answer is `nil`. Picking the "closest" profile instead would place windows
/// on a screen nobody pointed at, which is worse than doing nothing and asking.
/// Whether a deliberate subset mode should exist one day is tracked in
/// `docs/offene-fragen.md`, question 5.
public struct DefaultProfileResolver: ProfileResolver {

    public init() {}

    public func activeProfile(for fingerprint: SetupFingerprint, in configuration: Configuration) -> Profile? {
        guard let aliases = aliases(for: fingerprint, in: configuration) else { return nil }
        return configuration.profiles.first { $0.fingerprint.normalized == aliases }
    }

    /// Translates hardware identities into configuration aliases.
    ///
    /// Returns `nil` as soon as one attached display is not described by the
    /// configuration: an unknown display makes the whole setup unknown, and no
    /// profile can honestly claim to describe it.
    ///
    /// When two descriptors share an identity — a configuration error the
    /// validator reports — the first one in file order wins, so the result stays
    /// deterministic instead of depending on dictionary ordering.
    private func aliases(for fingerprint: SetupFingerprint, in configuration: Configuration) -> Set<DisplayAlias>? {
        var identityToAlias: [DisplayIdentity: DisplayAlias] = [:]
        for display in configuration.displays where identityToAlias[display.identity] == nil {
            identityToAlias[display.identity] = display.alias
        }

        var aliases: Set<DisplayAlias> = []
        for identity in fingerprint.displays {
            guard let alias = identityToAlias[identity] else { return nil }
            aliases.insert(alias)
        }
        return aliases
    }
}
