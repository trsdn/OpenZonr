import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Produces the events `openzonr dragprobe` measures, one per run-loop tick.
///
/// It exists because of a wrong number. The first version of the probe posted
/// forty mouse events in a `usleep` loop and the tap then reported 753 events
/// per second with a 51.5 ms gap — both artefacts of a queue draining *after*
/// the blocking loop ended, not properties of the delivery path. Anything that
/// blocks the main thread while measuring the main thread measures the block.
///
/// So the driver owns a timer, hands one event to the run loop per tick, and
/// lets the measured path run between ticks. The interval is deliberately in
/// the region of a real drag (8 ms ≈ 125 Hz) rather than as fast as possible:
/// the question is what arrives during a drag, not what a stress test survives.
@MainActor
final class SyntheticDriver {

    /// What the driver moves.
    enum Motion {
        /// The pointer, for the event tap. Stays in a corner and travels 40
        /// points — enough to produce events, too little to pick up a window.
        case pointer(CGPoint)
        /// A window, for the Accessibility observer, returned to `origin` at
        /// the end. A borrowed window is put back where it was found.
        case window(AXUIElement, CGPoint)
    }

    private let motion: Motion
    private let steps: Int
    private let interval: TimeInterval
    private var step = 0
    private var timer: Timer?

    init(motion: Motion, steps: Int, interval: TimeInterval = 0.008) {
        self.motion = motion
        self.steps = steps
        self.interval = interval
    }

    func start() {
        if case let .pointer(origin) = motion {
            post(.leftMouseDown, at: origin)
        }
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // .common so the ticks survive a run loop that is also servicing the
        // tap; the default mode would be enough here, but the probe should not
        // depend on that staying true.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        step += 1
        guard step <= steps else {
            finish()
            return
        }
        switch motion {
        case let .pointer(origin):
            post(.leftMouseDragged, at: CGPoint(x: origin.x + Double(step), y: origin.y))
        case let .window(element, origin):
            // A small sideways shuffle rather than a long slide: the window
            // stays where the user can still see it, and every step is a real
            // position change, which is what the notification reacts to.
            setPosition(element, to: CGPoint(x: origin.x + Double(step % 8), y: origin.y))
        }
    }

    private func finish() {
        switch motion {
        case let .pointer(origin):
            post(.leftMouseUp, at: CGPoint(x: origin.x + Double(steps), y: origin.y))
        case let .window(element, origin):
            setPosition(element, to: origin)
        }
        stop()
    }

    private func post(_ type: CGEventType, at point: CGPoint) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }
        event.post(tap: .cghidEventTap)
    }

    private func setPosition(_ element: AXUIElement, to point: CGPoint) {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }
}
