import Foundation

public struct ProfileFingerprintCheck: ConfigurationCheck {

    public init() {}

    public func findings(in configuration: Configuration) -> [ValidationFinding] {
        let displayAliases = Set(configuration.displays.map(\.alias))
        var firstProfileByFingerprint: [Set<DisplayAlias>: ProfileID] = [:]
        var findings: [ValidationFinding] = []

        for profile in configuration.profiles {
            let profilePath = ConfigurationPath().element("profiles", profile.id)
            if profile.fingerprint.displays.isEmpty {
                findings.append(ValidationFinding(
                    code: .emptyProfileFingerprint,
                    path: profilePath.field("fingerprint").field("displays"),
                    message: L.string("profileFingerprint.empty", "A profile fingerprint must contain at least one display.")
                ))
            }

            for (index, alias) in profile.fingerprint.displays.enumerated() where !displayAliases.contains(alias) {
                findings.append(ValidationFinding(
                    code: .unknownDisplayInFingerprint,
                    path: profilePath.field("fingerprint").element("displays", at: index),
                    message: L.string(
                        "profileFingerprint.unknownDisplay",
                        "The profile fingerprint refers to the unknown display %@.",
                        "\(alias)"
                    )
                ))
            }

            let normalized = profile.fingerprint.normalized
            if let firstProfile = firstProfileByFingerprint[normalized] {
                findings.append(ValidationFinding(
                    code: .duplicateProfileFingerprint,
                    path: profilePath.field("fingerprint"),
                    message: L.string(
                        "profileFingerprint.duplicate",
                        "This fingerprint collides with profile %@.",
                        "\(firstProfile)"
                    )
                ))
            } else {
                firstProfileByFingerprint[normalized] = profile.id
            }
        }

        return findings
    }
}
