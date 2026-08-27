import Foundation

public struct IdentifierUniquenessCheck: ConfigurationCheck {

    public init() {}

    public func findings(in configuration: Configuration) -> [ValidationFinding] {
        var findings: [ValidationFinding] = []

        findings.append(contentsOf: duplicateFindings(
            values: configuration.displays.map(\.alias),
            code: .duplicateDisplayAlias,
            path: { ConfigurationPath().element("displays", at: $0).field("alias") },
            message: { "Der Display-Alias \($0) ist mehrfach vergeben." }
        ))
        findings.append(contentsOf: duplicateFindings(
            values: configuration.roles.map(\.id),
            code: .duplicateRoleID,
            path: { ConfigurationPath().element("roles", at: $0).field("id") },
            message: { "Die Rollen-ID \($0) ist mehrfach vergeben." }
        ))
        findings.append(contentsOf: duplicateFindings(
            values: configuration.rules.map(\.id),
            code: .duplicateRuleID,
            path: { ConfigurationPath().element("rules", at: $0).field("id") },
            message: { "Die Regel-ID \($0) ist mehrfach vergeben." }
        ))
        findings.append(contentsOf: duplicateFindings(
            values: configuration.profiles.map(\.id),
            code: .duplicateProfileID,
            path: { ConfigurationPath().element("profiles", at: $0).field("id") },
            message: { "Die Profil-ID \($0) ist mehrfach vergeben." }
        ))

        for display in configuration.displays {
            findings.append(contentsOf: duplicateFindings(
                values: display.layouts.map(\.id),
                code: .duplicateLayoutID,
                path: { ConfigurationPath().element("displays", display.alias).element("layouts", at: $0).field("id") },
                message: { "Das Layout \($0) ist für Display \(display.alias) mehrfach vergeben." }
            ))

            for layout in display.layouts {
                findings.append(contentsOf: duplicateFindings(
                    values: layout.zones.map(\.id),
                    code: .duplicateZoneID,
                    path: { ConfigurationPath().element("displays", display.alias).element("layouts", layout.id).element("zones", at: $0).field("id") },
                    message: { "Die Zone \($0) ist im Layout \(layout.id) mehrfach vergeben." }
                ))
            }
        }

        return findings
    }

    private func duplicateFindings<ID: Hashable & CustomStringConvertible>(
        values: [ID],
        code: ValidationCode,
        path: (Int) -> ConfigurationPath,
        message: (ID) -> String
    ) -> [ValidationFinding] {
        var seen: Set<ID> = []
        var findings: [ValidationFinding] = []

        for (index, value) in values.enumerated() {
            if seen.contains(value) {
                findings.append(ValidationFinding(code: code, path: path(index), message: message(value)))
            } else {
                seen.insert(value)
            }
        }

        return findings
    }
}
