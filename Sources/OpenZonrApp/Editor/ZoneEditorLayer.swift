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
    let onSweepChanged: (Bool) -> Void
    let onSweep: (RelativeRect) -> Void

    @State private var start: CGPoint?
    @State private var current: CGPoint?

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
                        start = value.startLocation
                        onSweepChanged(true)
                    }
                    current = value.location
                }
                .onEnded { value in
                    defer {
                        start = nil
                        current = nil
                        onSweepChanged(false)
                    }
                    guard let begin = start,
                          let rect = GridSweep.rect(from: begin, to: value.location, canvas: canvas)
                    else { return }
                    onSweep(rect)
                }
        )
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
