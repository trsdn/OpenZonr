import AppKit
import ApplicationServices
import Foundation
import OpenZonrCore

/// Thin wrapper around the Accessibility C API.
///
/// Everything that talks to `AXUIElement` lives here so the rest of the tool
/// stays plain Swift values. The API is untyped and pointer based; keeping it in
/// one file makes the unsafe surface reviewable.
public enum Accessibility {

    /// Whether this process may read and control other applications' windows.
    ///
    /// - Parameter prompt: when `true`, macOS shows the system dialog that
    ///   deep-links into the settings pane. Only `watch` asks for it — the
    ///   diagnostic subcommands should not pop dialogs.
    public static func isTrusted(promptIfNeeded prompt: Bool = false) -> Bool {
        // The constant is a global `var` in the SDK and therefore not
        // concurrency-safe to reference; its value is fixed API.
        let options = ["AXTrustedCheckOptionPrompt": prompt]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Result of probing whether window access actually works.
    ///
    /// `AXIsProcessTrusted()` is not sufficient. On this machine it returns
    /// `true` while every application still answers `kAXWindowsAttribute` with a
    /// stub element whose role is `AXApplication` instead of its real windows —
    /// the permission is attributed to the launching terminal, not to this
    /// binary. Reporting "trusted" and then placing nothing would be the worst
    /// possible failure mode, so the tool probes for real data instead.
    public enum WindowAccess {
        /// Real window elements are readable.
        case granted
        /// `AXIsProcessTrusted()` is false — the permission was never given.
        case notTrusted
        /// Trusted on paper, but no application yields a real window element.
        case degraded
        /// No application was reachable to probe against.
        case inconclusive

        public var isUsable: Bool { self == .granted || self == .inconclusive }
    }

    /// Probes running applications until one yields a genuine window element.
    ///
    /// A single application without windows proves nothing, so the probe keeps
    /// looking and only reports `.degraded` when *every* candidate answers with
    /// something that is not a window.
    @MainActor
    public static func probeWindowAccess() -> WindowAccess {
        guard isTrusted() else { return .notTrusted }

        var sawApplication = false
        for application in NSWorkspace.shared.runningApplications
        where application.activationPolicy == .regular {
            sawApplication = true
            let element = AXUIElementCreateApplication(application.processIdentifier)
            for window in windows(of: element) {
                // A real window reports the window role and carries a position.
                // The degraded stub reports `AXApplication` (and Finder's
                // desktop reports `AXScrollArea`), so accept nothing else.
                let role = string(window, kAXRoleAttribute as String)
                if role == (kAXWindowRole as String), frame(of: window) != nil {
                    return .granted
                }
            }
        }
        return sawApplication ? .degraded : .inconclusive
    }

    /// German explanation of the degraded state, including how to escape it.
    ///
    /// The way out named here is the signed bundle, not "add this binary".
    /// Adding an unsigned build product was the advice for a long time and it
    /// does not hold: every rebuild produces a new checksum that is no longer
    /// recognised, so the grant appears to be there and does nothing.
    public static let degradedAccessInstructions = """
    Die Bedienungshilfen melden Vertrauen (AXIsProcessTrusted == true), liefern
    aber keine echten Fenster: jede App antwortet auf AXWindows nur mit einem
    Stellvertreter-Element der Rolle AXApplication.

    Das passiert, wenn die Berechtigung am startenden Programm hängt (Terminal,
    VS Code, ein Agent-Prozess) und nicht an diesem Programm selbst. Aus der
    Shell gestartet erbt der Prozess das Vertrauen des Terminals — deshalb
    meldet AXIsProcessTrusted() irreführend true, die Fensterzugriffe erben es
    aber nicht.

    Der verlässliche Weg ist das signierte Bundle, denn dessen Freigabe hängt
    an Pfad und Signatur und überlebt jeden Neubau:

      ./Scripts/bundle.sh
      # danach einmal freigeben: Systemeinstellungen → Datenschutz &
      # Sicherheit → Bedienungshilfen → "+" → ~/Applications/OpenZonr.app
      ~/Applications/OpenZonr.app/Contents/MacOS/OpenZonr windows --bundle com.apple.Safari

    Eine unsignierte Binärdatei einzutragen hilft dagegen nicht dauerhaft: sie
    bekommt bei jedem Neubau eine neue Prüfsumme, die nicht wiedererkannt wird.

    Zur Gegenprobe: 'openzonr windows' muss echte Fenster mit Subrolle
    AXStandardWindow und Größe anzeigen. Erscheint dort nur AXApplication mit
    0x0, ist der Zugriff weiterhin degradiert.
    """

    /// German instructions shown when the permission is missing.
    ///
    /// Spelled out rather than "permission denied", because the setting is four
    /// clicks deep and the tool is useless without it.
    ///
    /// The advice depends on how this process was started, because the wrong
    /// advice costs an hour: the grant is bound to a bundle at its path, so
    /// naming the terminal emulator is right for `swift run` and actively
    /// misleading for the shipped app. The running program is therefore named
    /// literally, rather than described.
    public static var permissionInstructions: String {
        let header = """
        Zugriff auf die Bedienungshilfen fehlt.

        OpenZonr kann Fenster nur bewegen, wenn das ausführende Programm als
        vertrauenswürdig eingetragen ist:

          1. Systemeinstellungen öffnen
          2. Datenschutz & Sicherheit → Bedienungshilfen
          3. Auf "+" klicken und das Programm hinzufügen
        """

        let body: String
        if let bundle = enclosingApplicationBundle() {
            body = """
            Hinzuzufügen ist genau dieses Bundle:

              \(bundle.path)

            Ein bestehender Eintrag aus einem unsignierten Lauf ist zu entfernen
            und neu hinzuzufügen; den Haken nur neu zu setzen genügt nicht.

            Die Freigabe gilt diesem Pfad, nicht dem Identifier allein. Solange
            hierhin gebaut wird, überlebt sie jeden Neubau — auch aus einem
            anderen Klon des Repos.
            """
        } else {
            body = """
            Dieses Programm läuft nicht aus einem App-Bundle:

              \(Bundle.main.executableURL?.path ?? CommandLine.arguments.first ?? "unbekannt")

            Beim Start über "swift run" ist das ausführende Programm nicht dieses
            Werkzeug, sondern das Terminal (bzw. iTerm, VS Code …), aus dem heraus
            es gestartet wurde. Eine unsignierte Binärdatei bekommt zudem bei jedem
            Neubau eine neue Prüfsumme, die nicht wiedererkannt wird.

            Der verlässliche Weg ist deshalb das signierte Bundle:

              ./Scripts/bundle.sh
              open -n ~/Applications/OpenZonr.app

            Dort einmal freigegeben, überlebt die Freigabe jeden Neubau.
            """
        }

        return header + "\n\n" + body
    }

    /// The `.app` bundle this executable lives in, if any.
    ///
    /// `Bundle.main` is unreliable here: for the command line inside the bundle
    /// it reports the bundle, but for a bare binary it reports the containing
    /// directory. The executable path is walked instead, which answers the only
    /// question that matters — is there something to add in the settings.
    public static func enclosingApplicationBundle() -> URL? {
        enclosingApplicationBundle(
            of: Bundle.main.executableURL?.resolvingSymlinksInPath()
        )
    }

    /// The `.app` bundle containing `executable`, if any. Split out so the
    /// walking can be tested without an actual bundle on disk.
    public static func enclosingApplicationBundle(of executable: URL?) -> URL? {
        var directory = executable?.deletingLastPathComponent()
        while let current = directory, current.path != "/", !current.path.isEmpty {
            if current.pathExtension == "app" { return current }
            let parent = current.deletingLastPathComponent()
            if parent == current { return nil }
            directory = parent
        }
        return nil
    }

    // MARK: - Attribute access

    public static func copyAttribute(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        return value
    }

    public static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copyAttribute(element, attribute) as? String
    }

    public static func windows(of application: AXUIElement) -> [AXUIElement] {
        copyAttribute(application, kAXWindowsAttribute as String) as? [AXUIElement] ?? []
    }

    /// Reads position and size and combines them into a frame.
    ///
    /// Accessibility keeps the two apart, and both are `AXValue` boxes rather
    /// than plain types — hence the unwrapping dance.
    public static func frame(of window: AXUIElement) -> WindowFrame? {
        guard
            let positionValue = copyAttribute(window, kAXPositionAttribute as String),
            let sizeValue = copyAttribute(window, kAXSizeAttribute as String)
        else { return nil }

        var point = CGPoint.zero
        var size = CGSize.zero
        guard
            CFGetTypeID(positionValue) == AXValueGetTypeID(),
            CFGetTypeID(sizeValue) == AXValueGetTypeID(),
            // swiftlint:disable:next force_cast
            AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
            AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }

        return WindowFrame(x: point.x, y: point.y, width: size.width, height: size.height)
    }

    /// Writes position, then size, then position again.
    ///
    /// The repetition is not superstition: an application may clamp a size that
    /// does not fit at the window's *previous* position — typically when the
    /// target display is larger than the current one — and it may nudge the
    /// position when the size changes. Writing position twice around the size
    /// makes the common case converge in a single attempt.
    @discardableResult
    public static func setFrame(_ frame: WindowFrame, on window: AXUIElement) -> Bool {
        var point = CGPoint(x: frame.x, y: frame.y)
        var size = CGSize(width: frame.width, height: frame.height)

        guard
            let positionValue = AXValueCreate(.cgPoint, &point),
            let sizeValue = AXValueCreate(.cgSize, &size)
        else { return false }

        let first = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)
        let second = AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        let third = AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, positionValue)

        return first == .success && second == .success && third == .success
    }

    public static func raise(_ window: AXUIElement, pid: pid_t) {
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        NSRunningApplication(processIdentifier: pid)?.activate()
    }
}

/// An Accessibility window that the placement logic can act on.
///
/// The class is the only implementation of ``PlaceableWindow`` that touches the
/// system; the tests use a fake that mimics self-resizing applications.
@MainActor
public final class AccessibilityWindow: PlaceableWindow {

    public let element: AXUIElement
    public private(set) var snapshot: WindowSnapshot

    public init(element: AXUIElement, snapshot: WindowSnapshot) {
        self.element = element
        self.snapshot = snapshot
    }

    public func readFrame() -> WindowFrame? {
        Accessibility.frame(of: element)
    }

    @discardableResult
    public func write(frame: WindowFrame) -> Bool {
        Accessibility.setFrame(frame, on: element)
    }
}
