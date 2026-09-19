import Foundation

/// Belegt, dass ein Zug das *Fenster* bewegt und nicht etwas darin.
///
/// Ein AXWindow-Vorfahre unter dem Druckpunkt plus Zeigerweg beweist das nicht:
/// Text markieren, eine Datei ziehen oder einen Scrollbalken ziehen erfuellt
/// beides (#37). Der einzige Beleg, der Fensterzug von Inhaltszug trennt, ist
/// der Fensterrahmen selbst: er folgt dem Zeiger, oder er tut es nicht.
///
/// Rein und ohne AX, damit die Regel headless beweisbar ist. Die Rahmen liefert
/// der Tracker ausserhalb des Tap-Rueckrufs (siehe `EventTapDragTracker`,
/// #26); beide Rahmen und beide Punkte muessen in **AppKit**-Koordinaten sein.
/// `pointerFrom` ist der Druckpunkt, `pointerTo` der aktuelle Zeigerpunkt.
public enum WindowMoveEvidence {

    public enum Verdict: Hashable, Sendable {
        /// Groesse gleich, Ursprung folgt dem Zeiger: das Fenster wird gezogen.
        case moved
        /// Die Groesse hat sich geaendert: Kanten- oder Eckenzug.
        case resized
        /// Kein Beleg (Inhaltszug, Wackeln, Gegenbewegung).
        case notMoved
    }

    /// Groessenabweichung in Punkten, die noch als "gleich gross" gilt.
    public static let sizeTolerance: Double = 2
    /// Ursprungsverschiebung in Punkten, ab der von Bewegung die Rede ist.
    /// 6 pt liegen klar ueber AX-/Rundungsrauschen (~1-2 pt, Groessenordnung
    /// von `sizeTolerance`) und unter jedem bewussten Fensterzug.
    public static let minimumTravel: Double = 6
    /// Kleinster Kosinus zwischen Fenster- und Zeigerverschiebung (0,5 = hoechstens
    /// 60 Grad Abweichung). An Rand/Menuebar geklemmte Fenster folgen nur einer
    /// Achse und liegen bei ~45 Grad; quer laufende Verschiebungen (Animation,
    /// Kacheln) fallen darunter durch.
    public static let minimumAlignment: Double = 0.5

    public static func classify(
        initial: WindowFrame,
        current: WindowFrame,
        pointerFrom: ScreenPoint,
        pointerTo: ScreenPoint
    ) -> Verdict {
        if abs(current.width - initial.width) > sizeTolerance
            || abs(current.height - initial.height) > sizeTolerance {
            return .resized
        }
        let windowDX = current.x - initial.x
        let windowDY = current.y - initial.y
        guard (windowDX * windowDX + windowDY * windowDY).squareRoot() >= minimumTravel else {
            return .notMoved
        }
        let pointerDX = pointerTo.x - pointerFrom.x
        let pointerDY = pointerTo.y - pointerFrom.y
        // Richtung statt Betrag: Fenster werden am Rand/Menuebar geklemmt, und
        // manche Apps hinken dem Zeiger hinterher. Ohne Zeigerweg ist das Produkt 0
        // und es gibt keinen Beleg.
        let dot = windowDX * pointerDX + windowDY * pointerDY
        let pointerTravel = (pointerDX * pointerDX + pointerDY * pointerDY).squareRoot()
        let windowTravel = (windowDX * windowDX + windowDY * windowDY).squareRoot()
        return dot > minimumAlignment * windowTravel * pointerTravel ? .moved : .notMoved
    }
}
