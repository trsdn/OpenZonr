import AppKit
import OpenZonrCore

/// The zones, drawn over everything, while a window is being dragged.
///
/// One borderless window per display rather than one big one across all of
/// them: on the measuring machine the displays do not form a rectangle, and a
/// window spanning the union would cover areas that are not on any screen.
///
/// The window is click-through (`ignoresMouseEvents`). That is not cosmetic —
/// the drag belongs to the application whose window is being moved, and an
/// overlay that swallowed the mouse would end the drag the moment it appeared.
@MainActor
final class DropzoneOverlay {

    private var windows: [DisplayAlias: NSWindow] = [:]

    /// Shows `plan`, creating and removing windows as needed.
    func show(_ plan: DropzoneOverlayPlan.Plan) {
        guard plan.isVisible else {
            hide()
            return
        }

        let byDisplay = Dictionary(grouping: plan.zones, by: \.display)
        for (display, zones) in byDisplay {
            let bounds = union(of: zones)
            let window = windows[display] ?? makeWindow()
            windows[display] = window
            window.setFrame(NSRect(x: bounds.x, y: bounds.y, width: bounds.width, height: bounds.height), display: false)
            let view = window.contentView as? DropzoneOverlayView
            view?.update(zones: zones, highlighted: plan.highlighted, offset: CGPoint(x: bounds.x, y: bounds.y))
            window.orderFrontRegardless()
        }

        for (display, window) in windows where byDisplay[display] == nil {
            window.orderOut(nil)
            windows.removeValue(forKey: display)
        }
    }

    func hide() {
        for window in windows.values { window.orderOut(nil) }
        windows.removeAll()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        // Above normal windows but below the menu bar: the overlay is a hint
        // during a gesture, not a modal surface.
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.contentView = DropzoneOverlayView()
        return window
    }

    private func union(of zones: [Dropzone]) -> WindowFrame {
        guard var minX = zones.first?.frame.x, var minY = zones.first?.frame.y else {
            return WindowFrame(x: 0, y: 0, width: 0, height: 0)
        }
        var maxX = minX
        var maxY = minY
        for zone in zones {
            minX = min(minX, zone.frame.x)
            minY = min(minY, zone.frame.y)
            maxX = max(maxX, zone.frame.x + zone.frame.width)
            maxY = max(maxY, zone.frame.y + zone.frame.height)
        }
        return WindowFrame(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

/// Draws the zones of one display.
final class DropzoneOverlayView: NSView {

    private var zones: [Dropzone] = []
    private var highlighted: Dropzone?
    private var offset: CGPoint = .zero

    func update(zones: [Dropzone], highlighted: Dropzone?, offset: CGPoint) {
        self.zones = zones
        self.highlighted = highlighted
        self.offset = offset
        needsDisplay = true
    }

    override var isFlipped: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        for zone in zones {
            let isHighlighted = zone.id == highlighted?.id
            let rect = NSRect(
                x: zone.frame.x - offset.x,
                y: zone.frame.y - offset.y,
                width: zone.frame.width,
                height: zone.frame.height
            ).insetBy(dx: 4, dy: 4)
            let path = NSBezierPath(roundedRect: rect, xRadius: 10, yRadius: 10)

            // The zone under the pointer is filled, the others are outlined.
            // Filling everything would tell the user where the zones are but not
            // where the window is going, which is the only question during a
            // drag.
            NSColor.controlAccentColor.withAlphaComponent(isHighlighted ? 0.32 : 0.10).setFill()
            path.fill()
            NSColor.controlAccentColor.withAlphaComponent(isHighlighted ? 0.95 : 0.45).setStroke()
            path.lineWidth = isHighlighted ? 3 : 1.5
            path.stroke()

            if isHighlighted { drawName(of: zone, in: rect) }
        }
    }

    private func drawName(of zone: Dropzone, in rect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: NSColor.white,
        ]
        let text = zone.name as NSString
        let size = text.size(withAttributes: attributes)
        let padding = NSSize(width: 14, height: 8)
        let plate = NSRect(
            x: rect.midX - (size.width + padding.width) / 2,
            y: rect.midY - (size.height + padding.height) / 2,
            width: size.width + padding.width,
            height: size.height + padding.height
        )
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: plate, xRadius: 8, yRadius: 8).fill()
        text.draw(at: NSPoint(x: plate.minX + padding.width / 2, y: plate.minY + padding.height / 2), withAttributes: attributes)
    }
}
