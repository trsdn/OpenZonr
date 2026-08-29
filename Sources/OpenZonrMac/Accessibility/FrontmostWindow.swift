import AppKit
import ApplicationServices
import Foundation
import OpenZonrCore

/// The window the user is looking at right now.
///
/// ## Why this is not a right-click on the window
///
/// The concept and issue #9 describe the 90 % case as a **right click on a
/// placed window → „Diese App immer hier öffnen"**. Auf ein *beliebiges*
/// Pixel im Fenster ist das nicht mit Public API erreichbar: ein Menü in das
/// Ereignishandling einer fremden App zu injizieren geht nicht, und ein
/// transparentes Overlay über allen Bildschirmen würde Klicks schlucken, die
/// der App darunter gehören, und Screen Recording zusätzlich zur
/// Bedienungshilfen-Freigabe verlangen.
///
/// ``FrontmostWindow`` ist deshalb der **Tastatur-Weg** dieser Absicht: der
/// Nutzer bringt das Fenster nach vorn, wählt „Aktuelles Fenster hier
/// festhalten" aus dem Menüleisten-Menü, dieselbe Regel wird geschrieben. Ein
/// zweiter Weg — Rechtsklick auf den grünen Fensterknopf — kam mit Issue #27
/// hinzu (`ZoomButtonMenu`); er ist punktgenau, nicht flächig, deshalb ohne
/// Overlay und ohne fremdes Ereignishandling zu schlucken.
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
