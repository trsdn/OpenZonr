import Foundation

/// The complete result of validating one configuration.
///
/// The report deliberately carries *all* findings rather than the first one.
/// A user who fixes one reported problem, reruns and gets the next one is being
/// made to do the tool's work; a configuration file is small enough to check
/// exhaustively in one pass.
public struct ValidationReport: Hashable, Sendable {

    /// Every finding, ordered as produced by ``ConfigurationValidator``:
    /// errors before warnings, then by document path.
    public private(set) var findings: [ValidationFinding]

    public init(findings: [ValidationFinding] = []) {
        self.findings = findings
    }

    /// Findings that make the configuration unusable.
    public var errors: [ValidationFinding] {
        findings.filter { $0.severity == .error }
    }

    /// Findings that are merely suspicious.
    public var warnings: [ValidationFinding] {
        findings.filter { $0.severity == .warning }
    }

    /// `true` when the configuration can be used, warnings notwithstanding.
    public var isUsable: Bool {
        !findings.contains { $0.severity == .error }
    }

    /// `true` when nothing at all was found.
    public var isEmpty: Bool { findings.isEmpty }

    public mutating func append(_ finding: ValidationFinding) {
        findings.append(finding)
    }

    public mutating func append(contentsOf newFindings: [ValidationFinding]) {
        findings.append(contentsOf: newFindings)
    }

    /// `true` when at least one finding of `code` is present.
    public func contains(_ code: ValidationCode) -> Bool {
        findings.contains { $0.code == code }
    }

    /// All findings of one kind, for targeted inspection.
    public func findings(of code: ValidationCode) -> [ValidationFinding] {
        findings.filter { $0.code == code }
    }

    /// `true` when a finding of `code` was reported at exactly `path`.
    ///
    /// This is what tests assert on: the code alone would not prove that the
    /// report points at the right place in the document.
    public func contains(_ code: ValidationCode, at path: String) -> Bool {
        findings.contains { $0.code == code && $0.path.description == path }
    }

    /// Returns a report whose findings are in the canonical order: errors
    /// first, then warnings, each group sorted by document path and code.
    ///
    /// Stable ordering matters because the report is printed and diffed.
    public func sorted() -> ValidationReport {
        ValidationReport(
            findings: findings.sorted { lhs, rhs in
                if lhs.severity != rhs.severity {
                    return lhs.severity == .error
                }
                if lhs.path.description != rhs.path.description {
                    return lhs.path.description < rhs.path.description
                }
                return lhs.code.rawValue < rhs.code.rawValue
            }
        )
    }
}

/// One aspect of configuration validation.
///
/// Checks are split by topic so each one stays small enough to read in full,
/// and so a new rule is added by writing a new check rather than by extending a
/// single growing function.
public protocol ConfigurationCheck: Sendable {
    /// Returns every problem this check finds. Never throws and never stops at
    /// the first problem.
    func findings(in configuration: Configuration) -> [ValidationFinding]
}
