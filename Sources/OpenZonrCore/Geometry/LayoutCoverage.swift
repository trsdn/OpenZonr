import Foundation

/// Unbedeckte Fläche eines Zonensatzes, ausgedrückt als achsenparallele
/// Rechtecke im Einheitsquadrat.
///
/// Überlappungen sind laut ``Zone`` erlaubt und beabsichtigt — ein großes
/// Fokusfeld über zwei Hälften ist ein legitimes Muster. Die *unbedeckte*
/// Fläche dagegen ist fast immer ein Versehen und heute unsichtbar. Der Editor
/// zeigt sie als Schraffur; Voraussetzung dafür ist eine reine Rechnung, die
/// sich headless prüfen lässt.
///
/// Verfahren: rasterförmige Auswertung mit einer Auflösung, die alle üblichen
/// Layouts fehlerfrei trifft (Zwölftel, Viertel, 25/50/25, Fünftel). Das
/// Ergebnis wird zu horizontalen Streifen zusammengefasst und die Streifen
/// vertikal zu Rechtecken vereinigt, damit das Zeichnen nicht Tausende
/// Einzelkacheln macht. Die Fläche selbst bleibt genau, weil auf dem Raster
/// abgetastet wird, das Zonen auch selbst benutzen.
public enum LayoutCoverage {

    /// Standard-Rasterschritt für die Abtastung.
    ///
    /// 60 Schritte = kleinstes gemeinsames Vielfaches von 12 (Zwölftel), 4
    /// (Viertel), 5 (Fünftel) und 20 (25/50/25). Alle Vorlagen liegen damit
    /// auf Rasterstützpunkten; die Abdeckungsrechnung sagt für diese Layouts
    /// exakt Null.
    public static let defaultDivisions = 60

    /// Rechtecke, die die unbedeckte Fläche des Einheitsquadrats bilden.
    ///
    /// - Parameters:
    ///   - zones: die Zonenrechtecke des Layouts.
    ///   - divisions: Rasterfeinheit; ein Vielfaches von 12, 4 und 5 hält alle
    ///     Vorlagen exakt.
    /// - Returns: eine Liste achsenparalleler Rechtecke, deren Vereinigung
    ///   die unbedeckte Fläche ergibt. Sind alle Rasterzellen bedeckt, ist
    ///   die Liste leer.
    public static func uncovered(
        zones: [RelativeRect],
        divisions: Int = defaultDivisions
    ) -> [RelativeRect] {
        guard divisions > 0 else { return [] }
        let step = 1.0 / Double(divisions)
        let epsilon = step / 8

        // Eine Rasterzelle gilt als bedeckt, sobald ihr Mittelpunkt in
        // irgendeiner Zone liegt. Der Mittelpunkt ist der Ort, den die Zelle
        // repräsentiert; das gleicht Rundungen aus, ohne eine Rasterzeile
        // vorzuschreiben, an der sich die Zonen halten müssten.
        var covered = Array(repeating: Array(repeating: false, count: divisions), count: divisions)
        for row in 0..<divisions {
            let cy = (Double(row) + 0.5) * step
            for column in 0..<divisions {
                let cx = (Double(column) + 0.5) * step
                for zone in zones {
                    if cx >= zone.x - epsilon,
                       cx < zone.x + zone.width + epsilon,
                       cy >= zone.y - epsilon,
                       cy < zone.y + zone.height + epsilon {
                        covered[row][column] = true
                        break
                    }
                }
            }
        }

        // Zeilenweise unbedeckte Läufe finden, dann gleiche Läufe in
        // aufeinanderfolgenden Zeilen zu Rechtecken vereinigen. Der
        // Kompromiss ist absichtlich zeilenorientiert: eine allgemeine
        // Polygonzerlegung wäre exakter im Sonderfall zweier gestapelter
        // Löcher, aber die Fläche stimmt so oder so, und die Zeichenkosten
        // hängen an der Anzahl der Rechtecke, nicht an ihrer Anordnung.
        var stripsByRow: [[(start: Int, endExclusive: Int)]] = []
        for row in 0..<divisions {
            var strips: [(start: Int, endExclusive: Int)] = []
            var column = 0
            while column < divisions {
                if covered[row][column] {
                    column += 1
                    continue
                }
                let start = column
                while column < divisions, !covered[row][column] {
                    column += 1
                }
                strips.append((start, column))
            }
            stripsByRow.append(strips)
        }

        var result: [RelativeRect] = []
        // Offene Streifen: pro Startspalte höchstens einer. Ein neuer Streifen
        // mit gleicher Start- und Endspalte in der nächsten Zeile setzt den
        // offenen fort; alles andere schließt ihn ab.
        var openByStart: [Int: (endExclusive: Int, startRow: Int)] = [:]

        for row in 0..<divisions {
            var next: [Int: (endExclusive: Int, startRow: Int)] = [:]
            var carried = Set<Int>()
            for strip in stripsByRow[row] {
                if let open = openByStart[strip.start], open.endExclusive == strip.endExclusive {
                    next[strip.start] = open
                    carried.insert(strip.start)
                } else {
                    next[strip.start] = (strip.endExclusive, row)
                }
            }
            for (start, open) in openByStart where !carried.contains(start) {
                result.append(
                    rectangle(
                        start: start,
                        endExclusive: open.endExclusive,
                        startRow: open.startRow,
                        endRowExclusive: row,
                        step: step
                    )
                )
            }
            openByStart = next
        }
        for (start, open) in openByStart {
            result.append(
                rectangle(
                    start: start,
                    endExclusive: open.endExclusive,
                    startRow: open.startRow,
                    endRowExclusive: divisions,
                    step: step
                )
            )
        }
        return result
    }

    private static func rectangle(
        start: Int,
        endExclusive: Int,
        startRow: Int,
        endRowExclusive: Int,
        step: Double
    ) -> RelativeRect {
        RelativeRect(
            x: Double(start) * step,
            y: Double(startRow) * step,
            width: Double(endExclusive - start) * step,
            height: Double(endRowExclusive - startRow) * step
        )
    }
}
