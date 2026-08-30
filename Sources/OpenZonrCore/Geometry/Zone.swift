import Foundation

/// Stable identifier of a zone, unique within its ``Layout``.
public struct ZoneID: StringIdentifier {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// A named target area on a display.
///
/// A zone is pure geometry plus identity. It carries no knowledge of which app
/// belongs into it — that link is established indirectly through a ``ZoneRole``
/// binding inside a ``Profile``.
public struct Zone: Codable, Hashable, Sendable, Identifiable {
    public var id: ZoneID
    /// Human readable label shown in the UI, e.g. "rechts oben".
    public var name: String
    /// Geometry relative to the visible frame of the owning display.
    public var frame: RelativeRect

    public init(id: ZoneID, name: String, frame: RelativeRect) {
        self.id = id
        self.name = name
        self.frame = frame
    }
}

/// Stable identifier of a layout, unique within its display descriptor.
public struct LayoutID: StringIdentifier {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

/// A complete set of zones for one display.
///
/// Layouts belong to a **display**, not to a profile: a 38" ultrawide wants a
/// three-column layout, a 24" office monitor a two-column one, and that stays
/// true no matter which setup profile is currently active. A display may own
/// several layouts (e.g. "3 Spalten" and "2 Spalten + Fokus"); the active
/// profile selects which one is in use.
///
/// Zones within a layout may overlap. Overlap is a legitimate design (a large
/// "focus" zone stacked on top of two half zones), so it is not rejected — but
/// the rule engine resolves ambiguity through ``ZoneRole`` bindings, never by
/// guessing from geometry.
///
/// Ein Layout darf einen ``margin`` tragen — den einzigen Abstand, den das
/// Modell kennt. Er wirkt *nur beim Platzieren*: ``DefaultZoneResolver`` zieht
/// ihn beim Auflösen einer Zone in konkrete Fenstermaße ab, ``DropzoneMap``
/// rechnet weiter mit den ungeschrumpften Zonen. Damit sieht man Luft
/// zwischen den Fenstern und zieht trotzdem über eine geschlossene Fläche.
/// Wer den Rand an beiden Stellen abzöge, bekäme optisch dasselbe Ergebnis
/// und ein Overlay, das an jeder Naht blinkt.
public struct Layout: Codable, Hashable, Sendable, Identifiable {
    public var id: LayoutID
    public var name: String
    public var zones: [Zone]
    /// Rand um jede Zone, in Bruchteilen des sichtbaren Rahmens.
    ///
    /// Wirkt nur beim Platzieren; ``DropzoneMap`` bleibt unangetastet. `0`
    /// heißt: keine Luft — das bisherige Verhalten. Werte über `0.05` würden
    /// halbe Zonen auf einem 5120 px breiten Bildschirm um mehr als 128 px
    /// pro Seite schrumpfen und sind fast immer ein Versehen; die Validierung
    /// hält das eng.
    public var margin: Double

    public init(id: LayoutID, name: String, zones: [Zone], margin: Double = 0) {
        self.id = id
        self.name = name
        self.zones = zones
        self.margin = margin
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, zones, margin
    }

    /// Dekodiert ein Layout, tolerant gegen fehlenden ``margin``.
    ///
    /// Ein Handeintrag ohne Randwert bleibt gültig; der Standard `0` erhält
    /// das bisherige Verhalten. Ohne diesen Decoder würde jede Konfiguration
    /// aus der Zeit vor dem Feld beim Laden abgelehnt — die lauteste denkbare
    /// Art, etwas zu brechen, das mit Rändern nichts zu tun hat.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(LayoutID.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.zones = try container.decode([Zone].self, forKey: .zones)
        self.margin = try container.decodeIfPresent(Double.self, forKey: .margin) ?? 0
    }

    /// Kodiert ein Layout; ``margin`` bleibt weg, wenn er `0` ist.
    ///
    /// Damit erzeugt der Editor für Layouts ohne Rand keine neue Zeile in der
    /// JSON-Datei — was im Diff eines Handeintrags Lärm wäre und in einer
    /// versionierten Konfiguration ohne Not.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(zones, forKey: .zones)
        if margin != 0 {
            try container.encode(margin, forKey: .margin)
        }
    }
}
