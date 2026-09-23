import Foundation

/// Wird ein achsenparalleles Rechteck von einer Menge anderer lückenlos
/// überdeckt?
///
/// Gebraucht für den Befund „Zone unerreichbar": eine Zone verschwindet nicht
/// hinter *einer* anderen, sondern hinter der **Vereinigung** mehrerer. In der
/// Ebene des Autors überdecken „Rechts oben" und „Rechts unten" zusammen
/// „Rechts außen"; einzeln tut es keine von beiden. Eine paarweise Prüfung
/// fände den Fall nicht.
///
/// Verfahren: Gitterzerlegung. Alle Kanten der beteiligten Rechtecke, auf das
/// geprüfte Rechteck beschnitten, ergeben ein Gitter. Innerhalb einer Zelle
/// ändert sich nichts — entweder liegt sie ganz in einem der Rechtecke oder in
/// keinem. Es genügt also, je Zelle den Mittelpunkt zu prüfen. Das ist exakt,
/// nicht genähert, und bei der Zahl Zonen einer Ebene (einstellig) billig.
public enum RectangleCoverage {

    /// - Returns: `true`, wenn jeder Punkt von `rect` in mindestens einem der
    ///   `others` liegt. Ein Rechteck ohne Fläche gilt als überdeckt — es gibt
    ///   keinen Punkt, der unbedeckt bleiben könnte.
    public static func isCovered(_ rect: WindowFrame, by others: [WindowFrame]) -> Bool {
        guard rect.width > 0, rect.height > 0 else { return true }

        // Nur was das Rechteck überhaupt berührt, kann zur Überdeckung
        // beitragen.
        let relevant = others.filter { other in
            other.width > 0 && other.height > 0
                && other.x < rect.x + rect.width && other.x + other.width > rect.x
                && other.y < rect.y + rect.height && other.y + other.height > rect.y
        }
        guard !relevant.isEmpty else { return false }

        let xs = gridLines(
            from: relevant.flatMap { [$0.x, $0.x + $0.width] },
            low: rect.x, high: rect.x + rect.width
        )
        let ys = gridLines(
            from: relevant.flatMap { [$0.y, $0.y + $0.height] },
            low: rect.y, high: rect.y + rect.height
        )

        for xIndex in 0..<(xs.count - 1) {
            for yIndex in 0..<(ys.count - 1) {
                let midX = (xs[xIndex] + xs[xIndex + 1]) / 2
                let midY = (ys[yIndex] + ys[yIndex + 1]) / 2
                let covered = relevant.contains { other in
                    other.contains(ScreenPoint(x: midX, y: midY))
                }
                if !covered { return false }
            }
        }
        return true
    }

    /// Die Schnittlinien innerhalb `low…high`, aufsteigend und ohne Dubletten.
    private static func gridLines(from values: [Double], low: Double, high: Double) -> [Double] {
        var lines = [low, high]
        for value in values where value > low && value < high {
            lines.append(value)
        }
        return Array(Set(lines)).sorted()
    }
}
