import Foundation

/// Das Seitenverhältnis, mit dem der Editor eine Bildschirmvorschau zeichnet —
/// samt der Auskunft, ob es gemessen oder geschätzt ist.
///
/// Warum das ein eigener Typ ist: eine unbeschriftete Schätzung, die aussieht
/// wie eine Messung, ist in diesem Projekt die Fehlerklasse, gegen die alles
/// andere geschrieben ist. Der Editor darf das Verhältnis nicht anzeigen,
/// ohne im selben Zug zu sagen, woher es kommt.
///
/// Die Auswahl „echte Maße oder Schätzung" ist reine Rechnung und lebt hier
/// in Core, damit sie ohne angeschlossenen Bildschirm prüfbar ist. Der Editor
/// bekommt nur das Ergebnis.
public struct CanvasAspect: Hashable, Sendable {

    /// Woher der Wert stammt.
    public enum Source: Hashable, Sendable {
        /// Aus dem sichtbaren Rahmen eines aktuell angeschlossenen Bildschirms.
        ///
        /// `visibleFrame`, nicht `frame`: Zonen werden ohnehin gegen den
        /// sichtbaren Bereich aufgelöst (`DefaultZoneResolver`). Wer die
        /// Vorschau am vollen Rahmen zeichnet, malt Platz mit, den Zonen nie
        /// bekommen können.
        case measured
        /// Fallback, weil der Bildschirm gerade nicht angeschlossen ist.
        ///
        /// Der Editor muss auch für einen abgezogenen Bildschirm funktionieren,
        /// und ohne Snapshot bleibt nichts anderes als ein Platzhalter. Der
        /// Wert ist als `estimated` beschriftet, damit die Oberfläche das
        /// sichtbar machen kann.
        case estimated
    }

    /// Breite geteilt durch Höhe. Immer positiv, nie `.nan`.
    public let ratio: Double

    /// Ob `ratio` an einem angeschlossenen Bildschirm gemessen wurde.
    public let source: Source

    /// Punktmaß des sichtbaren Rahmens, wenn er gemessen wurde.
    ///
    /// Wird von der Oberfläche neben den relativen Zonenmaßen verwendet, um
    /// aus `0,25` ein `1280 × 1344 pt` zu machen — solange echte Maße vorliegen.
    /// Bei einer Schätzung ist der Wert `nil`, weil eine geschätzte Punktzahl
    /// eine geschätzte Punktzahl bleibt und keine, die man neben eine
    /// gespeicherte Zahl schreibt.
    public let visibleSize: WindowSize?

    public init(ratio: Double, source: Source, visibleSize: WindowSize? = nil) {
        // Ein Verhältnis von `0` oder `.nan` würde `fittedRect` in einen
        // Divisions-durch-Null-Fehler treiben. Ein Bildschirm mit Breite oder
        // Höhe `0` ist ohnehin unmöglich; der Klammerungswert `0.01` steht
        // dafür, dass der Fehler hier bemerkt und nicht weitergereicht wird.
        let sanitised = (ratio.isFinite && ratio > 0) ? ratio : (16.0 / 10.0)
        self.ratio = sanitised
        self.source = source
        self.visibleSize = visibleSize
    }

    /// Der Platzhalter, den der Editor bekommt, wenn nichts Besseres da ist.
    ///
    /// 16:10 ist die Verteilung, die die meisten Notebook-Panels tragen; ein
    /// weder gemessener noch beschrifteter Wert wäre trotzdem falsch.
    public static let fallback = CanvasAspect(ratio: 16.0 / 10.0, source: .estimated)
}

/// Wählt das Seitenverhältnis für die Vorschau eines Bildschirms.
///
/// Ist der Bildschirm angeschlossen (im Sinne von: sein ``DisplayIdentity``
/// steht in `snapshots`), zählt sein `visibleFrame`. Ist er es nicht, bleibt es
/// bei ``CanvasAspect/fallback`` — als beschriftete Schätzung.
///
/// Reine Funktion, kein Zugriff auf `NSScreen` oder Ähnliches. Die Bedingung,
/// dass sie ohne angeschlossenen Bildschirm testbar ist, ist der Grund, warum
/// sie in Core lebt und nicht im Editor.
public func canvasAspect(
    for descriptor: DisplayDescriptor,
    snapshots: [DisplaySnapshot]
) -> CanvasAspect {
    guard let snapshot = snapshots.first(where: { $0.identity == descriptor.identity }) else {
        return .fallback
    }
    let width = snapshot.visibleFrame.width
    let height = snapshot.visibleFrame.height
    guard width > 0, height > 0 else {
        // Ein Snapshot mit einem entarteten sichtbaren Rahmen ist theoretisch
        // möglich (etwa wenn Dock und Menüleiste den ganzen Bildschirm
        // beanspruchen — auf realer Hardware nie beobachtet). Wenn es doch
        // passiert, ist die Schätzung ehrlicher als ein Verhältnis von `NaN`.
        return .fallback
    }
    return CanvasAspect(
        ratio: width / height,
        source: .measured,
        visibleSize: WindowSize(width: width, height: height)
    )
}
