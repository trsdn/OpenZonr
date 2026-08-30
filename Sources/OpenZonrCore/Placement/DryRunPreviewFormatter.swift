import Foundation

/// Baut die Dry-Run-Zeile für den Regel-Editor als Text.
///
/// Absichtlich pure Rechnung in Core, damit die Zeichensetzung, die Reihenfolge
/// der Angaben und die Beschriftung „Nicht geprüft: …" ohne
/// SwiftUI-Vorschauliste testbar sind. Der Editor bindet den Text an ein
/// Label und mehr nicht.
public enum DryRunPreviewFormatter {

    /// Der zusammengesetzte Text plus Metadaten, die die Oberfläche für die
    /// Beschriftung („bedingt", „ungeprüft") braucht.
    public struct Line: Hashable, Sendable {
        /// Die Zeile selbst, wie sie im Editor steht.
        public var headline: String
        /// Nicht geprüfte Kriterien, benannt. Leer heißt: Messung, nicht
        /// Vermutung.
        public var caveats: [String]
        /// `true`, wenn ohne echtes Fenster gerechnet wurde.
        public var isConditional: Bool

        public init(headline: String, caveats: [String], isConditional: Bool) {
            self.headline = headline
            self.caveats = caveats
            self.isConditional = isConditional
        }
    }

    /// Erzeugt die Zeile für ein Ergebnis von ``DryRunPreview/evaluate(window:configuration:snapshots:)``
    /// bzw. ``DryRunPreview/evaluate(bundleIdentifier:configuration:snapshots:)``.
    ///
    /// - Parameter subject: menschenfreundliche Bezeichnung des Fensters oder
    ///   der App („Dieses Fenster", „Outlook"). Nur für die einleitende
    ///   Formulierung; keine Bedeutung für die Auswertung.
    /// - Parameter configuration: wird für die Auflösung von Bildschirm- und
    ///   Zonenamen aus Aliasen und IDs herangezogen. Wenn ein Alias unbekannt
    ///   ist, steht der Rohwert in der Zeile — das ist immer noch die
    ///   Wahrheit, nur weniger schön.
    public static func line(
        for result: DryRunPreview.Result,
        subject: String,
        configuration: Configuration
    ) -> Line {
        switch result {
        case .noMatch:
            return Line(
                headline: "\(subject) — keine Regel greift.",
                caveats: [],
                isConditional: false
            )

        case let .matches(match):
            return line(for: match, subject: subject, configuration: configuration, note: nil)

        case let .unresolvable(match, failure):
            // Die Regel steht, die Auflösung scheitert. Das ist eine ehrliche
            // Auskunft und keine Vermutung: die Zeile nennt die Regel und
            // sagt, warum sie diesmal keinen Rahmen ergibt.
            let grund = grundText(from: failure)
            return line(for: match, subject: subject, configuration: configuration, note: grund)
        }
    }

    private static func line(
        for match: DryRunPreview.Match,
        subject: String,
        configuration: Configuration,
        note: String?
    ) -> Line {
        var teile: [String] = []
        teile.append(subject)

        if let placement = match.placement {
            let zoneName = zoneName(for: placement, configuration: configuration)
            let displayName = displayName(for: placement.display, configuration: configuration)
            let size = String(
                format: "%.0f × %.0f pt",
                placement.frame.width,
                placement.frame.height
            )
            teile.append("ginge nach \(zoneName) auf \(displayName)")
            teile.append("Regel „\(match.rule.name)\" (Priorität \(match.rule.priority))")
            teile.append(size)
        } else {
            // Kein Rahmen: nur Regel und Rolle nennen — nichts weiter erfinden.
            let rolle = roleName(for: match.role, configuration: configuration)
            teile.append("ginge in Rolle „\(rolle)\"")
            teile.append("Regel „\(match.rule.name)\" (Priorität \(match.rule.priority))")
            if let note {
                teile.append(note)
            }
        }

        let headline = teile.joined(separator: " · ")

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

    // MARK: - Namen aus der Konfiguration ziehen

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

    private static func grundText(from failure: ZoneResolutionFailure) -> String {
        switch failure {
        case let .unknownDisplay(alias):
            return "unbekannter Bildschirm \(alias.rawValue)"
        case let .unknownLayout(layoutID, display):
            return "unbekanntes Layout \(layoutID.rawValue) für \(display.rawValue)"
        case let .unknownZone(zoneID, layout, display):
            return "unbekannte Zone \(zoneID.rawValue) in \(layout.rawValue) auf \(display.rawValue)"
        case let .missingVisibleFrame(alias) where alias.rawValue.isEmpty:
            return "kein aktives Profil für die angeschlossenen Bildschirme"
        case let .missingVisibleFrame(alias):
            return "Bildschirm \(alias.rawValue) ist gerade nicht angeschlossen"
        case let .invalidShare(share):
            return "ungültige Zonenteilung (\(share.slots) Slots, Index \(share.slotIndex))"
        }
    }

    private static func caveatText(for criterion: RuleCriteria.Criterion) -> String {
        switch criterion {
        case let .bundleIdentifier(value):
            return "Bundle-Kennung (\(value))"
        case let .title(pattern):
            return "Fenstertitel (Muster \(pattern))"
        case let .roles(list):
            return "Rolle (AX): \(list.joined(separator: ", "))"
        case let .subroles(list):
            return "Subrolle (AX): \(list.joined(separator: ", "))"
        case let .minimumSize(size):
            return String(format: "Mindestgröße %.0f × %.0f pt", size.width, size.height)
        case let .maximumSize(size):
            return String(format: "Höchstgröße %.0f × %.0f pt", size.width, size.height)
        case let .aspectRatio(range):
            return String(format: "Seitenverhältnis %.2f – %.2f", range.minimum, range.maximum)
        case let .onlyFirstWindowAfterLaunch(value):
            return value
                ? "nur das erste Fenster nach dem Start der App"
                : "jedes Fenster (nicht nur das erste)"
        }
    }
}
