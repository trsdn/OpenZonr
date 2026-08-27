import Foundation

/// Runs all configuration checks and returns one deterministic report.
public struct ConfigurationValidator: Sendable {

    public let checks: [any ConfigurationCheck]

    /// Checks run in a fixed order: identity, references, geometry, policy,
    /// regular expressions, profile selection, then rule hygiene.
    public init() {
        self.init(checks: [
            IdentifierUniquenessCheck(),
            ReferenceIntegrityCheck(),
            GeometryCheck(),
            PolicyCheck(),
            PatternCheck(),
            ProfileFingerprintCheck(),
            RuleHygieneCheck()
        ])
    }

    public init(checks: [any ConfigurationCheck]) {
        self.checks = checks
    }

    public func validate(_ configuration: Configuration) -> ValidationReport {
        var report = ValidationReport()
        for check in checks {
            report.append(contentsOf: check.findings(in: configuration))
        }
        return report.sorted()
    }
}
