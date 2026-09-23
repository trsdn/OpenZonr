import Foundation

/// Ein Rechteck aus zwei Punkten, die über ein Raster gestrichen wurden.
///
/// Der Editor lässt eine Zone bisher anlegen und dann an Griffen zurechtziehen.
/// Streichen kehrt das um: die Geste *ist* die Zone. Beides bleibt möglich —
/// die Griffe rasten über ``EdgeSnap`` ohnehin auf dasselbe Raster, hier wird
/// nur eine zweite Art, es zu treffen, hinzugefügt.
///
/// Rein und ohne AppKit, damit die Rechnung geprüft werden kann, ohne eine
/// Maus zu bewegen.
public enum GridSweep {

    /// Die Auflösung des Rasters, in Zellen je Kante.
    ///
    /// Zwölf, weil der Editor seit jeher ein Zwölftelraster zeichnet und
    /// ``EdgeSnap`` dorthin rastet. Eine andere Zahl hier hiesse: die Geste
    /// trifft andere Kanten als der Griff daneben.
    public static let cells = 12

    /// Das Rechteck, das die Geste von `start` nach `end` aufzieht.
    ///
    /// Beide Punkte liegen in **Leinwand**-Koordinaten (Ursprung oben links,
    /// wie `RelativeRect`). Gerechnet wird in Zellen: der Block reicht von der
    /// Zelle unter dem einen Punkt bis zur Zelle unter dem anderen,
    /// **einschliesslich beider**. Ein Klick ohne Bewegung ergibt deshalb genau
    /// eine Zelle und nicht ein Rechteck ohne Fläche — sonst wäre die
    /// häufigste Fehlbedienung eine unsichtbare Zone.
    ///
    /// Die Richtung ist gleichgültig: von rechts unten nach links oben ergibt
    /// dasselbe wie umgekehrt.
    ///
    /// - Parameters:
    ///   - start: Punkt, an dem die Geste begann.
    ///   - end: Punkt, an dem sie endete.
    ///   - canvas: Grösse der Leinwand in denselben Einheiten wie die Punkte.
    /// - Returns: Das aufgezogene Rechteck, relativ zur Leinwand, immer
    ///   innerhalb des Einheitsquadrats. `nil`, wenn die Leinwand keine Fläche
    ///   hat — dann gibt es keine Zelle, auf die sich die Geste beziehen
    ///   könnte.
    public static func rect(from start: CGPoint, to end: CGPoint, canvas: CGSize) -> RelativeRect? {
        guard canvas.width > 0, canvas.height > 0 else { return nil }

        let startColumn = cell(for: start.x, extent: canvas.width)
        let endColumn = cell(for: end.x, extent: canvas.width)
        let startRow = cell(for: start.y, extent: canvas.height)
        let endRow = cell(for: end.y, extent: canvas.height)

        let firstColumn = min(startColumn, endColumn)
        let lastColumn = max(startColumn, endColumn)
        let firstRow = min(startRow, endRow)
        let lastRow = max(startRow, endRow)

        // Das Rechteck wird aus seinen **Kanten** gebildet, nicht aus Spanne
        // mal Schritt. In Fliesskomma ist das nicht dasselbe:
        // `2 · (1/12) − 1 · (1/12)` und `1 · (1/12)` können sich um ein ULP
        // unterscheiden. ``EdgeSnap`` rastet die vier Kanten einzeln und bildet
        // die Grösse als Differenz — wer hier anders rechnet, erzeugt je nach
        // benutzter Geste (streichen oder ziehen) minimal verschiedene Zonen,
        // und zwei Zonen sitzen dann nicht mehr bündig.
        let step = 1.0 / Double(cells)
        let left = Double(firstColumn) * step
        let right = Double(lastColumn + 1) * step
        let top = Double(firstRow) * step
        let bottom = Double(lastRow + 1) * step

        // Dieselbe Mindestgrösse wie ``EdgeSnap`` (dort `minSize`, eine Zelle).
        // Nicht kosmetisch: `rechts − links` liegt bei einzelligen Blöcken in
        // vier von zwölf Spalten ein ULP unter `step` — gemessen für Spalte 3,
        // 4, 6 und 9. Ohne die Klemme hinge es von der benutzten Geste ab, ob
        // eine einzellige Zone `0.08333333333333331` oder
        // `0.08333333333333333` breit ist.
        return RelativeRect(
            x: left,
            y: top,
            width: max(right - left, step),
            height: max(bottom - top, step)
        )
    }

    /// Der Zellenindex unter einer Koordinate, auf `0…cells-1` begrenzt.
    ///
    /// Die Begrenzung ist kein Formalismus: eine Geste, die über den Rand der
    /// Leinwand hinausläuft, soll die Randzelle treffen und nicht eine, die es
    /// nicht gibt.
    private static func cell(for value: Double, extent: Double) -> Int {
        let index = Int((value / extent * Double(cells)).rounded(.down))
        return min(max(index, 0), cells - 1)
    }
}
