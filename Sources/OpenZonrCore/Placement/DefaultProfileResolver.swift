import Foundation

/// Picks the profile that matches the currently attached displays.
///
/// The comparison is an exact set comparison on ``DisplayIdentity``. A setup
/// with one extra monitor is *not* a partial match: guessing would place
/// windows on a screen the user never approved, which is worse than doing
/// nothing and saying so. Displays listed in ``Configuration/ignoredDisplays``
/// are removed before comparison — that is how virtual displays are kept from
/// swapping the profile.
public struct DefaultProfileResolver: ProfileResolver {

    /// Why no profile could be selected. Carries enough detail for `watch` to
    /// print an actionable message instead of "kein Profil".
    public enum Problem: Error, Hashable, Sendable {
        /// No profile's fingerprint equals the current setup.
        case noMatchingProfile(current: Set<DisplayIdentity>, unknownIdentities: Set<DisplayIdentity>)
        /// A profile references a display alias the configuration does not declare.
        case unknownAlias(ProfileID, DisplayAlias)
    }

    public init() {}

    public func activeProfile(for fingerprint: SetupFingerprint, in configuration: Configuration) -> Profile? {
        switch matchingProfile(for: fingerprint, in: configuration) {
        case let .success(profile): return profile
        case .failure: return nil
        }
    }

    /// Same as ``activeProfile(for:in:)`` but explains the failure.
    public func matchingProfile(
        for fingerprint: SetupFingerprint,
        in configuration: Configuration
    ) -> Result<Profile, Problem> {
        let identitiesByAlias = Dictionary(
            configuration.displays.map { ($0.alias, $0.identity) },
            uniquingKeysWith: { first, _ in first }
        )

        for profile in configuration.profiles {
            var identities: Set<DisplayIdentity> = []
            var missingAlias: DisplayAlias?

            for alias in profile.fingerprint.normalized {
                guard let identity = identitiesByAlias[alias] else {
                    missingAlias = alias
                    break
                }
                identities.insert(identity)
            }

            if let missingAlias {
                return .failure(.unknownAlias(profile.id, missingAlias))
            }
            if identities == fingerprint.displays {
                return .success(profile)
            }
        }

        let known = Set(configuration.displays.map(\.identity))
        return .failure(
            .noMatchingProfile(
                current: fingerprint.displays,
                unknownIdentities: fingerprint.displays.subtracting(known)
            )
        )
    }
}
