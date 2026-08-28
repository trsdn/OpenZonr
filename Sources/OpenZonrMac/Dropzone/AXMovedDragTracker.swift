import AppKit
import ApplicationServices
import Foundation
import OpenZonrCore

/// Drag detection via `kAXMovedNotification` on the focused window.
///
/// ## What it gets right
///
/// It reports the thing it is actually about — *this window moved* — instead of
/// mouse events that have to be attributed to a window afterwards. No element
/// hit test, no events from clicks that are not drags.
///
/// ## What it costs, and why this is the honest half of the comparison
///
/// Accessibility has **no notification for the mouse button being released**.
/// The move events simply stop, and "stopped" is indistinguishable from "the
/// user is holding still". Since the drop is the entire point of dropzones,
/// this tracker has to find the release somewhere else, and the only source
/// that does not need another grant is polling ``NSEvent/pressedMouseButtons``.
/// It polls at 60 Hz while a drag is in progress and not otherwise.
///
/// It also reports moves that are not drags at all: a window moved by another
/// tool, by the app itself, or by OpenZonr's own placement. The button state
/// filters those out — which is the same poll again, now load-bearing for
/// correctness and not just for the end of the drag.
///
/// Both costs are measurable, and `openzonr dragprobe` measures them.
@MainActor
public final class AXMovedDragTracker: WindowDragTracker {

    public var onEvent: ((WindowDragEvent) -> Void)?
    public let name = "kAXMovedNotification"

    /// Raw arrivals for the probe: the moment a move notification landed.
    public var onRawMove: ((ScreenPoint) -> Void)?

    /// How often the mouse button is polled while a drag is running.
    public var pollInterval: TimeInterval = 1.0 / 60

    private var primaryTopY: Double
    private var observers: [pid_t: AXObserver] = [:]
    private var observedWindows: [pid_t: AXUIElement] = [:]
    private var activationObservation: (any NSObjectProtocol)?
    private var pollTimer: Timer?

    private var current: DraggedWindow?
    private var lastPoint: ScreenPoint?

    public init(primaryTopY: Double) {
        self.primaryTopY = primaryTopY
    }

    public func updatePrimaryTopY(_ value: Double) {
        primaryTopY = value
    }

    public func start() throws {
        guard Accessibility.isTrusted() else { throw WindowDragTrackerError.notTrusted }

        // Only the frontmost application is observed. Observing every running
        // one would mean an observer per process and a notification for every
        // window any of them ever moves; the window being dragged is by
        // definition the one in front.
        attachToFrontmostApplication()

        guard !observers.isEmpty else { throw WindowDragTrackerError.noObservableApplication }

        activationObservation = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.attachToFrontmostApplication() }
        }
    }

    public func stop() {
        if let activationObservation {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObservation)
        }
        activationObservation = nil
        for (pid, observer) in observers {
            if let window = observedWindows[pid] {
                AXObserverRemoveNotification(observer, window, kAXMovedNotification as CFString)
            }
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        }
        observers.removeAll()
        observedWindows.removeAll()
        pollTimer?.invalidate()
        pollTimer = nil
        current = nil
        lastPoint = nil
    }

    private func attachToFrontmostApplication() {
        guard let application = NSWorkspace.shared.frontmostApplication,
              application.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }

        let pid = application.processIdentifier
        let applicationElement = AXUIElementCreateApplication(pid)
        guard let window = (Accessibility.copyAttribute(applicationElement, kAXFocusedWindowAttribute as String)
            .map { unsafeDowncast($0, to: AXUIElement.self) })
            ?? Accessibility.windows(of: applicationElement).first
        else { return }

        // Re-registering on the same window is harmless but pointless, and it
        // happens on every application switch back and forth.
        if let existing = observedWindows[pid], CFEqual(existing, window) { return }

        var observer: AXObserver?
        if let existing = observers[pid] {
            observer = existing
            if let previous = observedWindows[pid] {
                AXObserverRemoveNotification(existing, previous, kAXMovedNotification as CFString)
            }
        } else {
            guard AXObserverCreate(pid, movedCallback, &observer) == .success, let created = observer else { return }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
            observers[pid] = created
        }

        guard let observer else { return }
        let status = AXObserverAddNotification(
            observer,
            window,
            kAXMovedNotification as CFString,
            Unmanaged.passUnretained(self).toOpaque()
        )
        guard status == .success else { return }
        observedWindows[pid] = window
    }

    /// Handles one move notification. Internal so the C callback can reach it.
    func handleMoved(_ element: AXUIElement) {
        guard let frame = Accessibility.frame(of: element) else { return }
        let point = pointerLocation()
        onRawMove?(point)

        // A move with no button held is not a drag. Windows are moved by their
        // own application, by other tools and by OpenZonr itself; without this
        // check the overlay would appear during OpenZonr's own placement, which
        // is the sort of feedback loop that is hard to see and impossible to
        // explain.
        guard NSEvent.pressedMouseButtons & 1 == 1 else { return }

        if current == nil {
            var pid: pid_t = 0
            guard AXUIElementGetPid(element, &pid) == .success,
                  let application = NSRunningApplication(processIdentifier: pid)
            else { return }

            let window = DraggedWindow(
                element: element,
                processIdentifier: pid,
                bundleIdentifier: application.bundleIdentifier,
                applicationName: application.localizedName ?? application.bundleIdentifier ?? "pid \(pid)",
                frame: ScreenArrangement.flipVertically(frame, primaryTopY: primaryTopY)
            )
            current = window
            onEvent?(.began(window, at: point))
            startPolling()
        }

        lastPoint = point
        onEvent?(.moved(point, modifiers: currentModifiers()))
    }

    /// Watches for the mouse button coming back up.
    ///
    /// This timer is the price of this approach. Accessibility never says "the
    /// user let go", so the release has to be noticed by asking, sixty times a
    /// second, for as long as a drag lasts.
    private func startPolling() {
        pollTimer?.invalidate()
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
                self.finishDrag()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    private func finishDrag() {
        pollTimer?.invalidate()
        pollTimer = nil
        guard current != nil else { return }
        current = nil
        let point = lastPoint ?? pointerLocation()
        lastPoint = nil
        onEvent?(.ended(point, modifiers: currentModifiers()))
    }

    /// The pointer in AppKit coordinates.
    ///
    /// `NSEvent.mouseLocation` is already bottom-left based, so nothing is
    /// flipped here — unlike the event tap, whose locations come from the window
    /// server top-left. Two sources, two conventions, and mixing them up puts
    /// the highlight on the wrong screen.
    private func pointerLocation() -> ScreenPoint {
        let location = NSEvent.mouseLocation
        return ScreenPoint(x: location.x, y: location.y)
    }

    private func currentModifiers() -> ModifierState {
        var state: ModifierState = []
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift) { state.insert(.shift) }
        if flags.contains(.control) { state.insert(.control) }
        if flags.contains(.option) { state.insert(.option) }
        if flags.contains(.command) { state.insert(.command) }
        return state
    }
}

private let movedCallback: AXObserverCallback = { _, element, _, refcon in
    guard let refcon else { return }
    let tracker = Unmanaged<AXMovedDragTracker>.fromOpaque(refcon).takeUnretainedValue()
    let box = UncheckedElementBox(element)
    MainActor.assumeIsolated {
        tracker.handleMoved(box.value)
    }
}

private struct UncheckedElementBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
