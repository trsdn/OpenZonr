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
/// ## Second use: right-clicks on the zoom button
///
/// Seit Issue #27 hört derselbe Tap zusätzlich auf `rightMouseDown` — nicht,
/// weil er begrifflich für Rechtsklicks zuständig wäre, sondern weil er der
/// einzige Ort im Programm ist, an dem Mausereignisse hereinkommen. Ein
/// zweiter Tap verlangte dieselbe Berechtigung noch einmal und wäre reine
/// Verdoppelung. Der Rechtsklick geht durch einen **eigenen** Rückruf
/// (``onRightClick``), damit die Zug-Zustandsmaschine unbehelligt bleibt.
/// Wichtig — und der Grund, warum die Zusicherung aus #26/#29 auch für diesen
/// Pfad gilt: die AX-Abfrage nach dem Zoom-Knopf läuft **nicht** im
/// Tap-Rückruf, sondern in `Task.detached`. Erst mit fertigem Ergebnis
/// springt der Pfad auf den MainActor zurück und ruft `onRightClick` auf.
/// Damit blockieren weder die Abfrage noch ein anschließendes modales
/// `NSMenu.popUp` den Thread, der den Tap bedient.
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
/// `.tapDisabledByTimeout` is handled rather than ignored — the tap is
/// re-enabled and a running drag is **kept**, because the mouse button is
/// still down and the gesture has only lost an observation, not itself.
/// See Issue #26 and `docs/dropzones.md`.
///
/// Listen-only heißt auch: der Rechtsklick kann nicht verschluckt werden.
/// Zeigt eine App selbst ein Menü auf Rechtsklick am Zoom-Knopf, erscheinen
/// zwei. Gemessen sind zwei Apps (TextEdit und Safari) ohne eigenes Menü,
/// nicht alle — das steht als *nicht gemessen* in der Doku, nicht als
/// Zusicherung.
@MainActor
public final class EventTapDragTracker: WindowDragTracker {

    public var onEvent: ((WindowDragEvent) -> Void)?
    public let name = "CGEventTap"

    /// Rückruf für Rechtsklicks — der Punkt in AppKit-Koordinaten (für die
    /// Menüposition) plus das **schon fertige** Ergebnis der AX-Abfrage.
    ///
    /// Warum das Ergebnis hier reinkommt und nicht der Empfänger nachzieht: die
    /// AX-Abfrage darf nicht im Tap-Rückruf laufen. Sie kostet gemessene
    /// Spitzen (bis 970 ms in Issue #26), und der Runloop, der den Tap bedient,
    /// ist derselbe, der ein `NSMenu.popUp` in seinen modalen Tracking-Loop
    /// zwingt. Beides zusammen im Rückruf hieße: dieselbe Klasse Fehler, die
    /// #29 für den Zug-Pfad geschlossen hat, für Rechtsklicks wieder offen.
    /// Deshalb macht der Tracker die Abfrage in `Task.detached` und ruft
    /// `onRightClick` erst mit dem Ergebnis auf dem MainActor auf.
    ///
    /// Warum getrennt vom Zug-Rückruf: ein Rechtsklick hat keinen Anfang, keine
    /// Bewegung und kein Ende. In die ``WindowDragEvent``-Zustandsmaschine
    /// gehört er nicht — der Tap ist nur zufällig ein guter Ort, um das
    /// Ereignis überhaupt zu sehen. Zwei Kanäle sind ehrlicher als ein
    /// überladener.
    public var onRightClick: ((_ appKitPoint: ScreenPoint, _ lookup: ZoomButtonLookup.Result) -> Void)?

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
    private var pressAccessibilityPoint: ScreenPoint?
    private var dragging = false

    /// Ergebnis der Fenster-Ermittlung, die parallel zum Zug läuft.
    ///
    /// Der Lookup wird beim `leftMouseDown` **außerhalb** des Tap-Rückrufs
    /// angestoßen (siehe `scheduleWindowLookup`). Bis die Mindeststrecke
    /// zurückgelegt ist, vergeht ohnehin Zeit; das Ergebnis liegt dann meist
    /// schon vor. Ist es noch nicht da, wartet der Tracker mit `.began`, bis
    /// entweder der Lookup fertig ist oder die Maustaste losgelassen wird.
    ///
    /// - `nil`: kein Lookup läuft (oder er ist noch nicht angestoßen).
    /// - `.some(nil)`: Lookup fertig, aber kein Fenster unter dem Druckpunkt.
    /// - `.some(.some(window))`: Fenster gefunden.
    private var pendingWindow: DraggedWindow??
    /// Zähler zum Verwerfen veralteter Lookup-Ergebnisse, falls in kurzer Folge
    /// mehrere Züge starten. Jedes `leftMouseDown` erhöht die Kennung; nur
    /// Ergebnisse mit passender Kennung werden angenommen.
    private var lookupToken: UInt64 = 0
    /// Wahr, sobald die Mindeststrecke überschritten wurde. Wird gebraucht,
    /// damit die Lookup-Fertigstellung selbst `.began` auslösen kann — sonst
    /// müsste der Nutzer die Maus nach der Fertigstellung noch einmal um ein
    /// Pixel bewegen, damit ein weiteres `leftMouseDragged` den Zustand
    /// prüft.
    private var readyToBegin = false
    /// Zuletzt gesehener Pointer‑ und Modifikatorzustand während des Zugs.
    /// Braucht die Lookup-Fertigstellung, um beim späten `.began` das
    /// unmittelbar folgende `.moved` mit dem aktuellen Punkt zu senden.
    private var lastDragPoint: ScreenPoint?
    private var lastDragModifiers: ModifierState = []

    /// Ermittelt das Fenster unter einem Punkt in **Accessibility**‑Koordinaten.
    /// Wird auf einem **Hintergrund-Thread** aufgerufen (via `Task.detached` in
    /// `scheduleWindowLookup`) — nicht auf dem MainActor, damit die AX-Spitzen
    /// (gemessen bis 970 ms in Issue #26) nicht den Runloop belegen, der den
    /// Tap bedient. Injizierbar, damit die Zustandsmaschine ohne echte
    /// AX-Abfrage getestet werden kann.
    private let windowLookup: @Sendable (ScreenPoint, Double) -> DraggedWindow?

    public convenience init(primaryTopY: Double) {
        self.init(primaryTopY: primaryTopY, windowLookup: Self.window(atAccessibilityPoint:primaryTopY:))
    }

    /// Testsaat: erlaubt es, den Fenster-Lookup durch eine synchrone Attrappe
    /// zu ersetzen und die Zustandsmaschine kopfweise durchzuspielen.
    init(
        primaryTopY: Double,
        windowLookup: @escaping @Sendable (ScreenPoint, Double) -> DraggedWindow?
    ) {
        self.primaryTopY = primaryTopY
        self.windowLookup = windowLookup
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
            | (1 << CGEventType.rightMouseDown.rawValue)

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
        pressAccessibilityPoint = nil
        pendingWindow = nil
        readyToBegin = false
        lastDragPoint = nil
        lastDragModifiers = []
        lookupToken &+= 1
        dragging = false
    }

    /// Reine Zustandslogik des Trackers. Testbar ohne echten `CGEvent`, weil
    /// alle relevanten Eingaben in ``Input`` abgebildet sind — inklusive des
    /// Timeout-Bescheids, der die tückische Ursache dieses Fehlers ist.
    enum Input {
        case mouseDown(point: ScreenPoint, accessibilityPoint: ScreenPoint)
        case mouseDragged(point: ScreenPoint, modifiers: ModifierState)
        case mouseUp(point: ScreenPoint, modifiers: ModifierState)
        /// macOS hat den Tap abgeschaltet, weil ein Rückruf zu lange brauchte.
        /// **Der Zug bleibt bestehen** — die Maustaste ist noch unten, nur
        /// unsere Beobachtung hatte einen Aussetzer.
        case tapDisabledByTimeout
        /// Der Nutzer (oder das System) hat den Tap abgeschaltet. Das ist ein
        /// echtes Ende der Beobachtung; ein laufender Zug wird abgebrochen.
        case tapDisabledByUserInput
    }

    /// Handles one event from the tap. Internal so the callback can reach it.
    func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout {
            handle(.tapDisabledByTimeout)
            return
        }
        if type == .tapDisabledByUserInput {
            handle(.tapDisabledByUserInput)
            return
        }

        let accessibilityPoint = ScreenPoint(x: event.location.x, y: event.location.y)
        let point = ScreenArrangement.flipVertically(accessibilityPoint, primaryTopY: primaryTopY)
        onRawEvent?(type, point, Self.latency(of: event))

        switch type {
        case .leftMouseDown:
            handle(.mouseDown(point: point, accessibilityPoint: accessibilityPoint))
        case .leftMouseDragged:
            handle(.mouseDragged(point: point, modifiers: Self.modifiers(of: event)))
        case .leftMouseUp:
            handle(.mouseUp(point: point, modifiers: Self.modifiers(of: event)))
        case .rightMouseDown:
            // Rechtsklick geht am Zug vorbei. Die AX-Abfrage darf hier nicht
            // synchron stehen — sonst blockiert der Rückruf den Runloop, der
            // den Tap bedient, und mit einem modalen `NSMenu.popUp` wäre die
            // Blockade so lang, wie das Menü offen ist. Deshalb: nur anstoßen,
            // der Rückruf an den Empfänger kommt erst mit fertigem Ergebnis
            // auf dem MainActor (siehe `scheduleZoomButtonLookup`).
            //
            // Der Tap ist `.listenOnly`, wir können den Klick nicht schlucken.
            // Zeigt eine andere App an derselben Stelle ihr eigenes Menü,
            // erscheinen zwei; gemessen sind zwei Apps (TextEdit, Safari)
            // ohne Menü, nicht alle. Siehe Issue #27 und `docs/dropzones.md`.
            scheduleZoomButtonLookup(at: accessibilityPoint, appKitPoint: point)
        default:
            break
        }
    }

    /// Wendet eine Eingabe auf die Zustandsmaschine an. Enthält die zwei
    /// Zusicherungen, die dieser Tracker einlösen muss:
    ///
    /// 1. Im Rückruf steht **keine** AX-Abfrage, deren Dauer von einer fremden
    ///    App abhängt — der Fenster-Lookup wird beim `mouseDown` als eigene
    ///    Task angestoßen (`scheduleWindowLookup`), nie hier synchron.
    ///    Dasselbe gilt für den Rechtsklick-Pfad: `scheduleZoomButtonLookup`
    ///    hebt AX-Abfrage **und** das anschließende `NSMenu.popUp` vom Tap-
    ///    Thread weg auf einen eigenen MainActor-Turn.
    /// 2. Ein Tap-Timeout bricht einen laufenden Zug **nicht** ab. Der Tap
    ///    wird wieder eingeschaltet, alles andere bleibt. Beim nächsten
    ///    `leftMouseDragged` wird nahtlos weitergemeldet.
    func handle(_ input: Input) {
        switch input {
        case .tapDisabledByTimeout:
            // Der Zug läuft physisch weiter — nur unsere Beobachtung hatte
            // einen Aussetzer. Wiedereinschalten, Zustand behalten.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            Log.detail("Ereignis-Tap wegen Timeout kurz abgeschaltet; Zug wird fortgesetzt.")

        case .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            if dragging {
                cancelDrag(reason: "Der Ereignis-Tap wurde vom System oder Nutzer abgeschaltet.")
            }

        case let .mouseDown(point, accessibilityPoint):
            // Falls ein voriger Zug „stehengeblieben" ist, weil sein Loslassen
            // im Timeout-Fenster verlorenging: jetzt ist er wirklich vorbei.
            if dragging {
                cancelDrag(reason: "Das Loslassen des vorigen Zugs ist im Ereignis-Tap verlorengegangen.")
            }
            pressLocation = point
            pressAccessibilityPoint = accessibilityPoint
            pendingWindow = nil
            readyToBegin = false
            lastDragPoint = nil
            lastDragModifiers = []
            dragging = false
            scheduleWindowLookup(at: accessibilityPoint)

        case let .mouseDragged(point, modifiers):
            guard let press = pressLocation else { return }
            lastDragPoint = point
            lastDragModifiers = modifiers
            if !dragging {
                if !readyToBegin {
                    guard DropzoneActivator.distance(from: press, to: point) >= minimumDragDistance else { return }
                    readyToBegin = true
                }
                // Sobald die Mindeststrecke da ist, hängt der Beginn nur noch
                // am Fenster-Lookup. Ist er fertig, geht es los; ist er noch
                // nicht fertig, warten wir. Die Fertigstellung selbst löst
                // den Beginn nach (`applyLookupResult`).
                guard let resolved = pendingWindow else { return }
                begin(with: resolved, at: press)
            }
            if dragging {
                onEvent?(.moved(point, modifiers: modifiers))
            }

        case let .mouseUp(point, modifiers):
            let wasDragging = dragging
            pressLocation = nil
            pressAccessibilityPoint = nil
            pendingWindow = nil
            readyToBegin = false
            lastDragPoint = nil
            lastDragModifiers = []
            lookupToken &+= 1
            dragging = false
            if wasDragging {
                onEvent?(.ended(point, modifiers: modifiers))
            }
        }
    }

    private func begin(with window: DraggedWindow?, at press: ScreenPoint) {
        guard let window else {
            // Kein Fenster unter dem Druckpunkt — ein Zug auf dem Schreibtisch,
            // in einer Textansicht, egal wo. Bis zum nächsten Druck nichts tun.
            pressLocation = nil
            pressAccessibilityPoint = nil
            readyToBegin = false
            return
        }
        dragging = true
        onEvent?(.began(window, at: press))
    }

    /// Stößt die AX-Abfrage außerhalb des Tap-Rückrufs **und außerhalb des
    /// Hauptthreads** an.
    ///
    /// Der Aufruf landet in `Task.detached` — auf einem Hintergrund-Thread. Der
    /// Rückruf ist längst zurückgekehrt, wenn die Abfrage läuft, und der
    /// Runloop des Hauptthreads bleibt frei, um den Tap zu bedienen und die
    /// Oberfläche zu zeichnen. Das Ergebnis kehrt über `Task { @MainActor }` in
    /// die Zustandsmaschine zurück.
    ///
    /// Warum nicht einfach `Task { @MainActor }`? Weil die AX-Abfrage dann auf
    /// genau dem Thread landet, dessen Runloop den Tap bedient — gemessene
    /// Spitzen bis 970 ms (Issue #26) hätten dort Ereignisse aufgestaut. Apples
    /// Accessibility-API ist dokumentiert threadsicher; der Nutzer hat vor dem
    /// Merge nachgemessen, dass ein Hintergrund-Aufruf dasselbe Ergebnis
    /// liefert (siehe PR-#28-Kommentar). Wichtig ist nicht die Geschwindigkeit,
    /// sondern wen die Spitze trifft: nicht mehr den Hauptthread.
    ///
    /// Ein Zähler verwirft veraltete Ergebnisse — falls in kurzer Folge ein
    /// zweiter `mouseDown` kommt (Doppelklick, neue Geste), zählt nur die
    /// letzte Abfrage.
    private func scheduleWindowLookup(at accessibilityPoint: ScreenPoint) {
        lookupToken &+= 1
        let token = lookupToken
        let pivot = primaryTopY
        let lookup = windowLookup
        Task.detached { [weak self] in
            let window = lookup(accessibilityPoint, pivot)
            await MainActor.run {
                self?.applyLookupResult(window, token: token)
            }
        }
    }

    /// Rechtsklick-Zwilling zu `scheduleWindowLookup`. Aus denselben Gründen:
    /// die AX-Abfrage darf nicht auf dem Thread laufen, der den Tap bedient,
    /// und `NSMenu.popUp` erst recht nicht (modaler Tracking-Loop). Nach der
    /// Abfrage kehrt der Pfad auf den MainActor zurück und ruft `onRightClick`
    /// dort auf. Das ist bewusst *kein* Weg über die Zug-Zustandsmaschine —
    /// Rechtsklicks stehen für sich.
    ///
    /// Der Rückruf bekommt das Ergebnis der Abfrage als `Result`, damit der
    /// Empfänger nichts mehr am AX-Baum tun muss und die Fallunterscheidung
    /// (Fenster / kein Zoom-Knopf / kein Fenster) an einer Stelle liegt.
    private func scheduleZoomButtonLookup(at accessibilityPoint: ScreenPoint, appKitPoint: ScreenPoint) {
        let pivot = primaryTopY
        Task.detached { [weak self] in
            let result = ZoomButtonLookup.read(
                atAccessibilityPoint: accessibilityPoint,
                primaryTopY: pivot
            )
            await MainActor.run {
                self?.onRightClick?(appKitPoint, result)
            }
        }
    }

    private func applyLookupResult(_ window: DraggedWindow?, token: UInt64) {
        guard token == lookupToken, let press = pressLocation else { return }
        pendingWindow = .some(window)
        // Wenn die Mindeststrecke schon überschritten wurde, während der
        // Lookup lief, geben wir `.began` jetzt selbst aus — sonst würde die
        // Geste erst beim nächsten `leftMouseDragged` beginnen, was den Nutzer
        // Pixel kosten kann.
        if !dragging, readyToBegin {
            begin(with: window, at: press)
            if dragging, let point = lastDragPoint {
                onEvent?(.moved(point, modifiers: lastDragModifiers))
            }
        }
    }

    private func cancelDrag(reason: String) {
        dragging = false
        pressLocation = nil
        pressAccessibilityPoint = nil
        pendingWindow = nil
        readyToBegin = false
        lastDragPoint = nil
        lastDragModifiers = []
        onEvent?(.cancelled(reason: reason))
    }

    // MARK: - Testsaat

    /// Gibt den aktuellen Lookup-Zähler frei. Für Tests, damit ein spätes
    /// Ergebnis mit dem "richtigen" Token eingespielt werden kann.
    var _testCurrentLookupToken: UInt64 { lookupToken }

    /// Ruft `applyLookupResult` direkt auf. Für Tests, weil `Task` erst nach
    /// dem Test-Frame läuft und sich damit nicht sinnvoll synchronisieren
    /// lässt.
    func _testApplyLookupResult(_ window: DraggedWindow?, token: UInt64) {
        applyLookupResult(window, token: token)
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
    ///
    /// **`nonisolated`, damit der Aufruf auf einem Hintergrund-Thread laufen
    /// kann.** Apples Accessibility-API ist dokumentiert threadsicher; das
    /// einzige, was hier vom Hauptthread abhängen könnte, wäre die Auswertung
    /// eines Ergebnisses in unserer Zustandsmaschine — die passiert getrennt in
    /// `applyLookupResult(_:token:)`. Siehe Issue #26 und den Kommentar in
    /// `scheduleWindowLookup`.
    nonisolated static func window(atAccessibilityPoint point: ScreenPoint, primaryTopY: Double) -> DraggedWindow? {
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
