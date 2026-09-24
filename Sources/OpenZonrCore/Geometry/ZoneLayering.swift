import Foundation

/// Zerlegt die Zonen einer Ebene in Gruppen, in denen sich nichts überlappt.
///
/// Gebraucht für die Übersicht. Sie zeichnet jede Zone an ihrer Stelle und
/// schreibt die Beschriftung hinein — bei gestapelten Zonen liegen damit
/// mehrere Texte übereinander und keiner ist lesbar. Das lässt sich nicht durch
/// Anordnung der Etiketten beheben: zwei Rechtecke am selben Ort haben dieselbe
/// freie Ecke.
///
/// Statt gegen die Überlappung zu zeichnen, wird sie gezeigt. Jede Gruppe ist
/// in sich überlappungsfrei und damit lesbar, und die Reihenfolge der Gruppen
/// sagt etwas: die grossen Flächen zuerst, die daraufliegenden Unterteilungen
/// danach.
public enum ZoneLayering {

    /// Die Zonen, gruppiert in überlappungsfreie Ebenen.
    ///
    /// Verfahren: absteigend nach Fläche sortieren, dann jede Zone in die
    /// **erste** Gruppe legen, in der sie mit nichts überlappt. Das ist kein
    /// Optimum — die kleinste Zahl Gruppen zu finden ist das Färben eines
    /// Graphen und damit unnötig teuer für eine Ansicht. Es ist aber stabil,
    /// verständlich und liefert für die Fälle, um die es geht (eine grosse
    /// Zone mit Unterteilungen darin), genau die erwartete Aufteilung.
    ///
    /// Absteigend nach Fläche, damit die grossen Flächen die erste Gruppe
    /// bilden und die Unterteilungen darauf folgen. Umgekehrt landete die
    /// grösste Zone in der letzten Gruppe und die Übersicht begänne mit den
    /// Bruchstücken.
    ///
    /// Bei gleicher Fläche entscheidet die Zonen-ID — dieselbe Ordnung wie im
    /// Treffertest, damit dieselbe Konfiguration immer dieselbe Ansicht ergibt
    /// und nicht die Reihenfolge in der Datei durchschlägt.
    ///
    /// - Returns: Die Gruppen, jede in der Reihenfolge der sortierten Eingabe.
    ///   Leere Eingabe ergibt keine Gruppe, nicht eine leere.
    public static func layers(of zones: [Zone]) -> [[Zone]] {
        let sorted = zones.sorted { lhs, rhs in
            let left = area(lhs.frame)
            let right = area(rhs.frame)
            if left != right { return left > right }
            return lhs.id < rhs.id
        }

        var result: [[Zone]] = []
        for zone in sorted {
            if let index = result.firstIndex(where: { group in
                group.allSatisfy { !overlaps($0.frame, zone.frame) }
            }) {
                result[index].append(zone)
            } else {
                result.append([zone])
            }
        }
        return result
    }

    /// Überlappen sich zwei Rechtecke *flächig*?
    ///
    /// Halboffene Kanten, wie überall sonst: links und oben einschliesslich,
    /// rechts und unten ausschliesslich. Zwei nebeneinanderliegende Spalten
    /// teilen sich eine Kante und überlappen **nicht** — sonst landete jede
    /// gewöhnliche Spaltenaufteilung in lauter Einzelebenen, und die Zerlegung
    /// wäre für den Normalfall unbrauchbar.
    static func overlaps(_ lhs: RelativeRect, _ rhs: RelativeRect) -> Bool {
        lhs.x < rhs.x + rhs.width && lhs.x + lhs.width > rhs.x
            && lhs.y < rhs.y + rhs.height && lhs.y + lhs.height > rhs.y
    }

    private static func area(_ rect: RelativeRect) -> Double {
        max(0, rect.width) * max(0, rect.height)
    }
}
