import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import OpenZonrCore

/// Drag detection via a `CGEventTap` on the mouse.
///
/// ## What it gets right
///
/// The pointer position and the *release* come from the same stream, so a drop
/// is an event and not a guess. That matters more than it sounds: the whole
/// feature hangs on knowing exactly when the user let go, and the Accessibility
/// API has no notification for it.
///
/// ## What it costs
///
/// A tap sees every mouse event in the session, including all the ones that have
/// nothing to do with window dragging, and it sees them on the main run loop. It
/// also needs the same Accessibility grant as everything else here — measured,
/// not assumed; `openzonr dragprobe` prints whether the tap could be created.
///
/// The tap is **listen-only**. It never modifies or swallows an event, which
/// keeps the failure mode benign: if OpenZonr hangs, macOS disables the tap by
/// timeout and the user's mouse keeps working. That is also why
/// `.tapDisabledByTimeout` is handled rather than ignored.
@MainActor
public final class EventTapDragTracker: WindowDragTracker {

    public var onEvent: ((WindowDragEvent) -> Void)?
    public let name = "CGEventTap"

    /// Set from the outside to record raw event arrivals for the probe.
    ///
    /// The probe needs every event with its latency, the feature needs only the
    /// drags. Splitting them keeps measurement out of the hot path when nobody
    /// is measuring.
    public var onRawEvent: ((CGEventType, ScreenPoint, Duration?) -> Void)?

    /// How far the pointer must move before a press counts as a drag.
    ///
    /// Zero would report a drag for the click that merely focuses a window.
    public var minimumDragDistance: Double = 3

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var primaryTopY: Double
    private var pressLocation: ScreenPoint?
    private var dragging = false

    public init(primaryTopY: Double) {
        self.primaryTopY = primaryTopY
    }

    /// Re-reads the pivot for the coordinate flip.
    ///
    /// Called when the screen arrangement changes. A stale pivot does not
    /// misplace the pointer slightly — it puts it on the wrong display.
    public func updatePrimaryTopY(_ value: Double) {
        primaryTopY = value
    }

    public func start() throws {
        guard tap == nil else { return }

        let mask = (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.leftMouseDragged.rawValue)
            | (1 << CGEventType.leftMouseUp.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: eventTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw WindowDragTrackerError.eventTapRejected
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
    }

    public func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        pressLocation = nil
        dragging = false
    }

    /// Handles one event from the tap. Internal so the callback can reach it.
    func handle(type: CGEventType, event: CGEvent) {
        // The tap is disabled by macOS when a callback takes too long, and a
        // disabled tap reports nothing at all — silently, forever. Re-enabling
        // is the only way this feature survives one slow frame.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            if dragging {
                dragging = false
                onEvent?(.cancelled(reason: "Der Ereignis-Tap wurde vom System abgeschaltet."))
            }
            return
        }

        let accessibilityPoint = ScreenPoint(x: event.location.x, y: event.location.y)
        let point = ScreenArrangement.flipVertically(accessibilityPoint, primaryTopY: primaryTopY)
        onRawEvent?(type, point, Self.latency(of: event))

        switch type {
        case .leftMouseDown:
            pressLocation = point
            dragging = false

        case .leftMouseDragged:
            guard let press = pressLocation else { return }
            if !dragging {
                guard DropzoneActivator.distance(from: press, to: point) >= minimumDragDistance else { return }
                // The window is identified from where the press happened, not
                // from where the pointer is now: by the time it moved, the
                // pointer may already be over a different window, and dragging
                // by the title bar means the interesting element is under the
                // *first* point.
                guard let window = Self.window(atAccessibilityPoint: accessibilityPoint, primaryTopY: primaryTopY) else {
                    // No window under the press — a drag on the desktop, in a
                    // text view, anywhere. Stop looking until the next press.
                    pressLocation = nil
                    return
                }
                dragging = true
                onEvent?(.began(window, at: press))
            }
            onEvent?(.moved(point, modifiers: Self.modifiers(of: event)))

        case .leftMouseUp:
            let wasDragging = dragging
            pressLocation = nil
            dragging = false
            if wasDragging {
                onEvent?(.ended(point, modifiers: Self.modifiers(of: event)))
            }

        default:
            break
        }
    }

    /// Time between the event being stamped by the window server and this
    /// process seeing it.
    ///
    /// `CGEvent.timestamp` is in Mach absolute time units, the same clock
    /// `mach_absolute_time()` reads, so the difference is a genuine end-to-end
    /// delivery latency rather than a guess from a wall clock.
    ///
    /// Returns `nil` when the stamp is not usable — which is not a formality.
    /// Events posted by `CGEvent.post` are stamped at delivery, so subtracting
    /// gives a non-positive difference. Reporting that as `0.0 ms` would read as
    /// "measured, and instantaneous"; it means "nothing was measured here". Only
    /// events from real hardware carry a stamp that predates their arrival.
    static func latency(of event: CGEvent) -> Duration? {
        let now = mach_absolute_time()
        let stamped = event.timestamp
        guard stamped > 0, now > stamped else { return nil }
        return machDuration(ticks: now - stamped)
    }

    /// Converts Mach absolute time ticks into a `Duration`.
    static func machDuration(ticks: UInt64) -> Duration {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        guard info.denom != 0 else { return .zero }
        let nanoseconds = ticks * UInt64(info.numer) / UInt64(info.denom)
        return .nanoseconds(Int64(clamping: nanoseconds))
    }

    static func modifiers(of event: CGEvent) -> ModifierState {
        var state: ModifierState = []
        let flags = event.flags
        if flags.contains(.maskShift) { state.insert(.shift) }
        if flags.contains(.maskControl) { state.insert(.control) }
        if flags.contains(.maskAlternate) { state.insert(.option) }
        if flags.contains(.maskCommand) { state.insert(.command) }
        return state
    }

    /// The window under a point in **Accessibility** coordinates.
    ///
    /// `AXUIElementCopyElementAtPosition` answers with the deepest element — a
    /// button, a text field, a title bar — so the answer is walked up through
    /// `AXParent` until something with the window role appears. The walk is
    /// bounded: a malformed hierarchy must not turn a mouse drag into an
    /// infinite loop.
    static func window(atAccessibilityPoint point: ScreenPoint, primaryTopY: Double) -> DraggedWindow? {
        let systemWide = AXUIElementCreateSystemWide()
        var element: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            systemWide, Float(point.x), Float(point.y), &element
        ) == .success, let hit = element else { return nil }

        var current: AXUIElement? = hit
        var depth = 0
        while let candidate = current, depth < 12 {
            if Accessibility.string(candidate, kAXRoleAttribute as String) == (kAXWindowRole as String) {
                var pid: pid_t = 0
                guard AXUIElementGetPid(candidate, &pid) == .success,
                      let application = NSRunningApplication(processIdentifier: pid),
                      let frame = Accessibility.frame(of: candidate)
                else { return nil }

                return DraggedWindow(
                    element: candidate,
                    processIdentifier: pid,
                    bundleIdentifier: application.bundleIdentifier,
                    applicationName: application.localizedName ?? application.bundleIdentifier ?? "pid \(pid)",
                    frame: ScreenArrangement.flipVertically(frame, primaryTopY: primaryTopY)
                )
            }
            current = Accessibility.copyAttribute(candidate, kAXParentAttribute as String)
                .map { unsafeDowncast($0, to: AXUIElement.self) }
            depth += 1
        }
        return nil
    }
}

/// Bridges the C callback back into the tracker.
///
/// Same shape as ``WatchEngine``'s Accessibility callback and for the same
/// reason: the C function pointer cannot capture, so the tracker travels through
/// `userInfo`. The tap's run loop source is on the main run loop, which is what
/// makes the main-actor assumption sound rather than hopeful.
private let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tracker = Unmanaged<EventTapDragTracker>.fromOpaque(userInfo).takeUnretainedValue()
    let box = UncheckedEventBox(event)
    MainActor.assumeIsolated {
        tracker.handle(type: type, event: box.value)
    }
    // Listen-only: the event is passed through untouched, always.
    return Unmanaged.passUnretained(event)
}

private struct UncheckedEventBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
