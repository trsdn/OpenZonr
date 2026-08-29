import ApplicationServices
import Foundation
import OpenZonrCore

/// The window a drag is about.
///
/// **Nicht `@MainActor`, aber `Sendable`.** Der Typ ist ein Wertetyp mit einem
/// `AXUIElement` — Apples Accessibility-API ist dokumentiert threadsicher, jede
/// `AXUIElementCopy…`-Operation darf von jedem Thread aus laufen. Der frühere
/// Grund für die Isolation war, dass alle AX-Aufrufer auf dem Hauptthread
/// standen; das wurde mit Issue #26 aufgegeben, weil dort ein Lookup von 970 ms
/// auf dem Hauptthread landete. Der `@unchecked`-Anteil betrifft nur, dass
/// `AXUIElement` selbst nicht als `Sendable` deklariert ist.
public struct DraggedWindow: @unchecked Sendable {
    public let element: AXUIElement
    public let processIdentifier: pid_t
    public let bundleIdentifier: String?
    public let applicationName: String
    /// The window's frame in **AppKit** coordinates when the drag was noticed.
    public let frame: WindowFrame

    public init(
        element: AXUIElement,
        processIdentifier: pid_t,
        bundleIdentifier: String?,
        applicationName: String,
        frame: WindowFrame
    ) {
        self.element = element
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.frame = frame
    }

    /// Das Fenster reduziert auf das, was eine Regel braucht.
    public var dropped: DroppedWindow {
        DroppedWindow(bundleIdentifier: bundleIdentifier, applicationName: applicationName)
    }
}

/// What a tracker reports. All points are in **AppKit** coordinates.
@MainActor
public enum WindowDragEvent {
    /// A window started moving. The point is where the pointer was.
    case began(DraggedWindow, at: ScreenPoint)
    /// The pointer moved while the window is being dragged.
    case moved(ScreenPoint, modifiers: ModifierState)
    /// The mouse button was released at this point.
    case ended(ScreenPoint, modifiers: ModifierState)
    /// The drag stopped without a usable release — the window vanished, the
    /// tracker was disabled, or the system took the event stream away.
    case cancelled(reason: String)
}

/// Why a tracker could not start.
///
/// Each case is a sentence the user can act on. "Ging nicht" would put the whole
/// feature into the same silent-nothing state this project keeps paying for.
public enum WindowDragTrackerError: Error, CustomStringConvertible {
    case notTrusted
    case eventTapRejected
    case noObservableApplication

    public var description: String {
        switch self {
        case .notTrusted:
            return Accessibility.permissionInstructions
        case .eventTapRejected:
            return """
            Der Ereignis-Tap konnte nicht erstellt werden. CGEventTapCreate verlangt
            dieselbe Bedienungshilfen-Freigabe wie das Bewegen von Fenstern — und zwar
            für genau dieses Bundle an genau diesem Pfad.
            """
        case .noObservableApplication:
            return "Es ist keine App erreichbar, an der sich Fensterbewegungen beobachten ließen."
        }
    }
}

/// A source of "a window is being dragged" events.
///
/// Two implementations exist because the issue demands that the choice be
/// measured rather than argued: ``EventTapDragTracker`` and
/// ``AXMovedDragTracker``. `openzonr dragprobe` runs both and prints numbers.
@MainActor
public protocol WindowDragTracker: AnyObject {
    /// Called for every event, on the main actor.
    var onEvent: ((WindowDragEvent) -> Void)? { get set }
    /// Short name for logs and for the probe's table.
    var name: String { get }
    func start() throws
    func stop()
}

extension ScreenArrangement {

    /// Mirrors a point between AppKit and Accessibility coordinates.
    ///
    /// The frame conversion subtracts the height as well; for a point there is
    /// no height, and using the frame version with a zero-height frame is how
    /// one accidentally writes it correctly once and wrongly the next time.
    public static func flipVertically(_ point: ScreenPoint, primaryTopY: Double) -> ScreenPoint {
        ScreenPoint(x: point.x, y: primaryTopY - point.y)
    }

    /// Mirrors a point using this arrangement's main display as the pivot.
    public func flipVertically(_ point: ScreenPoint) -> ScreenPoint {
        Self.flipVertically(point, primaryTopY: primaryTopY)
    }
}
