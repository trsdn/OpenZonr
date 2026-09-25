import OpenZonrCore
import SwiftUI

/// Which of a zone's two rectangles the editor is currently editing.
///
/// A zone has carried two rectangles since the activation areas landed:
/// where the window ends up (``Zone/frame``) and where the release has to
/// happen (``Zone/activationArea``). Making both draggable at once would mean
/// guessing, at every grip, which one is meant. Instead: one canvas, one
/// toggle, and the other layer stays faintly visible — the gap between the
/// two is the whole point at an edge trigger and must not be invisible.
/// The name of the canvas's coordinate space.
///
/// Gestures on the zone grip **must** measure in this space, not in
/// `.local`. The grip sits bottom-right in a stack whose size is computed
/// from the running drag: if the gesture measured in its own view, the view
/// would grow with the gesture, the grip would wander out from under the
/// pointer, and the translation would be measured against a moving origin.
/// The result oscillates instead of following the pointer — reported by a
/// user as "doesn't move with my cursor" and "keeps jumping back and forth".
///
/// The canvas itself does not move. That is why everything here measures
/// against it.
enum ZoneCanvas {
    static let space = "zoneCanvas"
}

enum EditorLayer: String, CaseIterable, Identifiable {
    case target
    case activation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .target: return localized("editorLayer.title.target", "Target Frame")
        case .activation: return localized("editorLayer.title.activation", "Activation Area")
        }
    }
}

/// The faint outline of the layer that is currently **not** being edited.
///
/// Pure drawing, no hit testing — it sits below the grips and must not
/// intercept a gesture.
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

/// The sweep gesture: dragging across cells yields a rectangle.
///
/// Sits **below** the zone grips, so a drag on an existing zone keeps
/// moving that zone instead of sweeping a new one next to it. The gesture
/// therefore only starts on free space.
///
/// The computation itself lives in ``GridSweep`` and is tested headless —
/// what's left here is collecting the points and drawing the preview.
struct GridSweepSurface: View {

    let canvas: CGSize
    /// The rectangles that are already occupied — **no** sweep starts on
    /// them.
    ///
    /// Without this boundary, the surface would also catch gestures that
    /// start on a zone: the grip moves or resizes the zone, and at the end
    /// the sweep redefines the same zone once more. Two writes per gesture,
    /// racing each other — visible as a frame that jumps wildly back and
    /// forth. Reported by a user in actual use.
    let occupied: [RelativeRect]
    let onSweepChanged: (Bool) -> Void
    let onSweep: (RelativeRect) -> Void

    @State private var start: CGPoint?
    @State private var current: CGPoint?
    /// `true` when the running gesture started on a zone and therefore does
    /// not count as a sweep.
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
            // minimumDistance 0, because a click with no movement should
            // yield a single cell — the fastest way to a small zone.
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if start == nil {
                        // Decide once at the start, not on every step:
                        // pressing down on a zone means moving it.
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

    /// Does the point lie on an already-occupied area?
    ///
    /// The same edge rule as everywhere else: left and top inclusive, right
    /// and bottom exclusive — otherwise the shared edge of two zones would
    /// belong to both.
    private func isOccupied(_ point: CGPoint) -> Bool {
        let x = point.x / canvas.width
        let y = point.y / canvas.height
        return occupied.contains { rect in
            x >= rect.x && x < rect.x + rect.width
                && y >= rect.y && y < rect.y + rect.height
        }
    }

    /// The rectangle the running gesture would sweep out — already
    /// grid-snapped, so the preview shows what release would produce, not
    /// the unsnapped intermediate state.
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
