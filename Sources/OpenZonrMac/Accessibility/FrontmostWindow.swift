import AppKit
import ApplicationServices
import Foundation
import OpenZonrCore

/// The window the user is looking at right now.
///
/// ## Why this is not a right-click on the window
///
/// The concept and issue #9 describe the 90 % case as a **right click on a
/// placed window → „Diese App immer hier öffnen"**. That is not reachable with
/// public API. A context menu on a foreign application's window would have to be
/// injected into that application's own event handling; macOS has no supported
/// way to add an item to another process's window menu, and the alternative —
/// a transparent overlay window that intercepts right clicks over every screen —
/// would swallow clicks that belong to the app underneath and needs
/// Screen Recording on top of Accessibility.
///
/// The reachable path with the same result is this one: the user puts the
/// window where it belongs, then picks „Aktuelles Fenster hier festhalten" from
/// the menu bar. Same input (this app, this place), same output (a rule and a
/// binding), one extra move of the mouse. The deviation is written down in
/// `docs/regel-editor.md` rather than left to be discovered.
public enum FrontmostWindow {

    /// What the pin needs to know about the window in front.
    public struct Snapshot: Sendable {
        public var bundleIdentifier: String
        public var applicationName: String
        /// The window in **AppKit** coordinates, origin bottom-left — already
        /// converted, because that is the space zones live in.
        public var frame: WindowFrame
        public var title: String?
    }

    /// Why there is nothing to pin.
    ///
    /// Separate cases because they need separate sentences: "OpenZonr is in
    /// front" and "no permission" look identical from the outside and have
    /// nothing to do with each other.
    public enum Failure: Error, CustomStringConvertible {
        case noFrontmostApplication
        case ownApplication
        case noBundleIdentifier(String)
        case noWindow(String)

        public var description: String {
            switch self {
            case .noFrontmostApplication:
                return "Es ist keine App im Vordergrund."
            case .ownApplication:
                return "Im Vordergrund steht OpenZonr selbst. Bring erst das Fenster nach vorne, das festgehalten werden soll."
            case let .noBundleIdentifier(name):
                return "„\(name)“ meldet keine Bundle-Kennung; ohne sie lässt sich keine Regel schreiben."
            case let .noWindow(name):
                return "Von „\(name)“ ist kein Fenster lesbar. Fehlt die Freigabe für die Bedienungshilfen?"
            }
        }
    }

    /// Reads the frontmost window of the frontmost application.
    ///
    /// - Parameter primaryTopY: the pivot for the coordinate flip, taken from
    ///   ``ScreenArrangement``. The Accessibility API reports windows top-left
    ///   based while zones are resolved bottom-left based; getting this backwards
    ///   does not misplace a window slightly, it picks the wrong screen.
    @MainActor
    public static func read(primaryTopY: Double) -> Result<Snapshot, Failure> {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return .failure(.noFrontmostApplication)
        }
        guard application.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            return .failure(.ownApplication)
        }

        let name = application.localizedName ?? "Unbekannt"
        guard let bundleIdentifier = application.bundleIdentifier else {
            return .failure(.noBundleIdentifier(name))
        }

        let element = AXUIElementCreateApplication(application.processIdentifier)
        // The focused window first — that is the one the user is working in. The
        // first window of the list is the fallback for applications that do not
        // report a focused one, which is common right after a launch.
        let window = (Accessibility.copyAttribute(element, kAXFocusedWindowAttribute as String)
            .map { unsafeDowncast($0, to: AXUIElement.self) })
            ?? Accessibility.windows(of: element).first

        guard let window, let accessibilityFrame = Accessibility.frame(of: window) else {
            return .failure(.noWindow(name))
        }

        return .success(
            Snapshot(
                bundleIdentifier: bundleIdentifier,
                applicationName: name,
                frame: ScreenArrangement.flipVertically(accessibilityFrame, primaryTopY: primaryTopY),
                title: Accessibility.string(window, kAXTitleAttribute as String)
            )
        )
    }
}
