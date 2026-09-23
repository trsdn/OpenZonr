import OpenZonrCore
import SwiftUI

/// Welche der beiden Rechtecke einer Zone der Editor gerade bearbeitet.
///
/// Eine Zone trägt seit den Trefferflächen zwei Rechtecke: wohin das Fenster
/// kommt (``Zone/frame``) und wo losgelassen werden muss
/// (``Zone/activationArea``). Beide gleichzeitig ziehbar zu machen hiesse, bei
/// jedem Griff raten zu müssen, welches gemeint ist. Statt dessen: eine
/// Leinwand, ein Umschalter, und die jeweils andere Ebene bleibt blass
/// sichtbar — der Abstand zwischen beiden ist bei Randauslösung der ganze
/// Punkt und darf nicht unsichtbar sein.
/// Der Name des Koordinatenraums der Leinwand.
///
/// Gesten am Zonengriff **müssen** in diesem Raum messen und nicht in `.local`.
/// Der Griff sitzt unten rechts in einem Stapel, dessen Grösse aus dem
/// laufenden Zug berechnet wird: misst die Geste im eigenen View, wächst der
/// View mit der Geste, der Griff wandert unter dem Zeiger weg und die
/// Translation wird gegen einen bewegten Ursprung gemessen. Das Ergebnis
/// schwingt, statt dem Zeiger zu folgen — vom Nutzer gemeldet als „bewegt sich
/// nicht mit meinem Cursor" und „springt ständig hin und her".
///
/// Die Leinwand bewegt sich nicht. Deshalb misst hier alles gegen sie.
enum ZoneCanvas {
    static let space = "zoneCanvas"
}

enum EditorLayer: String, CaseIterable, Identifiable {
    case target
    case activation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .target: return "Zielrahmen"
        case .activation: return "Trefferfläche"
        }
    }
}

/// Die blasse Kontur der Ebene, die gerade **nicht** bearbeitet wird.
///
/// Reine Zeichnung, kein Treffertest — sie liegt unter den Griffen und darf
/// keine Geste abfangen.
struct GhostRects: View {

    let rects: [RelativeRect]
    let canvas: CGSize

    var body: some View {
        Canvas { context, _ in
            for rect in rects {
                let path = Path(roundedRect: CGRect(
                    x: rect.x * canvas.width,
                    y: rect.y * canvas.height,
                    width: rect.width * canvas.width,
                    height: rect.height * canvas.height
                ), cornerRadius: 4)
                context.stroke(
                    path,
                    with: .color(Color.secondary.opacity(0.45)),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
            }
        }
        .frame(width: canvas.width, height: canvas.height)
        .allowsHitTesting(false)
    }
}

/// Die Streich-Geste: über Zellen ziehen ergibt ein Rechteck.
///
/// Liegt **unter** den Zonengriffen, damit ein Zug auf einer bestehenden Zone
/// weiterhin diese Zone bewegt und nicht daneben eine neue aufzieht. Die Geste
/// beginnt also nur auf freier Fläche.
///
/// Die Rechnung selbst liegt in ``GridSweep`` und ist headless geprüft — hier
/// bleibt nur, die Punkte einzusammeln und die Vorschau zu zeichnen.
struct GridSweepSurface: View {

    let canvas: CGSize
    /// Die Rechtecke, die bereits belegt sind — auf ihnen beginnt **kein**
    /// Aufziehen.
    ///
    /// Ohne diese Grenze fängt die Fläche auch Gesten ab, die auf einer Zone
    /// beginnen: der Griff verschiebt oder skaliert die Zone, und am Ende
    /// bestimmt das Aufziehen dieselbe Zone noch einmal neu. Zwei
    /// Schreibvorgänge pro Geste, die gegeneinander laufen — sichtbar als
    /// Rahmen, der wild hin und her springt. Vom Nutzer im Gebrauch gemeldet.
    let occupied: [RelativeRect]
    let onSweepChanged: (Bool) -> Void
    let onSweep: (RelativeRect) -> Void

    @State private var start: CGPoint?
    @State private var current: CGPoint?
    /// Wahr, wenn die laufende Geste auf einer Zone begann und deshalb nicht
    /// als Aufziehen zählt.
    @State private var abandoned = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())

            if let preview {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(0.20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    )
                    .frame(width: preview.width, height: preview.height)
                    .offset(x: preview.minX, y: preview.minY)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: canvas.width, height: canvas.height)
        .gesture(
            // minimumDistance 0, weil ein Klick ohne Bewegung eine einzelne
            // Zelle ergeben soll — der schnellste Weg zu einer kleinen Zone.
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if start == nil {
                        // Einmal am Anfang entscheiden, nicht bei jedem Schritt:
                        // wer auf einer Zone losdrückt, will sie bewegen.
                        abandoned = isOccupied(value.startLocation)
                        guard !abandoned else { return }
                        start = value.startLocation
                        onSweepChanged(true)
                    }
                    guard !abandoned else { return }
                    current = value.location
                }
                .onEnded { value in
                    defer {
                        start = nil
                        current = nil
                        abandoned = false
                        onSweepChanged(false)
                    }
                    guard !abandoned,
                          let begin = start,
                          let rect = GridSweep.rect(from: begin, to: value.location, canvas: canvas)
                    else { return }
                    onSweep(rect)
                }
        )
    }

    /// Liegt der Punkt auf einer bereits belegten Fläche?
    ///
    /// Dieselbe Kantenregel wie überall sonst: links und oben einschliesslich,
    /// rechts und unten ausschliesslich — sonst gehörte die gemeinsame Kante
    /// zweier Zonen beiden.
    private func isOccupied(_ point: CGPoint) -> Bool {
        let x = point.x / canvas.width
        let y = point.y / canvas.height
        return occupied.contains { rect in
            x >= rect.x && x < rect.x + rect.width
                && y >= rect.y && y < rect.y + rect.height
        }
    }

    /// Das Rechteck, das die laufende Geste aufziehen würde — schon gerastet,
    /// damit die Vorschau zeigt, was beim Loslassen entsteht, und nicht den
    /// ungerasteten Zwischenstand.
    private var preview: CGRect? {
        guard let start, let current,
              let rect = GridSweep.rect(from: start, to: current, canvas: canvas)
        else { return nil }
        return CGRect(
            x: rect.x * canvas.width,
            y: rect.y * canvas.height,
            width: rect.width * canvas.width,
            height: rect.height * canvas.height
        )
    }
}
