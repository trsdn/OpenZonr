import Foundation

/// Meldet Zonen, die der Treffertest nie zurückgeben kann.
///
/// Eine Zone `Z` ist unerreichbar, wenn ihre Trefferfläche von der
/// **Vereinigung** der Trefferflächen jener Zonen derselben Ebene überdeckt
/// wird, die der Treffertest ihr vorzieht — kleinere Fläche, oder gleiche
/// Fläche und früher in der Ordnung der Zonen-IDs. Genau diese Regel steht in
/// ``DropzoneMap/zone(at:in:)``; hier wird sie nur rückwärts gelesen.
///
/// Gerechnet wird in relativen Einheiten. Das ist zulässig, weil alle Zonen
/// einer Ebene denselben sichtbaren Rahmen teilen: die Umrechnung ist eine
/// gemeinsame affine Abbildung und ändert an Überdeckung und
/// Flächenvergleichen nichts. Die Prüfung braucht deshalb **kein** Display und
/// läuft headless.
public struct ZoneReachabilityCheck: ConfigurationCheck {

    public init() {}

    public func findings(in configuration: Configuration) -> [ValidationFinding] {
        var findings: [ValidationFinding] = []

        for display in configuration.displays {
            for layout in display.layouts {
                findings.append(contentsOf: self.findings(in: layout, of: display))
            }
        }
        return findings
    }

    private func findings(in layout: Layout, of display: DisplayDescriptor) -> [ValidationFinding] {
        var findings: [ValidationFinding] = []

        for zone in layout.zones {
            let path = ConfigurationPath()
                .element("displays", display.alias)
                .element("layouts", layout.id)
                .element("zones", zone.id)

            let activation = zone.activationArea ?? zone.frame

            if let declared = zone.activationArea, !intersects(declared, zone.frame) {
                findings.append(ValidationFinding(
                    code: .activationAreaDetached,
                    path: path.field("activationArea"),
                    // Deutsche Anführungszeichen „…“ sind keine String-Begrenzer;
                    // ein gerades " an dieser Stelle beendete das Literal.
                    message: "Die Trefferfläche der Zone „\(zone.name)“ überschneidet ihren "
                        + "eigenen Zielrahmen nicht. Erlaubt — so lässt sich eine Zone am "
                        + "Bildschirmrand auslösen —, aber häufiger ein Versehen."
                ))
            }

            let preferred = layout.zones
                .filter { $0.id != zone.id }
                .filter { other in prefers(other, over: zone) }
                .map { $0.activationArea ?? $0.frame }

            if RectangleCoverage.isCovered(rect(activation), by: preferred.map(rect)) {
                findings.append(ValidationFinding(
                    code: .zoneUnreachable,
                    path: path,
                    message: "Die Zone „\(zone.name)“ ist nicht erreichbar: ihre Trefferfläche "
                        + "wird von kleineren Zonen derselben Ebene vollständig überdeckt. "
                        + "Gib ihr eine eigene „activationArea“, die frei liegt."
                ))
            }
        }
        return findings
    }

    /// Dieselbe Ordnung wie im Treffertest: kleinere Fläche gewinnt, bei
    /// Gleichstand die kleinere Zonen-ID. Die Displays sind hier immer gleich,
    /// weil eine Ebene zu genau einem Display gehört.
    private func prefers(_ candidate: Zone, over zone: Zone) -> Bool {
        let a = area(candidate.activationArea ?? candidate.frame)
        let b = area(zone.activationArea ?? zone.frame)
        if a != b { return a < b }
        return candidate.id < zone.id
    }

    private func area(_ rect: RelativeRect) -> Double {
        max(0, rect.width) * max(0, rect.height)
    }

    private func intersects(_ lhs: RelativeRect, _ rhs: RelativeRect) -> Bool {
        lhs.x < rhs.x + rhs.width && lhs.x + lhs.width > rhs.x
            && lhs.y < rhs.y + rhs.height && lhs.y + lhs.height > rhs.y
    }

    /// Relative Einheiten in ein `WindowFrame` umgedeutet, nur um
    /// ``RectangleCoverage`` benutzen zu können. Die Achsenrichtung spielt für
    /// Überdeckung keine Rolle, solange alle Rechtecke gleich behandelt werden.
    private func rect(_ relative: RelativeRect) -> WindowFrame {
        WindowFrame(x: relative.x, y: relative.y, width: relative.width, height: relative.height)
    }
}
