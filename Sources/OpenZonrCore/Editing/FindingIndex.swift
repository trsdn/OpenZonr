import Foundation

/// A ``ValidationReport`` addressed by document path instead of read top to
/// bottom.
///
/// The issue asks for errors *at the affected field* rather than in a list at
/// the edge of the window, and that is only possible if a view can ask "is
/// anything wrong with `rules[outlook].match.titlePattern`?" in constant time.
/// This index is that question, and it is the reason ``ValidationFinding``
/// carries a ``ConfigurationPath`` at all.
///
/// Two kinds of lookup exist, and the difference matters:
///
/// - ``findings(at:)`` — findings for exactly this field. A text field shows
///   these under itself.
/// - ``findings(under:)`` — findings for this field *and everything below it*.
///   A row in the rule list shows the worst of these as a badge, so a problem
///   deep inside a collapsed rule is still visible from the outside.
public struct FindingIndex: Hashable, Sendable {

    /// Findings for one exact path, keyed by the path's components.
    private var exact: [[ConfigurationPath.Component]: [ValidationFinding]]

    /// Every path that carries a finding, kept as component arrays.
    ///
    /// Prefix matching runs over components rather than over the rendered
    /// string, because `rules[a]` is a string prefix of `rules[ab]` while being
    /// an entirely unrelated rule.
    private var paths: [[ConfigurationPath.Component]]

    public init(_ report: ValidationReport = ValidationReport()) {
        var exact: [[ConfigurationPath.Component]: [ValidationFinding]] = [:]
        for finding in report.sorted().findings {
            exact[finding.path.components, default: []].append(finding)
        }
        self.exact = exact
        self.paths = Array(exact.keys)
    }

    public var isEmpty: Bool { exact.isEmpty }

    /// Findings reported for exactly `path`.
    public func findings(at path: ConfigurationPath) -> [ValidationFinding] {
        exact[path.components] ?? []
    }

    /// Findings reported for `path` or anything nested inside it.
    public func findings(under path: ConfigurationPath) -> [ValidationFinding] {
        let prefix = path.components
        return paths
            .filter { candidate in
                candidate.count >= prefix.count && Array(candidate.prefix(prefix.count)) == prefix
            }
            .flatMap { exact[$0] ?? [] }
            .sorted { lhs, rhs in
                if lhs.severity != rhs.severity { return lhs.severity == .error }
                if lhs.path.description != rhs.path.description {
                    return lhs.path.description < rhs.path.description
                }
                return lhs.code.rawValue < rhs.code.rawValue
            }
    }

    /// Findings that none of `paths` covers.
    ///
    /// The editor shows fields it knows about; a finding it cannot place must
    /// still reach the user. The uniqueness checks are the concrete case: they
    /// report at `rules[2].id`, addressed by position, because with two rules of
    /// the same identifier an identifier is exactly what cannot address them.
    /// Dropping such a finding because no field claimed it would hide the one
    /// problem the editor itself cannot fix.
    public func findings(notUnder paths: [ConfigurationPath]) -> [ValidationFinding] {
        let prefixes = paths.map(\.components)
        return self.paths
            .filter { candidate in
                !prefixes.contains { prefix in
                    candidate.count >= prefix.count && Array(candidate.prefix(prefix.count)) == prefix
                }
            }
            .flatMap { exact[$0] ?? [] }
            .sorted { lhs, rhs in
                if lhs.severity != rhs.severity { return lhs.severity == .error }
                if lhs.path.description != rhs.path.description {
                    return lhs.path.description < rhs.path.description
                }
                return lhs.code.rawValue < rhs.code.rawValue
            }
    }

    /// The worst severity reported for exactly `path`, or `nil` when it is clean.
    public func severity(at path: ConfigurationPath) -> ValidationSeverity? {
        Self.worst(findings(at: path))
    }

    /// The worst severity reported for `path` or anything inside it.
    public func severity(under path: ConfigurationPath) -> ValidationSeverity? {
        Self.worst(findings(under: path))
    }

    private static func worst(_ findings: [ValidationFinding]) -> ValidationSeverity? {
        if findings.contains(where: { $0.severity == .error }) { return .error }
        return findings.isEmpty ? nil : .warning
    }
}

/// The paths the editor needs, written once.
///
/// Every view that shows a field builds its path through these helpers rather
/// than assembling components by hand. If a check ever moves its finding to a
/// different path, one place here has to follow instead of a dozen views
/// silently showing nothing.
extension ConfigurationPath {

    public static func rule(_ id: RuleID) -> ConfigurationPath {
        ConfigurationPath().element("rules", id)
    }

    public static func ruleMatch(_ id: RuleID) -> ConfigurationPath {
        rule(id).field("match")
    }

    public static func ruleAction(_ id: RuleID) -> ConfigurationPath {
        rule(id).field("action")
    }

    public static func role(_ id: RoleID) -> ConfigurationPath {
        ConfigurationPath().element("roles", id)
    }

    public static func profile(_ id: ProfileID) -> ConfigurationPath {
        ConfigurationPath().element("profiles", id)
    }

    public static func roleBinding(_ profile: ProfileID, at index: Int) -> ConfigurationPath {
        Self.profile(profile).element("roleBindings", at: index)
    }

    public static func profileFallback(_ profile: ProfileID) -> ConfigurationPath {
        Self.profile(profile).field("fallback")
    }

    public static func display(_ alias: DisplayAlias) -> ConfigurationPath {
        ConfigurationPath().element("displays", alias)
    }

    public static func layout(_ layout: LayoutID, display: DisplayAlias) -> ConfigurationPath {
        Self.display(display).element("layouts", layout)
    }

    public static func zone(_ zone: ZoneID, layout: LayoutID, display: DisplayAlias) -> ConfigurationPath {
        Self.layout(layout, display: display).element("zones", zone)
    }

    public static func zoneFrame(_ zone: ZoneID, layout: LayoutID, display: DisplayAlias) -> ConfigurationPath {
        Self.zone(zone, layout: layout, display: display).field("frame")
    }
}
