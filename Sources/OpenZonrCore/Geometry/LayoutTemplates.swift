import Foundation

/// Fertige Zonensätze für die üblichen Aufteilungen.
///
/// Der Editor bietet sie als Vorlagen an, damit der Weg von *„ich will drei
/// Spalten"* zu *drei sauber schließenden Rechtecken* nicht über acht Zahlen
/// führt. Die vorhandene Beispielkonfiguration `c49rg9x-three-columns` ist ein
/// **von Hand gebautes 25/50/25** — das Argument, dass Vorlagen gebraucht
/// werden, kommt aus dem Projekt selbst.
///
/// Alle Vorlagen liegen auf dem Zwölftel- oder Zwanzigstelraster und schließen
/// deshalb ohne Naht. Die Zone-Kennungen sind stabil: `applying` ersetzt die
/// Zonen eines Layouts vollständig, und wer eine Vorlage zweimal anwendet,
/// bekommt zweimal dieselben Kennungen — sonst würden Bindungen still ins
/// Leere zeigen, ohne dass jemand daran gedreht hat.
public enum LayoutTemplate: String, CaseIterable, Sendable {

    /// Zwei gleich breite Spalten: 6/12 links, 6/12 rechts.
    case halves = "halves"
    /// Drei gleich breite Spalten: 4/12 · 4/12 · 4/12.
    case thirds = "thirds"
    /// Vier gleich breite Spalten: 3/12 · 3/12 · 3/12 · 3/12.
    case quarters = "quarters"
    /// Drei Spalten 25 · 50 · 25 — die vorhandene Konfiguration in Zahlen.
    case twentyFiveFiftyTwentyFive = "twenty-five-fifty-twenty-five"
    /// Fünf gleich breite Spalten — auf 5120 px sind Drittel Fenster von
    /// 1706 px, und das ist für die üblichen Fenstergrößen zu breit.
    case fifths = "fifths"

    /// Beschriftung für das Menü.
    public var displayName: String {
        switch self {
        case .halves: return "Hälften"
        case .thirds: return "Drittel"
        case .quarters: return "Viertel"
        case .twentyFiveFiftyTwentyFive: return "25 · 50 · 25"
        case .fifths: return "Fünftel"
        }
    }

    /// Die Zonen der Vorlage im Einheitsquadrat, in Lese-Reihenfolge.
    ///
    /// Namen sind deutsch, weil der Editor deutsch beschriftet ist; die
    /// Kennungen bleiben ASCII, damit sie in Dateipfaden und Bindungen
    /// unauffällig bleiben.
    public var zones: [Zone] {
        switch self {
        case .halves:
            return [
                zone("halves-left", "Links", 0, 0, 6.0 / 12, 1),
                zone("halves-right", "Rechts", 6.0 / 12, 0, 6.0 / 12, 1),
            ]
        case .thirds:
            return [
                zone("thirds-left", "Links", 0, 0, 4.0 / 12, 1),
                zone("thirds-center", "Mitte", 4.0 / 12, 0, 4.0 / 12, 1),
                zone("thirds-right", "Rechts", 8.0 / 12, 0, 4.0 / 12, 1),
            ]
        case .quarters:
            return [
                zone("quarters-1", "Erstes Viertel", 0, 0, 3.0 / 12, 1),
                zone("quarters-2", "Zweites Viertel", 3.0 / 12, 0, 3.0 / 12, 1),
                zone("quarters-3", "Drittes Viertel", 6.0 / 12, 0, 3.0 / 12, 1),
                zone("quarters-4", "Viertes Viertel", 9.0 / 12, 0, 3.0 / 12, 1),
            ]
        case .twentyFiveFiftyTwentyFive:
            return [
                zone("wide-left", "Links", 0, 0, 0.25, 1),
                zone("wide-center", "Mitte", 0.25, 0, 0.5, 1),
                zone("wide-right", "Rechts", 0.75, 0, 0.25, 1),
            ]
        case .fifths:
            return [
                zone("fifths-1", "Erstes Fünftel", 0, 0, 0.2, 1),
                zone("fifths-2", "Zweites Fünftel", 0.2, 0, 0.2, 1),
                zone("fifths-3", "Drittes Fünftel", 0.4, 0, 0.2, 1),
                zone("fifths-4", "Viertes Fünftel", 0.6, 0, 0.2, 1),
                zone("fifths-5", "Fünftes Fünftel", 0.8, 0, 0.2, 1),
            ]
        }
    }

    private func zone(_ id: String, _ name: String, _ x: Double, _ y: Double, _ w: Double, _ h: Double) -> Zone {
        Zone(id: ZoneID(rawValue: id), name: name, frame: RelativeRect(x: x, y: y, width: w, height: h))
    }
}

/// Auswirkungen einer Vorlagenanwendung, die dem Nutzer *vorher* gezeigt werden.
///
/// Der Editor meldet hängende Bindungen bereits als Befund
/// (``ValidationCode/unknownZoneInBinding``), sobald sie entstehen. Für eine
/// Vorlage ist das zu spät — sie ersetzt bestehende Zonen auf einen Schlag.
/// ``PreviewedApplication`` sagt vor der Anwendung, welche Bindungen dadurch
/// ins Leere zeigen würden, und wer das liest, entscheidet mit offenen Augen.
public struct LayoutTemplatePreview: Hashable, Sendable {

    /// Zonenkennungen, die verschwinden würden.
    public var removedZones: [ZoneID]

    /// Bindungen, die nach der Anwendung ``unknownZoneInBinding`` melden würden.
    ///
    /// Pro Rolle nur ein Eintrag, weil das Datenmodell pro Profil höchstens
    /// eine Bindung pro Rolle vorsieht — und dieser Vorschau-Wert stammt aus
    /// derselben Bindungsliste.
    public var danglingBindings: [DanglingBinding]

    public init(removedZones: [ZoneID], danglingBindings: [DanglingBinding]) {
        self.removedZones = removedZones
        self.danglingBindings = danglingBindings
    }

    public struct DanglingBinding: Hashable, Sendable {
        public var profile: ProfileID
        public var role: RoleID
        public var display: DisplayAlias
        public var zone: ZoneID

        public init(profile: ProfileID, role: RoleID, display: DisplayAlias, zone: ZoneID) {
            self.profile = profile
            self.role = role
            self.display = display
            self.zone = zone
        }
    }
}

extension Configuration {

    /// Was das Anwenden von `template` an Bindungen ins Leere brechen würde.
    ///
    /// Ein reiner Vergleich der Zonenkennungen: alle Kennungen, die im neuen
    /// Layout **nicht mehr** vorkommen, sind entfernt; jede Rollenbindung, die
    /// eine solche Kennung auf diesem Bildschirm nennt, würde hängen.
    ///
    /// Die Funktion ändert nichts. Der Editor ruft sie vor der Anwendung auf,
    /// zeigt die Liste, und der Nutzer entscheidet.
    public func previewApplying(
        template: LayoutTemplate,
        layout: LayoutID,
        display: DisplayAlias
    ) -> LayoutTemplatePreview {
        let existing = displays
            .first { $0.alias == display }?
            .layouts.first { $0.id == layout }?
            .zones.map(\.id) ?? []
        let newIDs = Set(template.zones.map(\.id))
        let removed = existing.filter { !newIDs.contains($0) }
        let removedSet = Set(removed)

        var dangling: [LayoutTemplatePreview.DanglingBinding] = []
        for profile in profiles where (profile.layouts[display] ?? layoutID(forDisplay: display, inProfile: profile.id)) == layout {
            for binding in profile.roleBindings where binding.display == display && removedSet.contains(binding.zone) {
                dangling.append(
                    LayoutTemplatePreview.DanglingBinding(
                        profile: profile.id,
                        role: binding.role,
                        display: display,
                        zone: binding.zone
                    )
                )
            }
        }
        return LayoutTemplatePreview(removedZones: removed, danglingBindings: dangling)
    }

    /// Ersetzt die Zonen eines Layouts vollständig durch die der Vorlage.
    ///
    /// Bindungen werden nicht mitgezogen. Wer eine Vorlage anwendet, für die
    /// zuvor `previewApplying(template:…)` hängende Bindungen ausgewiesen hat,
    /// bekommt danach genau diese Bindungen als
    /// ``ValidationCode/unknownZoneInBinding`` gemeldet — das ist die
    /// gewünschte Kette: Vorschau zeigt es, die Validierung hält es fest, die
    /// Sidebar-Badges machen es sichtbar.
    public func applying(
        template: LayoutTemplate,
        layout: LayoutID,
        display: DisplayAlias
    ) -> Configuration {
        guard
            let displayIndex = displays.firstIndex(where: { $0.alias == display }),
            let layoutIndex = displays[displayIndex].layouts.firstIndex(where: { $0.id == layout })
        else { return self }
        var copy = self
        copy.displays[displayIndex].layouts[layoutIndex].zones = template.zones
        return copy
    }
}
