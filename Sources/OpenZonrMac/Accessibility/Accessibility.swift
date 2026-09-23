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

    Wurde dagegen das signierte Bundle über LaunchServices gestartet
    (Elternprozess launchd; 'openzonr selftest' zeigt es unter "Start") und die
    Meldung kommt trotzdem, ist der Eintrag in den Bedienungshilfen ungültig
    geworden. Beobachtet am 30.08.2026 nach einem Neubau, bei dem Pfad,
    Identifier, Team und Designated Requirement unverändert waren; warum, ist
    nicht geklärt. Abhilfe: den vorhandenen Eintrag in den Bedienungshilfen
    ENTFERNEN und das Bundle neu hinzufügen. Den Haken nur aus- und wieder
    einzuschalten genügt nicht.

    Der verlässliche Weg ist das signierte Bundle, denn dessen Freigabe hängt
    an Pfad und Signatur und übersteht einen Neubau in der Regel (nicht
    zugesichert, siehe oben):

      ./Scripts/bundle.sh
      # danach einmal freigeben: Systemeinstellungen → Datenschutz &
      # Sicherheit → Bedienungshilfen → "+" → ~/Applications/OpenZonr.app
      ~/Applications/OpenZonr.app/Contents/MacOS/OpenZonrApp windows --bundle com.apple.Safari

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
            hierhin gebaut wird, übersteht sie einen Neubau in der Regel — auch
            aus einem anderen Klon des Repos. Meldet der Selbsttest nach einem
            Neubau trotzdem "degradiert", ist der Eintrag ungültig geworden:
            dann entfernen und neu hinzufügen, den Haken nur zu setzen genügt
            nicht.
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

            Dort einmal freigegeben, übersteht die Freigabe einen Neubau in der
            Regel. Meldet der Selbsttest danach trotzdem "degradiert", den
            Eintrag entfernen und neu hinzufügen.
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

    /// One write of a frame, as Accessibility splits it.
    ///
    /// Exists so the *order* can be tested without a live window: the order is
    /// the whole point of ``applyFrame(_:write:)``.
    public enum FrameWrite: Equatable {
        case position(CGPoint)
        case size(CGSize)
        /// Die Bedienungshilfen-Kennung der **Anwendung**, nicht des Fensters.
        case enhancedUserInterface(Bool)
    }

    /// Name der Kennung, mit der eine App erfährt, dass eine Bedienungshilfe
    /// zuschaut. Kein öffentliches Symbol — die Zeichenkette ist der Vertrag.
    static let enhancedUserInterfaceAttribute = "AXEnhancedUserInterface"

    /// Läuft gerade eine Bedienungshilfe, auf die ein Mensch angewiesen ist?
    ///
    /// Die Kennung abzuschalten ist für uns eine Beschleunigung, für VoiceOver
    /// oder die Schaltersteuerung aber die Sekunde, in der ihr Werkzeug
    /// ausfällt. In dem Fall bleibt sie stehen und die Platzierung nimmt den
    /// langsameren Weg über die Wiederholung.
    @MainActor
    static func assistiveTechnologyIsRunning() -> Bool {
        NSWorkspace.shared.isVoiceOverEnabled || NSWorkspace.shared.isSwitchControlEnabled
    }

    /// Writes position, then size. **Nothing after the size.**
    ///
    /// Position first, because a size is judged against the position the window
    /// currently has: an application may clamp a size that does not fit where
    /// the window still is, typically when the target display is larger than
    /// the current one. Moving first removes that reason to clamp.
    ///
    /// Nothing after the size, because the two attributes are not independent
    /// in every application. Safari re-derives its size as soon as a position
    /// is written afterwards and discards the size just set — while every
    /// single call still returns `.success`. Gemessen am 23.09.2026, Ziel
    /// `1340,277 966x688` aus `1280,227 1610x1147`, mit der echten
    /// Voreinstellung (`attempts 3`, `initialDelay 50 ms`, `interval 200 ms`,
    /// `tolerance 4`):
    ///
    /// | Folge            | V1       | V2       | V3       | Ergebnis       |
    /// |------------------|----------|----------|----------|----------------|
    /// | `pos, size, pos` | Abw. 607 | Abw. 607 | Abw. 607 | nie angenommen |
    /// | `pos, size`      | Abw. 60  | **0**    | —        | **angenommen** |
    ///
    /// Die frühere dritte Schreibung war als Abkürzung gedacht — sie sollte den
    /// Fall abfangen, dass eine App die Position verschiebt, wenn sich die
    /// Größe ändert, und „kostet nichts, wenn die App sich anständig verhält".
    /// Bei Safari kostete sie die gesamte Größenänderung: das Fenster sprang
    /// bei jedem Versuch an eine neue Stelle, ohne je die Größe anzunehmen.
    ///
    /// Der Fall, für den sie gedacht war, bleibt gedeckt — nur eine Runde
    /// später: verschiebt eine App sich beim Ändern der Größe, steht die Größe
    /// schon; beim nächsten Versuch von ``RetryingWindowPlacer`` ist die
    /// Größenschreibung folgenlos und die Position bleibt stehen. Genau so
    /// findet Safari im zweiten Versuch sein Ziel. Die Pause zwischen den
    /// Versuchen (200 ms) ist dabei das, was Safari braucht — zwei Schreibungen
    /// unmittelbar hintereinander verliert es.
    ///
    /// Kontrolle am selben Tag: Finder nimmt beide Folgen im ersten Versuch an.
    @MainActor
    @discardableResult
    public static func setFrame(_ frame: WindowFrame, on window: AXUIElement) -> Bool {
        // Die Kennung sitzt an der **Anwendung**, nicht am Fenster. Die PID
        // steht am Element selbst, deshalb braucht der Aufrufer nichts davon
        // zu wissen.
        var pid: pid_t = 0
        let application: AXUIElement? = AXUIElementGetPid(window, &pid) == .success
            ? AXUIElementCreateApplication(pid)
            : nil
        let enhancedWasOn = application
            .flatMap { copyAttribute($0, enhancedUserInterfaceAttribute) as? Bool } ?? false

        return applyFrame(
            frame,
            enhancedUserInterfaceWasOn: enhancedWasOn,
            maySuppressEnhancedUserInterface: !assistiveTechnologyIsRunning()
        ) { write in
            switch write {
            case var .position(point):
                guard let value = AXValueCreate(.cgPoint, &point) else { return false }
                return AXUIElementSetAttributeValue(
                    window, kAXPositionAttribute as CFString, value
                ) == .success
            case var .size(size):
                guard let value = AXValueCreate(.cgSize, &size) else { return false }
                return AXUIElementSetAttributeValue(
                    window, kAXSizeAttribute as CFString, value
                ) == .success
            case let .enhancedUserInterface(on):
                guard let application else { return false }
                return AXUIElementSetAttributeValue(
                    application,
                    enhancedUserInterfaceAttribute as CFString,
                    on ? kCFBooleanTrue : kCFBooleanFalse
                ) == .success
            }
        }
    }

    /// Die Schreibfolge, losgelöst vom lebenden Fenster.
    ///
    /// Beide Rahmen-Schreibungen laufen immer — eine gescheiterte Position darf
    /// die Größe nicht aufhalten, sonst bliebe das Fenster halb gesetzt stehen.
    /// Gemeldet wird trotzdem ein Fehlschlag, damit die Wiederholung greift.
    ///
    /// Um sie herum liegt die Kennung ``enhancedUserInterfaceAttribute``. Steht
    /// sie auf wahr, animiert Safari jede Rahmenänderung; die Größenschreibung
    /// landet dann mitten in der laufenden Animation und rechnet gegen eine
    /// Position, die es noch nicht gibt. Sichtbar wird das als Abweichung, die
    /// mit dem Abstand zwischen den Schreibungen stetig kleiner wird — gemessen
    /// am 23.09.2026 an Safari, eine Runde je Abstand:
    ///
    /// | Abstand | 0 | 10 | 20 | 30 | 40 | 50 | 70 | 100 |
    /// |---------|---|----|----|----|----|----|----|-----|
    /// | Abw.    | 85| 85 | 45 | 29 | 19 | 9  | 3  | 0   |
    ///
    /// Kennung aus heisst: keine Animation, also kein Abstand nötig. Je vier
    /// Runden, ein einziger Versuch, dasselbe Fenster:
    ///
    /// | Vorgehen                              | Treffer | grösste Abw. |
    /// |---------------------------------------|---------|--------------|
    /// | nur `pos, size`                       | 0/4     | 91           |
    /// | Kennung aus, `pos, size`, Kennung an  | **4/4** | **0**        |
    /// | `AXFrame` in einem Rutsch             | 0/4     | nicht setzbar (−25205) |
    ///
    /// Zwei Regeln, die nicht verhandelbar sind:
    ///
    /// * **Nur zurückschalten, was an war.** Eine App, die die Kennung nie
    ///   hatte, bekommt sie hier nicht eingeschaltet.
    /// * **Immer zurückschalten**, auch wenn eine Rahmen-Schreibung scheitert —
    ///   sonst hinterlässt jede misslungene Platzierung eine App mit
    ///   abgeschalteter Bedienungshilfen-Kennung. Ob das Zurückschalten selbst
    ///   gelingt, ändert das Urteil über die Platzierung nicht: das Fenster
    ///   sitzt ja.
    ///
    /// Läuft VoiceOver oder die Schaltersteuerung, unterbleibt der Eingriff
    /// ganz (`maySuppressEnhancedUserInterface`).
    static func applyFrame(
        _ frame: WindowFrame,
        enhancedUserInterfaceWasOn: Bool,
        maySuppressEnhancedUserInterface: Bool,
        write: (FrameWrite) -> Bool
    ) -> Bool {
        let suppressing = enhancedUserInterfaceWasOn && maySuppressEnhancedUserInterface
        if suppressing { _ = write(.enhancedUserInterface(false)) }

        let wrotePosition = write(.position(CGPoint(x: frame.x, y: frame.y)))
        let wroteSize = write(.size(CGSize(width: frame.width, height: frame.height)))

        if suppressing { _ = write(.enhancedUserInterface(true)) }
        return wrotePosition && wroteSize
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
