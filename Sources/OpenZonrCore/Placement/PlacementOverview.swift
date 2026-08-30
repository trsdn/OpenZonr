import Foundation

/// „Welche Regel landet in welcher Zone?" — die Antwort, die die Übersicht aus
/// Issue #19 zeichnet.
///
/// Der Editor hat sonst drei Reiter, die die Datenmodellstruktur spiegeln:
/// Regeln, Rollen & Profile, Zonen. Wer wissen will, wohin *diese App* im
/// Ergebnis geht, muss die Kette Regel → Rolle → Bindung → Zone im Kopf
/// zusammensetzen. Diese Funktion setzt sie einmal zusammen und gibt eine
/// Datenstruktur zurück, die die Übersicht direkt zeichnen kann.
///
/// Absichtlich pure Rechnung in Core: die Übersicht ist ein Bild, ihr
/// Zustandekommen ist Rechnung. Der Test darüber muss nicht die
/// SwiftUI-Zeichenoberfläche prüfen, sondern die Aufteilung selbst.
public enum PlacementOverview {

    /// Ein Eintrag pro Regel — im Wesentlichen ihr Name, ihre Bundle-Kennung
    /// und die Priorität. Alles, was die Übersicht als Label braucht.
    public struct RuleLabel: Hashable, Sendable {
        public var ruleID: RuleID
        public var name: String
        public var bundleIdentifier: String?
        public var priority: Int
        public var enabled: Bool

        public init(
            ruleID: RuleID,
            name: String,
            bundleIdentifier: String?,
            priority: Int,
            enabled: Bool
        ) {
            self.ruleID = ruleID
            self.name = name
            self.bundleIdentifier = bundleIdentifier
            self.priority = priority
            self.enabled = enabled
        }
    }

    /// Der Inhalt einer Zone: das Layout-Feld, das relative Rechteck und die
    /// Regeln, die dorthin führen.
    public struct ZoneOccupancy: Hashable, Sendable {
        public var display: DisplayAlias
        public var zone: Zone
        public var rules: [RuleLabel]
        /// `true`, wenn keine einzige Regel in dieser Zone landet — das ist
        /// die Beobachtung, die die Übersicht aus Issue #19 sichtbar machen
        /// soll (in der realen Konfiguration betrifft das `u28e590-full`).
        public var isEmpty: Bool { rules.isEmpty }

        public init(display: DisplayAlias, zone: Zone, rules: [RuleLabel]) {
            self.display = display
            self.zone = zone
            self.rules = rules
        }
    }

    /// Ein Bildschirm mit seinem aktiven Layout und dessen Zonen.
    public struct DisplayPanel: Hashable, Sendable {
        public var descriptor: DisplayDescriptor
        public var layout: Layout
        public var zones: [ZoneOccupancy]
        /// Die Regel, die die Auffangbindung des Profils nutzen würde.
        /// Nicht dieselbe Sache wie „Regeln landen in dieser Zone"; sie steht
        /// hier separat, damit die Übersicht darauf hinweisen kann, wo
        /// unerkannte Fenster hingehen.
        public var fallbackZone: ZoneID?

        public init(
            descriptor: DisplayDescriptor,
            layout: Layout,
            zones: [ZoneOccupancy],
            fallbackZone: ZoneID?
        ) {
            self.descriptor = descriptor
            self.layout = layout
            self.zones = zones
            self.fallbackZone = fallbackZone
        }
    }

    /// Baut die Übersicht für ein Profil.
    ///
    /// Ein Bildschirm, der im Profil nicht auftaucht, taucht auch in der
    /// Übersicht nicht auf — das Profil beschreibt genau eine
    /// Bildschirmanordnung.
    ///
    /// Regeln ohne Bundle-Kennung erscheinen mit „(jede App)" als
    /// Kennung — das ist die Auffangregel, die die Zeichnung sonst
    /// unterschlagen würde.
    ///
    /// Deaktivierte Regeln werden mit `enabled: false` mitgeliefert, damit
    /// die Übersicht sie ausgegraut zeigen kann — sie wegzulassen hieße,
    /// dem Nutzer eine Konfiguration zu zeigen, die es so nicht gibt.
    public static func build(
        for profile: Profile,
        configuration: Configuration
    ) -> [DisplayPanel] {
        let bindingsByRole: [RoleID: RoleBinding] = Dictionary(
            uniqueKeysWithValues: profile.roleBindings.map { ($0.role, $0) }
        )

        // Regeln je Zone/Display einsammeln. Bewusst in Auswertungsreihenfolge:
        // die Zeichnung listet oben, was zuerst greift.
        let sortedRules = configuration.rules.sorted { lhs, rhs in
            if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
            return false
        }

        var perDisplayZone: [DisplayAlias: [ZoneID: [RuleLabel]]] = [:]
        for rule in sortedRules {
            guard let binding = bindingsByRole[rule.action.role] else {
                // Rolle nicht im Profil gebunden: die Auffangregel würde
                // greifen. Zeichnen wir die Regel in die Fallback-Zone,
                // dann bekommt die Übersicht sichtbar mit, was sonst nur die
                // Kette „Regel → unbekannte Rolle → Auffang" hergibt.
                let fallback = profile.fallback
                perDisplayZone[fallback.display, default: [:]][fallback.zone, default: []]
                    .append(label(from: rule))
                continue
            }
            perDisplayZone[binding.display, default: [:]][binding.zone, default: []]
                .append(label(from: rule))
        }

        var panels: [DisplayPanel] = []
        for descriptor in configuration.displays {
            let layoutID = profile.layouts[descriptor.alias] ?? descriptor.defaultLayoutID
            guard let layout = descriptor.layouts.first(where: { $0.id == layoutID }) else {
                continue
            }
            let zoneRules = perDisplayZone[descriptor.alias] ?? [:]
            let zones = layout.zones.map { zone in
                ZoneOccupancy(
                    display: descriptor.alias,
                    zone: zone,
                    rules: zoneRules[zone.id] ?? []
                )
            }
            let fallback = profile.fallback.display == descriptor.alias
                ? profile.fallback.zone
                : nil
            panels.append(DisplayPanel(
                descriptor: descriptor,
                layout: layout,
                zones: zones,
                fallbackZone: fallback
            ))
        }
        return panels
    }

    private static func label(from rule: PlacementRule) -> RuleLabel {
        RuleLabel(
            ruleID: rule.id,
            name: rule.name,
            bundleIdentifier: rule.match.bundleIdentifier,
            priority: rule.priority,
            enabled: rule.enabled
        )
    }
}
