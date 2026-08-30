import Foundation

/// Rasterung und Kantenfang für den Zoneneditor.
///
/// Der Editor rastet beim Loslassen auf ein Zwölftelraster, damit Hälften,
/// Drittel und Viertel ohne Naht schließen. Das reicht nicht überall: sobald
/// eine Zone auf einer benachbarten Zone aufsetzen soll, die selbst nicht auf
/// einem Zwölftel liegt (weil sie zuvor per Zahleneingabe gesetzt wurde oder
/// aus einem Import stammt), lässt das Zwölftelraster genau die Naht offen,
/// die auf 5120 px sehr sichtbar wird. Kantenfang deckt diesen Fall ab.
///
/// Die Funktion ist bewusst rein: der Editor gibt die Nachbarn (alle Zonen
/// desselben Layouts, ohne die gerade gezogene) und die Kantenrasterschwelle
/// hinein und bekommt die gefangene Rechteckform zurück. Kein SwiftUI, kein
/// Mausereignis, kein Zufall — die Belege für das Verhalten sind headless.
///
/// Zuerst wird an Nachbarkanten gerastet, dann ans Zwölftelraster. Die
/// Reihenfolge bedeutet: liegt eine Nachbarkante innerhalb der Fangschwelle,
/// gewinnt sie; sonst greift das Grundraster. Anders herum würde das
/// Grundraster erst auf einen der zwölf Stützpunkte springen und die
/// benachbarte Kante daneben liegen lassen — genau der Fall, den es zu
/// verhindern gilt.
public enum EdgeSnap {

    /// Standard-Schwelle für den Kantenfang, in Bruchteilen der Kantenlänge.
    ///
    /// Ein Zwölftel des Grundrasters ist `0.0833…`, damit fallen alle Punkte
    /// näher als etwa ein Sechstel Rasterschritt an eine Nachbarkante. Das ist
    /// weit genug, um beim Ziehen die Nahtsuche wahrnehmbar zu machen, und
    /// eng genug, um bei einer freien Positionierung neben der Zone zu
    /// bleiben. Die Schwelle ist ein Argument, damit Tests scharfe Zahlen
    /// belegen können, und trägt keinen SwiftUI-Zustand mit sich.
    public static let defaultThreshold: Double = 1.0 / 24.0

    /// Fängt `rect` zuerst an den Kanten in `neighbours`, dann ans Zwölftelraster.
    ///
    /// - Parameters:
    ///   - rect: das zu prüfende Rechteck im Einheitsquadrat.
    ///   - neighbours: die Kanten anderer Zonen desselben Layouts. Die gerade
    ///     gezogene Zone gehört **nicht** dazu — sonst rastet sie an sich
    ///     selbst, und die Geste steht still.
    ///   - threshold: höchster Abstand, bei dem eine Kante noch fängt.
    ///   - divisions: das Grundraster, in Zwölftel-Schritten.
    /// - Returns: `rect` mit angepasstem Ursprung und angepasster Größe. Wo
    ///   eine Nachbarkante gefangen wird, bleibt der gefangene Wert
    ///   unangetastet vom nachgelagerten Zwölftelraster.
    public static func snap(
        _ rect: RelativeRect,
        neighbours: [RelativeRect],
        threshold: Double = defaultThreshold,
        divisions: Int = 12
    ) -> RelativeRect {
        let verticals = Set(neighbours.flatMap { [$0.x, $0.x + $0.width] })
        let horizontals = Set(neighbours.flatMap { [$0.y, $0.y + $0.height] })

        let left = rect.x
        let right = rect.x + rect.width
        let top = rect.y
        let bottom = rect.y + rect.height

        let snappedLeft = snapValue(left, to: verticals, threshold: threshold)
        let snappedRight = snapValue(right, to: verticals, threshold: threshold)
        let snappedTop = snapValue(top, to: horizontals, threshold: threshold)
        let snappedBottom = snapValue(bottom, to: horizontals, threshold: threshold)

        let step = divisions > 0 ? 1.0 / Double(divisions) : 0
        let finalLeft = snappedLeft.snapped ? snappedLeft.value : gridSnap(left, step: step)
        let finalRight = snappedRight.snapped ? snappedRight.value : gridSnap(right, step: step)
        let finalTop = snappedTop.snapped ? snappedTop.value : gridSnap(top, step: step)
        let finalBottom = snappedBottom.snapped ? snappedBottom.value : gridSnap(bottom, step: step)

        let minSize = step > 0 ? step : 0.01
        return RelativeRect(
            x: finalLeft,
            y: finalTop,
            width: max(finalRight - finalLeft, minSize),
            height: max(finalBottom - finalTop, minSize)
        )
    }

    /// Der Wert, gerastet an das nächste Element aus `candidates`, sofern eines
    /// innerhalb von `threshold` liegt.
    private static func snapValue(
        _ value: Double,
        to candidates: Set<Double>,
        threshold: Double
    ) -> (value: Double, snapped: Bool) {
        var best: Double?
        var bestDistance = threshold
        for candidate in candidates {
            let distance = abs(candidate - value)
            if distance <= bestDistance {
                best = candidate
                bestDistance = distance
            }
        }
        if let best {
            return (best, true)
        }
        return (value, false)
    }

    private static func gridSnap(_ value: Double, step: Double) -> Double {
        guard step > 0 else { return value }
        return (value / step).rounded() * step
    }
}
