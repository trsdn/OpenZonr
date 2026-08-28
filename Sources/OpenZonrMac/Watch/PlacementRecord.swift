import Foundation
import OpenZonrCore

/// One thing OpenZonr did — or deliberately did not do — to one window.
///
/// The watch log answers "why did nothing happen?" in full prose, which is the
/// right answer for a terminal and the wrong one for a menu. This is the same
/// information reduced to a row: what, where, and how well it went.
///
/// Only decisions that reached a rule are recorded. Every window of every
/// watched application passes through the filter, and listing the hundreds that
/// were never candidates would bury the handful that were.
public struct PlacementRecord: Sendable, Identifiable, Hashable {

    public enum Outcome: Sendable, Hashable {
        /// The window ended up within tolerance, after `attempts` writes.
        case placed(attempts: Int, deviation: Double?)
        /// The application would not take the frame.
        case rejected(actual: WindowFrame, attempts: Int)
        /// The rule asked for `mode: suggest`, which has no overlay yet.
        case suggested
        /// A rule matched but the placement was not carried out, for the stated
        /// reason.
        case skipped(String)
        /// `--dry-run`, or the app's pause switch: decided, not executed.
        case notExecuted(String)
    }

    public let id: UUID
    public let date: Date
    public let applicationName: String
    public let bundleIdentifier: String?
    public let windowTitle: String?
    public let ruleID: RuleID?
    public let display: DisplayAlias?
    public let zone: ZoneID?
    public let outcome: Outcome

    public init(
        id: UUID = UUID(),
        date: Date = Date(),
        applicationName: String,
        bundleIdentifier: String?,
        windowTitle: String?,
        ruleID: RuleID?,
        display: DisplayAlias?,
        zone: ZoneID?,
        outcome: Outcome
    ) {
        self.id = id
        self.date = date
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.windowTitle = windowTitle
        self.ruleID = ruleID
        self.display = display
        self.zone = zone
        self.outcome = outcome
    }

    /// Where the window was sent, as `display/zone`, when there was a target.
    public var target: String? {
        guard let display, let zone else { return nil }
        return "\(display)/\(zone)"
    }

    /// One short sentence for a menu row.
    public var summary: String {
        switch outcome {
        case let .placed(attempts, deviation):
            let deviationText = deviation.map { " (\(format($0)) pt)" } ?? ""
            return "platziert nach \(attempts) Versuch\(attempts == 1 ? "" : "en")\(deviationText)"
        case let .rejected(_, attempts):
            return "von der App abgelehnt (\(attempts) Versuche)"
        case .suggested:
            return "nur vorgeschlagen"
        case let .skipped(reason):
            return reason
        case let .notExecuted(reason):
            return reason
        }
    }

    /// Whether this row is a success, a refusal, or merely informational.
    public var isFailure: Bool {
        if case .rejected = outcome { return true }
        return false
    }

    public var isSuccess: Bool {
        if case .placed = outcome { return true }
        return false
    }
}
