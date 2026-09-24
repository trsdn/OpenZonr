import Foundation

/// Builds the dry-run line for the rule editor, as text.
///
/// Deliberately pure computation in Core, so the punctuation, the order of the
/// details, and the "Not checked: …" caption are testable without a SwiftUI
/// preview list. The editor just binds the text to a label, nothing more.
public enum DryRunPreviewFormatter {

    /// The assembled text plus the metadata the surface needs for the
    /// "conditional"/"unverified" caption.
    public struct Line: Hashable, Sendable {
        /// The line itself, as it appears in the editor.
        public var headline: String
        /// Unverified criteria, named. Empty means measurement, not guesswork.
        public var caveats: [String]
        /// `true` when this was computed without a real window.
        public var isConditional: Bool

        public init(headline: String, caveats: [String], isConditional: Bool) {
            self.headline = headline
            self.caveats = caveats
            self.isConditional = isConditional
        }
    }

    /// Builds the line for a result from ``DryRunPreview/evaluate(window:configuration:snapshots:)``
    /// or ``DryRunPreview/evaluate(bundleIdentifier:configuration:snapshots:)``.
    ///
    /// - Parameter subject: human-friendly name of the window or app ("This
    ///   window", "Outlook"). Only for the introductory phrasing; no meaning
    ///   for the evaluation itself.
    /// - Parameter configuration: used to resolve display and zone names from
    ///   aliases and IDs. When an alias is unknown, the raw value appears in
    ///   the line instead — still the truth, just less pretty.
    public static func line(
        for result: DryRunPreview.Result,
        subject: String,
        configuration: Configuration
    ) -> Line {
        switch result {
        case .noMatch:
            return Line(
                headline: L.string("dryRunPreview.noMatch", "%@ — no rule applies.", subject),
                caveats: [],
                isConditional: false
            )

        case let .matches(match):
            return line(for: match, subject: subject, configuration: configuration, note: nil)

        case let .unresolvable(match, failure):
            // The rule stands, the resolution fails. That is an honest
            // report, not a guess: the line names the rule and says why it
            // does not yield a frame this time.
            let reason = reasonText(from: failure)
            return line(for: match, subject: subject, configuration: configuration, note: reason)
        }
    }

    private static func line(
        for match: DryRunPreview.Match,
        subject: String,
        configuration: Configuration,
        note: String?
    ) -> Line {
        var parts: [String] = []
        parts.append(subject)

        if let placement = match.placement {
            let zoneName = zoneName(for: placement, configuration: configuration)
            let displayName = displayName(for: placement.display, configuration: configuration)
            let size = String(
                format: "%.0f × %.0f pt",
                placement.frame.width,
                placement.frame.height
            )
            parts.append(L.string("dryRunPreview.wouldGoTo", "would go to %@ on %@", zoneName, displayName))
            parts.append(
                L.string(
                    "dryRunPreview.rulePriority",
                    "rule \u{201c}%@\u{201d} (priority %lld)",
                    match.rule.name, match.rule.priority
                )
            )
            parts.append(size)
        } else {
            // No frame: name only the rule and the role — invent nothing further.
            let roleText = roleName(for: match.role, configuration: configuration)
            parts.append(L.string("dryRunPreview.wouldGoToRole", "would go into role \u{201c}%@\u{201d}", roleText))
            parts.append(
                L.string(
                    "dryRunPreview.rulePriority",
                    "rule \u{201c}%@\u{201d} (priority %lld)",
                    match.rule.name, match.rule.priority
                )
            )
            if let note {
                parts.append(note)
            }
        }

        let headline = parts.joined(separator: " · ")

        let caveats: [String]
        if match.isConditional {
            caveats = match.report.undecidable.map(caveatText(for:))
        } else {
            caveats = []
        }

        return Line(
            headline: headline,
            caveats: caveats,
            isConditional: match.isConditional
        )
    }

    // MARK: - Pulling names from the configuration

    private static func zoneName(for placement: ResolvedPlacement, configuration: Configuration) -> String {
        for descriptor in configuration.displays where descriptor.alias == placement.display {
            for layout in descriptor.layouts {
                if let zone = layout.zones.first(where: { $0.id == placement.zone }) {
                    return zone.name
                }
            }
        }
        return placement.zone.rawValue
    }

    private static func displayName(for alias: DisplayAlias, configuration: Configuration) -> String {
        configuration.displays.first { $0.alias == alias }?.displayName ?? alias.rawValue
    }

    private static func roleName(for id: RoleID, configuration: Configuration) -> String {
        configuration.roles.first { $0.id == id }?.name ?? id.rawValue
    }

    private static func reasonText(from failure: ZoneResolutionFailure) -> String {
        switch failure {
        case let .unknownDisplay(alias):
            return L.string("dryRunPreview.reason.unknownDisplay", "unknown display %@", alias.rawValue)
        case let .unknownLayout(layoutID, display):
            return L.string(
                "dryRunPreview.reason.unknownLayout",
                "unknown layout %@ for %@",
                layoutID.rawValue, display.rawValue
            )
        case let .unknownZone(zoneID, layout, display):
            return L.string(
                "dryRunPreview.reason.unknownZone",
                "unknown zone %@ in %@ on %@",
                zoneID.rawValue, layout.rawValue, display.rawValue
            )
        case let .missingVisibleFrame(alias) where alias.rawValue.isEmpty:
            return L.string(
                "dryRunPreview.reason.noActiveProfile",
                "no active profile for the connected screens"
            )
        case let .missingVisibleFrame(alias):
            return L.string(
                "dryRunPreview.reason.displayNotConnected",
                "display %@ is not currently connected",
                alias.rawValue
            )
        case let .invalidShare(share):
            return L.string(
                "dryRunPreview.reason.invalidShare",
                "invalid zone share (%lld slots, index %lld)",
                share.slots, share.slotIndex
            )
        }
    }

    private static func caveatText(for criterion: RuleCriteria.Criterion) -> String {
        switch criterion {
        case let .bundleIdentifier(value):
            return L.string("dryRunPreview.caveat.bundleIdentifier", "bundle identifier (%@)", value)
        case let .title(pattern):
            return L.string("dryRunPreview.caveat.title", "window title (pattern %@)", pattern)
        case let .roles(list):
            return L.string(
                "dryRunPreview.caveat.roles", "role (AX): %@", list.joined(separator: ", ")
            )
        case let .subroles(list):
            return L.string(
                "dryRunPreview.caveat.subroles", "subrole (AX): %@", list.joined(separator: ", ")
            )
        case let .minimumSize(size):
            let sizeText = String(format: "%.0f × %.0f pt", size.width, size.height)
            return L.string("dryRunPreview.caveat.minimumSize", "minimum size %@", sizeText)
        case let .maximumSize(size):
            let sizeText = String(format: "%.0f × %.0f pt", size.width, size.height)
            return L.string("dryRunPreview.caveat.maximumSize", "maximum size %@", sizeText)
        case let .aspectRatio(range):
            let rangeText = String(format: "%.2f – %.2f", range.minimum, range.maximum)
            return L.string("dryRunPreview.caveat.aspectRatio", "aspect ratio %@", rangeText)
        case let .onlyFirstWindowAfterLaunch(value):
            return value
                ? L.string(
                    "dryRunPreview.caveat.onlyFirstWindow",
                    "only the first window after the app launches"
                )
                : L.string(
                    "dryRunPreview.caveat.everyWindow",
                    "every window (not only the first)"
                )
        }
    }
}
