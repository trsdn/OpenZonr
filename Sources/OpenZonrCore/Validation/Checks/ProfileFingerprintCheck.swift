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
                    message: "Der Profil-Fingerprint muss mindestens ein Display enthalten."
                ))
            }

            for (index, alias) in profile.fingerprint.displays.enumerated() where !displayAliases.contains(alias) {
                findings.append(ValidationFinding(
                    code: .unknownDisplayInFingerprint,
                    path: profilePath.field("fingerprint").element("displays", at: index),
                    message: "Der Profil-Fingerprint verweist auf das unbekannte Display \(alias)."
                ))
            }

            let normalized = profile.fingerprint.normalized
            if let firstProfile = firstProfileByFingerprint[normalized] {
                findings.append(ValidationFinding(
                    code: .duplicateProfileFingerprint,
                    path: profilePath.field("fingerprint"),
                    message: "Der Profil-Fingerprint kollidiert mit Profil \(firstProfile)."
                ))
            } else {
                firstProfileByFingerprint[normalized] = profile.id
            }
        }

        return findings
    }
}
