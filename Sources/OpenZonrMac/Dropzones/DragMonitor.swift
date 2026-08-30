import AppKit
import ApplicationServices
import OpenZonrCore

/// Watches the left mouse button for the shape of a window drag.
///
/// # Why a `CGEventTap` and not `kAXMovedNotification`
///
/// Both were considered; the deciding argument is a measurement this project
/// already paid for. `WatchEngine` reads a window frame with six attempts a
/// second apart because a starting application can leave a single
/// Accessibility read blocking for three seconds. A drag produces on the order
/// of sixty events a second. Hanging the gesture off `kAXMovedNotification`
/// would mean Accessibility traffic on every one of them, against a process
/// that is by definition busy — the one being dragged.
///
/// The event tap has the opposite shape. It carries no window identity at all,
/// which sounds like a drawback and is in fact the point: it costs nothing per
/// event, and the two moments that genuinely need Accessibility — *which*
/// window was grabbed, and *where* to put it down — happen once each, at the
/// start and at the end. In between the tap runs on pure geometry.
///
/// `kAXMovedNotification` also cannot say when a drag *ends*, and it fires for
/// programmatic moves too, so our own placement would feed back into it.
///
/// # Measured
///
/// A listen-only session tap for `mouseMoved`/`leftMouseDragged` could be
/// created and enabled, and delivered 20 of 20 synthetic events, the first one
/// 24 ms after posting. That measurement was taken from a trusted terminal;
/// see `docs/dropzones.md` for what remains unmeasured.
@MainActor
public final class DragMonitor {

    /// What the monitor saw, in AppKit screen coordinates.
    public enum Event: Sendable {
        case began(at: ScreenPoint)
        case moved(to: ScreenPoint, modifiers: NSEvent.ModifierFlags)
        case ended(at: ScreenPoint)
        /// The system switched the tap off — usually because a callback was too
        /// slow. Re-enabled automatically; reported so it can be logged rather
        /// than silently swallowed.
        case interrupted
    }

    public enum StartFailure: Error, CustomStringConvertible {
        case tapRefused

        public var description: String {
            switch self {
            case .tapRefused:
                return """
                Der Ereignis-Tap ließ sich nicht erstellen. Das ist praktisch immer die
                fehlende Bedienungshilfen-Freigabe: ein Tap auf Mausereignisse ist ein
                Eingriff, den macOS nur freigegebenen Programmen erlaubt.
                """
            }
        }
    }

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var handler: ((Event) -> Void)?
    private var primaryTopYProvider: (() -> Double)?

    /// Pivot for the coordinate mirror. Re-read at every drag start rather than
    /// cached once, because a display change moves it and a stale pivot would
    /// put the pointer on the wrong screen — silently, since the number stays
    /// plausible.
    private var primaryTopY: Double = 0

    public init() {}

    public var isRunning: Bool { tap != nil }

    /// Starts listening. The handler is called on the main actor.
    public func start(
        primaryTopY: @escaping () -> Double,
        handler: @escaping (Event) -> Void
    ) throws {
        guard tap == nil else { return }
        self.handler = handler
        self.primaryTopYProvider = primaryTopY
        self.primaryTopY = primaryTopY()

        let mask: CGEventMask =
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue)

        let context = Unmanaged.passUnretained(self).toOpaque()
        guard let created = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: dragTapCallback,
            userInfo: context
        ) else {
            self.handler = nil
            self.primaryTopYProvider = nil
            throw StartFailure.tapRefused
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, created, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: created, enable: true)

        tap = created
        source = runLoopSource
    }

    public func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        tap = nil
        source = nil
        handler = nil
        primaryTopYProvider = nil
    }

    fileprivate func handle(type: CGEventType, location: CGPoint, flags: CGEventFlags) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            handler?(.interrupted)
        case .leftMouseDown:
            primaryTopY = primaryTopYProvider?() ?? primaryTopY
            handler?(.began(at: point(of: location)))
        case .leftMouseDragged:
            handler?(.moved(to: point(of: location), modifiers: modifiers(of: flags)))
        case .leftMouseUp:
            handler?(.ended(at: point(of: location)))
        default:
            break
        }
    }

    private func point(of location: CGPoint) -> ScreenPoint {
        ScreenArrangement.flipVertically(
            ScreenPoint(x: location.x, y: location.y),
            primaryTopY: primaryTopY
        )
    }

    private func modifiers(of flags: CGEventFlags) -> NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue))
    }
}

/// Bridges the C callback back into the monitor.
///
/// Same arrangement as `WatchEngine`'s Accessibility callbacks: a bare function
/// pointer cannot capture, so the instance travels through `userInfo`. The tap
/// source was added to the main run loop, so main actor isolation is a fact
/// here, not a hope.
///
/// The event's location and flags are read out here rather than passed along,
/// because `CGEvent` is a class and not `Sendable` — and because everything
/// downstream only ever wanted those two values.
private let dragTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let monitor = Unmanaged<DragMonitor>.fromOpaque(userInfo).takeUnretainedValue()
    let location = event.location
    let flags = event.flags
    MainActor.assumeIsolated {
        monitor.handle(type: type, location: location, flags: flags)
    }
    return Unmanaged.passUnretained(event)
}
