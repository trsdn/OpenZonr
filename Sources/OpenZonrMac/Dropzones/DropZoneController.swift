import AppKit
import ApplicationServices
import OpenZonrCore

/// Turns a mouse drag into a placement.
///
/// The parts are deliberately thin: ``DragMonitor`` says where the pointer is,
/// ``DropZoneResolver`` says which zones are under it, ``DropZoneSession``
/// decides which one wins, ``DropZoneOverlay`` shows it, and ``WatchEngine``
/// carries out the placement. This type only wires them together and owns the
/// one thing none of them can own — the window being dragged.
///
/// # Accessibility budget
///
/// Two reads per drag, both on the main actor and both at moments where a
/// pause is invisible to the user: one when the drag passes the activation
/// threshold (which window is this?), and none at all on release, because the
/// element is already in hand. Everything in between is arithmetic. That is
/// the whole reason the gesture hangs off an event tap; see ``DragMonitor``.
@MainActor
public final class DropZoneController {

    /// How far down a window counts as its drag handle.
    ///
    /// Without this, selecting text in an editor would summon the overlay and
    /// then move the window on mouse-up — the drag looks identical from the
    /// outside. A strip is a heuristic: apps with tall unified toolbars can be
    /// dragged further down than 44 pt, so those drags are ignored rather than
    /// mishandled. Refusing to act is the safe error here.
    ///
    /// Unverified against real applications: that needs the Accessibility
    /// permission. See `docs/dropzones.md`.
    static let dragHandleHeight: Double = 44

    public private(set) var isEnabled = false
    public private(set) var lastFailure: String?

    /// Set by the app when the user pauses. Pausing means hands off, and an
    /// overlay flashing over every drag is exactly the interference the pause
    /// switch exists to stop.
    public var isPaused = false {
        didSet {
            guard isPaused != oldValue, isPaused else { return }
            abandon()
        }
    }

    private let monitor = DragMonitor()
    private let overlay = DropZoneOverlay()
    private let resolver = DropZoneResolver()
    private var session = DropZoneSession()

    private unowned let engine: WatchEngine

    /// The window under the drag, captured once at activation.
    private var dragged: DraggedWindow?

    /// The point the drag started at, kept to test against the window frame
    /// once the window is known.
    private var origin: ScreenPoint?

    private struct DraggedWindow {
        let element: AXUIElement
        let application: NSRunningApplication
        let snapshot: WindowSnapshot
    }

    public init(engine: WatchEngine) {
        self.engine = engine
    }

    /// The modifier that means "leave this drag alone".
    ///
    /// Option, not Command: Command-dragging a background window is a system
    /// gesture that must keep working, and Control and Shift are widely bound
    /// inside applications. Option during a title-bar drag has no standing
    /// meaning in AppKit.
    static let suppressionModifier: NSEvent.ModifierFlags = .option

    // MARK: - Lifecycle

    @discardableResult
    public func enable() -> Bool {
        guard !isEnabled else { return true }
        do {
            try monitor.start(
                primaryTopY: { [engine] in engine.arrangement.primaryTopY },
                handler: { [weak self] event in self?.handle(event) }
            )
            isEnabled = true
            lastFailure = nil
            Log.success("Dropzones aktiv.")
            return true
        } catch {
            lastFailure = String(describing: error)
            Log.warn(lastFailure ?? "Dropzones ließen sich nicht starten.")
            return false
        }
    }

    public func disable() {
        guard isEnabled else { return }
        monitor.stop()
        overlay.tearDown()
        session.cancel()
        dragged = nil
        origin = nil
        isEnabled = false
        Log.info("Dropzones aus.")
    }

    /// Drops the current drag without placing anything.
    private func abandon() {
        session.cancel()
        overlay.hide()
        dragged = nil
        origin = nil
    }

    // MARK: - Verification hooks

    /// Panels currently on screen — the overlay is ours, so this is observable
    /// without any permission.
    public var visibleOverlayCount: Int { overlay.visiblePanelCount }

    public func overlayFrame(for alias: DisplayAlias) -> WindowFrame? {
        overlay.panelFrame(for: alias)
    }

    public var highlightedCandidate: DropCandidate? { session.highlighted }

    // MARK: - Events

    private func handle(_ event: DragMonitor.Event) {
        guard !isPaused else { return }
        switch event {
        case let .began(point):
            origin = point
            session.begin(at: point)
        case let .moved(point, modifiers):
            advance(to: point, suppressed: modifiers.contains(Self.suppressionModifier))
        case let .ended(point):
            finish(at: point)
        case .interrupted:
            Log.warn("Der Ereignis-Tap wurde vom System abgeschaltet und neu aktiviert. Ein Ziehen ging dabei verloren.")
            abandon()
        }
    }

    private func advance(to point: ScreenPoint, suppressed: Bool) {
        guard session.isTracking else { return }

        let wasActive = session.isActive
        session.update(at: point, suppressed: suppressed, candidates: candidates(at: point))

        if session.isActive, !wasActive {
            // First moment the gesture is committed enough to be worth an
            // Accessibility read.
            captureDraggedWindow()
        }

        guard dragged != nil, !suppressed, session.isActive else {
            overlay.hide()
            return
        }
        // Re-resolve after the capture, so the first active frame is drawn too.
        session.update(at: point, suppressed: false, candidates: candidates(at: point))
        showOverlay(for: point)
    }

    private func finish(at point: ScreenPoint) {
        defer {
            overlay.hide()
            dragged = nil
            origin = nil
        }
        guard let target = session.end(), let dragged else { return }
        engine.placeByHand(
            element: dragged.element,
            application: dragged.application,
            snapshot: dragged.snapshot,
            candidate: target
        )
    }

    // MARK: - Geometry

    private func candidates(at point: ScreenPoint) -> [DropCandidate] {
        guard let profile = engine.profileState.profile else { return [] }
        return resolver.candidates(
            at: point,
            profile: profile,
            configuration: engine.configuration,
            visibleFrames: engine.arrangement.visibleFrames(for: engine.configuration.displays)
        )
    }

    private func showOverlay(for point: ScreenPoint) {
        guard let profile = engine.profileState.profile else { return }
        let frames = engine.arrangement.visibleFrames(for: engine.configuration.displays)
        guard let alias = resolver.display(at: point, visibleFrames: frames),
              let visibleFrame = frames[alias],
              let descriptor = engine.configuration.displays.first(where: { $0.alias == alias }),
              let layout = descriptor.layouts.first(where: {
                  $0.id == (profile.layouts[alias] ?? descriptor.defaultLayoutID)
              })
        else {
            overlay.hide()
            return
        }

        let plan = DropZoneOverlay.Plan(
            alias: alias,
            bounds: WindowFrame(
                x: visibleFrame.x,
                y: visibleFrame.y,
                width: visibleFrame.width,
                height: visibleFrame.height
            ),
            zones: layout.zones.map {
                ($0.id, ZoneGeometry.absoluteFrame(of: $0.frame, in: visibleFrame))
            },
            highlighted: session.highlighted?.zone
        )
        overlay.show([plan])
    }

    // MARK: - Accessibility

    /// Finds the window the user grabbed — the single permission-dependent step
    /// of a drag.
    private func captureDraggedWindow() {
        dragged = nil
        guard let application = NSWorkspace.shared.frontmostApplication else { return }
        let pid = application.processIdentifier
        guard let element = Accessibility.focusedWindow(ofProcess: pid),
              let axFrame = Accessibility.frame(of: element)
        else { return }
        let snapshot = WindowInventory.snapshot(
            of: element,
            application: application,
            frame: axFrame,
            layer: 0,
            isFirstWindowAfterLaunch: false
        )

        // In AppKit coordinates, to compare against the pointer.
        let frame = engine.arrangement.flipVertically(snapshot.frame)
        guard let origin, ZoneGeometry.contains(frame, origin) else { return }
        let handleTop = frame.y + frame.height
        guard origin.y <= handleTop, origin.y >= handleTop - Self.dragHandleHeight else { return }

        dragged = DraggedWindow(element: element, application: application, snapshot: snapshot)
    }
}
