import AppKit
import OpenZonrCore

/// The translucent rectangle that says "let go here".
///
/// One panel per display, sized to that display's visible frame, drawing every
/// zone of the active profile faintly and the one under the pointer clearly.
/// Showing only the highlighted zone would be less code and worse: a user who
/// does not yet know where the zones are learns it by dragging, and a single
/// rectangle appearing out of nowhere teaches nothing.
///
/// The panels are ours, so unlike everything else in a drag they need no
/// Accessibility permission — which makes this the half of dropzones that can
/// be verified today.
@MainActor
public final class DropZoneOverlay {

    /// What to draw on one display.
    public struct Plan: Sendable {
        public let alias: DisplayAlias
        /// Display visible frame in AppKit global coordinates.
        public let bounds: WindowFrame
        /// Every zone of the display, in the same coordinates.
        public let zones: [(id: ZoneID, frame: WindowFrame)]
        /// The zone to emphasise, if the pointer is in one.
        public let highlighted: ZoneID?

        public init(
            alias: DisplayAlias,
            bounds: WindowFrame,
            zones: [(id: ZoneID, frame: WindowFrame)],
            highlighted: ZoneID?
        ) {
            self.alias = alias
            self.bounds = bounds
            self.zones = zones
            self.highlighted = highlighted
        }
    }

    private var panels: [DisplayAlias: NSPanel] = [:]

    public init() {}

    public var visiblePanelCount: Int {
        panels.values.filter(\.isVisible).count
    }

    /// The frame of the panel for `alias`, for verification.
    public func panelFrame(for alias: DisplayAlias) -> WindowFrame? {
        guard let panel = panels[alias] else { return nil }
        return WindowFrame(
            x: panel.frame.origin.x,
            y: panel.frame.origin.y,
            width: panel.frame.width,
            height: panel.frame.height
        )
    }

    /// The highlighted zone currently drawn on `alias`, for verification.
    public func highlightedZone(on alias: DisplayAlias) -> ZoneID? {
        (panels[alias]?.contentView as? DropZoneOverlayView)?.highlighted
    }

    public func show(_ plans: [Plan]) {
        let wanted = Set(plans.map(\.alias))
        for (alias, panel) in panels where !wanted.contains(alias) {
            panel.orderOut(nil)
        }
        for plan in plans {
            let panel = panel(for: plan.alias)
            let frame = NSRect(
                x: plan.bounds.x,
                y: plan.bounds.y,
                width: plan.bounds.width,
                height: plan.bounds.height
            )
            if panel.frame != frame {
                panel.setFrame(frame, display: false)
            }
            let view = panel.contentView as? DropZoneOverlayView
            // Panel-local coordinates: the view's origin is the display's
            // bottom-left corner, not the global one.
            view?.update(
                zones: plan.zones.map {
                    (
                        $0.id,
                        NSRect(
                            x: $0.frame.x - plan.bounds.x,
                            y: $0.frame.y - plan.bounds.y,
                            width: $0.frame.width,
                            height: $0.frame.height
                        )
                    )
                },
                highlighted: plan.highlighted
            )
            if !panel.isVisible {
                panel.orderFrontRegardless()
            }
        }
    }

    public func hide() {
        for panel in panels.values {
            panel.orderOut(nil)
        }
    }

    /// Drops the panels entirely. `hide()` keeps them for the next drag, which
    /// is the common case; this is for switching dropzones off.
    public func tearDown() {
        hide()
        panels.removeAll()
    }

    private func panel(for alias: DisplayAlias) -> NSPanel {
        if let existing = panels[alias] { return existing }
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        // Above ordinary windows, so the highlight is visible over the window
        // being dragged rather than under it.
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
        // A menu bar app has no windows of its own to become key, and stealing
        // focus mid-drag would cancel the drag.
        panel.hidesOnDeactivate = false
        panel.contentView = DropZoneOverlayView()
        panels[alias] = panel
        return panel
    }
}

/// Draws the zones. Plain `draw(_:)` rather than layers: a handful of
/// rectangles a few times a second is not where the frame budget goes.
final class DropZoneOverlayView: NSView {

    private(set) var zones: [(id: ZoneID, frame: NSRect)] = []
    private(set) var highlighted: ZoneID?

    override var isFlipped: Bool { false }

    func update(zones: [(ZoneID, NSRect)], highlighted: ZoneID?) {
        let changed = highlighted != self.highlighted
            || zones.count != self.zones.count
            || zip(zones, self.zones).contains { $0.0 != $1.id || $0.1 != $1.frame }
        self.zones = zones.map { (id: $0.0, frame: $0.1) }
        self.highlighted = highlighted
        if changed { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        for zone in zones {
            let isHighlighted = zone.id == highlighted
            let path = NSBezierPath(roundedRect: zone.frame.insetBy(dx: 4, dy: 4), xRadius: 10, yRadius: 10)
            if isHighlighted {
                NSColor.controlAccentColor.withAlphaComponent(0.28).setFill()
                NSColor.controlAccentColor.withAlphaComponent(0.9).setStroke()
                path.lineWidth = 3
            } else {
                NSColor.controlAccentColor.withAlphaComponent(0.06).setFill()
                NSColor.controlAccentColor.withAlphaComponent(0.28).setStroke()
                path.lineWidth = 1
            }
            path.fill()
            path.stroke()
        }
    }
}
