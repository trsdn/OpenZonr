import Foundation

/// Stable identifier of a ``PlacementRule``.
public struct RuleID: StringIdentifier {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// One "match → action" entry: which windows, and where they go.
///
/// Evaluation order is by ``priority`` descending, ties broken by the order in
/// the configuration file. The **first matching rule wins**; later rules are not
/// evaluated for the same window. Specific rules therefore need a higher
/// priority than generic ones — an Outlook compose rule must outrank the plain
/// "Outlook → communication" rule, otherwise it can never fire.
public struct PlacementRule: Codable, Hashable, Sendable, Identifiable {
    public var id: RuleID
    /// Label shown in the UI; also what appears in the placement log.
    public var name: String
    /// Disabled rules are kept in the file but skipped during evaluation.
    public var enabled: Bool
    /// Higher values are evaluated first.
    public var priority: Int
    /// Criteria the window must satisfy.
    public var match: WindowMatch
    /// What to do with a matching window.
    public var action: PlacementAction

    public init(
        id: RuleID,
        name: String,
        enabled: Bool = true,
        priority: Int = 0,
        match: WindowMatch,
        action: PlacementAction
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.priority = priority
        self.match = match
        self.action = action
    }
}
