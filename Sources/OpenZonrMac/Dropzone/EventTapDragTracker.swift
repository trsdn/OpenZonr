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
/// Seit Issue #37 reicht das allein nicht für ein `.began`: Zeigerweg plus
/// AXWindow-Vorfahre gilt auch für Text markieren, eine Datei ziehen oder einen
/// Scrollbalken ziehen. Gemeldet wird erst, wenn der **Fensterrahmen** sich
/// bewegt hat (``WindowMoveEvidence``). Der Rahmen wird dafür während des Zugs
/// abgefragt — wie der Fenster-Lookup **nie** im Tap-Rückruf, sondern in
/// `Task.detached` (siehe `requestFrameSample`, #26). Nicht lesbarer Rahmen
/// heißt: kein Beleg, also kein Zug. Lieber eine Geste verpassen, als eine
/// fremde Textmarkierung zu einer Fensterplatzierung zu machen.
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

    /// Rückruf für einen Druck, der **nie** zu einem `.began` geführt hat.
    ///
    /// ``onEvent`` erzählt nur von Zügen, die es bis zum Bewegungsbeleg
    /// geschafft haben (#37). Genau die Drücke, die vorher stecken bleiben,
    /// sind aber die, über die der offene Fehler „die Zonen kommen nicht" zu
    /// klären ist — und die sind bisher komplett stumm. Ein eigener Kanal,
    /// damit die Zug-Zustandsmaschine unverändert bleibt.
    ///
    /// Höchstens **ein** Ergebnis je Druck, und nur, wenn die Mindeststrecke
    /// überhaupt erreicht wurde: sonst bekäme jeder gewöhnliche Klick einen
    /// Satz ins Menü. Gemeldet werden ausschliesslich die Fälle aus
    /// ``DragOutcome``, die der Tracker selbst entscheiden kann — kein
    /// AX-Aufruf im Tap-Rückruf, der Kanal reicht nur schon Gewusstes weiter.
    public var onOutcome: ((DragOutcome) -> Void)?

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

    /// Fenster, das aufgelöst wurde, dessen Bewegung aber noch nicht belegt ist
    /// (#37). Solange es gesetzt ist, wird kein `.began` gemeldet.
    private var candidate: DraggedWindow?
    /// Genau ein Rahmenabruf gleichzeitig; das Ergebnis löst den nächsten
    /// `leftMouseDragged` aus.
    private var sampleInFlight = false
    /// Nur zum Nachzählen (Tests, Diagnose) — die Obergrenze ist die Zeit,
    /// nicht diese Zahl.
    private var sampleCount = 0
    private var sampleToken: UInt64 = 0
    /// Zeitpunkt des ersten Rahmenabrufs dieses Drucks; der Anfang des Budgets.
    private var sampleWindowStart: ContinuousClock.Instant?
    /// Wahr, wenn für diesen Druck nichts mehr abzufragen ist: Budget
    /// aufgebraucht oder das Urteil steht schon fest (Kantenzug).
    private var samplingClosed = false

    /// Wahr, sobald dieser Druck sein Ergebnis gemeldet hat (oder zu einem
    /// echten Zug geworden ist, über den ``onEvent`` erzählt). Verhindert, dass
    /// ein Druck zwei Sätze produziert — etwa „Bewegung nicht erkannt" beim
    /// Budgetende und gleich danach „losgelassen" beim Loslassen.
    private var outcomeReported = false

    /// Zeitspanne ab dem **ersten** Rahmenabruf eines Drucks, in der der
    /// Tracker Belege sammelt.
    ///
    /// Eine Zahl von Abfragen taugt hier nicht: bei 8–16 ms Zugereignissen und
    /// wenigen Millisekunden je Abruf wären 30 Abrufe nach einer knappen halben
    /// Sekunde verbraucht — eine schwere App (Xcode, Electron), die genau diese
    /// halbe Sekunde hängt, verlöre die ganze Geste. Zeit misst das, worum es
    /// geht: wie lange wir einem Fenster zugestehen, dem Zeiger zu folgen.
    ///
    /// 2,5 s, begründet an der gemessenen AX-Spitze von 970 ms (Issue #26):
    /// zweieinhalb solcher Spitzen passen hinein, eine hängende App bekommt
    /// also mehr als einen Versuch. Nach oben begrenzt es den Preis eines
    /// Inhaltszugs — wer eine Minute lang Text markiert, zahlt AX-Abfragen nur
    /// für die ersten 2,5 s. Einen eigenen AX-Zustellzeitraum setzt dieses
    /// Programm nicht; es gilt die Systemvorgabe, und die ist länger als das
    /// Budget, weshalb eine späte Antwort über die Kennung verfällt statt das
    /// Budget zu verlängern.
    public var frameSampleBudget: Duration = .milliseconds(2500)

    /// Liest den aktuellen Rahmen des Fensters in **AppKit**-Koordinaten.
    /// Läuft wie `windowLookup` **nur** in `Task.detached` (siehe #26).
    private let frameSampler: @Sendable (DraggedWindow, Double) -> WindowFrame?

    /// Uhr für ``frameSampleBudget``. Injizierbar, damit ein Test einen langen
    /// Stillstand behaupten kann, ohne ihn abzuwarten.
    private let now: @MainActor () -> ContinuousClock.Instant

    /// Ermittelt das Fenster unter einem Punkt in **Accessibility**‑Koordinaten.
    /// Wird auf einem **Hintergrund-Thread** aufgerufen (via `Task.detached` in
    /// `scheduleWindowLookup`) — nicht auf dem MainActor, damit die AX-Spitzen
    /// (gemessen bis 970 ms in Issue #26) nicht den Runloop belegen, der den
    /// Tap bedient. Injizierbar, damit die Zustandsmaschine ohne echte
    /// AX-Abfrage getestet werden kann.
    private let windowLookup: @Sendable (ScreenPoint, Double) -> DraggedWindow?

    /// Dicke der Menüleiste, in **CG**-Koordinaten (Ursprung oben links, wie
    /// `accessibilityPoint`) — also einfach die Anzahl Punkte von oben. Real
    /// `NSStatusBar.system.thickness`; injizierbar, damit ein Test den Schutz
    /// gezielt an- und ausschalten kann, ohne AppKit zu brauchen.
    private let menuBarThickness: @MainActor () -> Double

    public convenience init(primaryTopY: Double) {
        self.init(
            primaryTopY: primaryTopY,
            windowLookup: Self.window(atAccessibilityPoint:primaryTopY:),
            frameSampler: Self.currentFrame(of:primaryTopY:),
            menuBarThickness: { NSStatusBar.system.thickness }
        )
    }

    /// Testsaat: Fenster-Lookup und Rahmenabruf durch Attrappen ersetzen und
    /// die Zustandsmaschine kopfweise durchspielen. `menuBarThickness` steht
    /// hier auf `0` — der Schutz aus #69 bleibt in bestehenden Tests aus, die
    /// wie üblich mit `y: 0` drücken; ein eigener Test schaltet ihn gezielt an.
    init(
        primaryTopY: Double,
        windowLookup: @escaping @Sendable (ScreenPoint, Double) -> DraggedWindow?,
        frameSampler: @escaping @Sendable (DraggedWindow, Double) -> WindowFrame? = { _, _ in nil },
        now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now },
        menuBarThickness: @escaping @MainActor () -> Double = { 0 }
    ) {
        self.primaryTopY = primaryTopY
        self.windowLookup = windowLookup
        self.frameSampler = frameSampler
        self.now = now
        self.menuBarThickness = menuBarThickness
    }

    /// Reiner Geometrie-Check, ohne AppKit: liegt `y` im obersten Streifen, der
    /// der Menüleiste vorbehalten ist? `accessibilityPoint` hat denselben
    /// Ursprung (oben links) wie `CGEvent.location`, aus dem er stammt.
    static func isWithinMenuBarStrip(y: Double, menuBarThickness: Double) -> Bool {
        y >= 0 && y < menuBarThickness
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
        resetMovementEvidence()
        outcomeReported = true
        dragging = false
    }

    /// Meldet das Ergebnis dieses Drucks — höchstens einmal.
    private func report(_ outcome: DragOutcome) {
        guard !outcomeReported else { return }
        outcomeReported = true
        onOutcome?(outcome)
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
            outcomeReported = false
            resetMovementEvidence()
            if Self.isWithinMenuBarStrip(y: accessibilityPoint.y, menuBarThickness: menuBarThickness()) {
                // Kein App-Fenster beginnt unter der Menüleiste, und die
                // Positionsabfrage genau dort ist eine gemessene Absturzquelle
                // (Issue #69): `AXUIElementCopyElementAtPosition` über einem
                // Statuselement lässt AppKits eigenen Bedienungshilfen-Code
                // (`NSAccessibilityMockStatusBarItem`) intern abstürzen. Der
                // Aufruf bleibt deshalb ganz aus; derselbe Tokenwechsel wie in
                // `scheduleWindowLookup` verwirft trotzdem jeden noch
                // ausstehenden Lookup aus einem vorigen Druck.
                lookupToken &+= 1
                applyLookupResult(nil, token: lookupToken)
            } else {
                scheduleWindowLookup(at: accessibilityPoint)
            }

        case let .mouseDragged(point, modifiers):
            guard let press = pressLocation else { return }
            lastDragPoint = point
            lastDragModifiers = modifiers
            if !dragging {
                if !readyToBegin {
                    guard DropzoneActivator.distance(from: press, to: point) >= minimumDragDistance else { return }
                    readyToBegin = true
                }
                // Sobald die Mindeststrecke da ist, hängt der Beginn am
                // Fenster-Lookup **und** am Bewegungsbeleg (#37). Ist der
                // Lookup noch nicht fertig, warten wir; seine Fertigstellung
                // stößt den Beleg selbst an (`applyLookupResult`). Jedes
                // weitere `leftMouseDragged` fragt einen neuen Rahmen ab,
                // solange keiner die Bewegung belegt hat — der Beleg kann
                // erst später eintreffen (Fenster klemmt, App hinkt nach).
                guard let resolved = pendingWindow else { return }
                considerBegin(resolved, at: press)
            }
            if dragging {
                onEvent?(.moved(point, modifiers: modifiers))
            }

        case let .mouseUp(point, modifiers):
            let wasDragging = dragging
            // Nur wenn überhaupt gezogen wurde: ein gewöhnlicher Klick hat kein
            // Ergebnis zu melden. `readyToBegin` heisst genau „die
            // Mindeststrecke war da, es hat aber nicht gereicht".
            if !wasDragging, readyToBegin {
                report(.releasedBeforeEvidence)
            }
            pressLocation = nil
            pressAccessibilityPoint = nil
            pendingWindow = nil
            readyToBegin = false
            lastDragPoint = nil
            lastDragModifiers = []
            lookupToken &+= 1
            resetMovementEvidence()
            dragging = false
            if wasDragging {
                onEvent?(.ended(point, modifiers: modifiers))
            }
        }
    }

    private func begin(with window: DraggedWindow?, at press: ScreenPoint) {
        guard let window else {
            // Kein Fenster unter dem Druckpunkt — ein Zug auf dem Schreibtisch,
            // in einer Textansicht, egal wo. Bis zum nächsten Druck nichts tun,
            // ausser es zu sagen: genau dieser Fall sieht von aussen aus wie
            // „die Zonen kommen nicht".
            report(.noWindowFound)
            pressLocation = nil
            pressAccessibilityPoint = nil
            readyToBegin = false
            return
        }
        dragging = true
        // Ab hier erzählt `onEvent`; der Druck hat kein eigenes Ergebnis mehr.
        outcomeReported = true
        onEvent?(.began(window, at: press))
    }

    /// Kein Fenster: still verwerfen wie bisher. Fenster gefunden: Beleg holen,
    /// `.began` erst mit Beleg (`applyFrameSample`). Läuft im Tap-Rückruf und
    /// stößt deshalb nur eine losgelöste Task an.
    private func considerBegin(_ window: DraggedWindow?, at press: ScreenPoint) {
        guard let window else {
            begin(with: nil, at: press)
            return
        }
        if candidate == nil { candidate = window }
        requestFrameSample()
    }

    /// Fragt den Fensterrahmen **außerhalb** des Tap-Rückrufs ab (#26/#37).
    /// Die Abfrage ist ein AX-Aufruf mit unbekannter Dauer, deshalb
    /// `Task.detached` wie bei `scheduleWindowLookup`; nie synchron hier.
    ///
    /// Zwei Grenzen: höchstens **ein** Abruf gleichzeitig — der nächste startet
    /// erst, wenn der vorige zurück ist, womit die AX-Umlaufzeit selbst den
    /// Takt vorgibt — und nur innerhalb von ``frameSampleBudget`` ab dem ersten
    /// Abruf dieses Drucks. Ein Inhaltszug (Text markieren, Scrollbalken) soll
    /// nicht für seine ganze Dauer AX-Abfragen erzeugen.
    private func requestFrameSample() {
        guard let window = candidate, !sampleInFlight, !samplingClosed else { return }
        let instant = now()
        if let start = sampleWindowStart {
            guard instant - start < frameSampleBudget else {
                // Aufgebraucht. Fail closed: lieber keine Geste als eine, die
                // wir nicht belegen konnten — aber nicht stumm, sonst bleibt
                // „es passiert nichts" unerklärt.
                samplingClosed = true
                report(.noMovementEvidence(.budgetExhausted))
                return
            }
        } else {
            sampleWindowStart = instant
        }
        sampleInFlight = true
        sampleCount += 1
        let token = sampleToken
        let pivot = primaryTopY
        let sampler = frameSampler
        let pointer = lastDragPoint ?? pressLocation ?? ScreenPoint(x: 0, y: 0)
        Task.detached { [weak self] in
            let frame = sampler(window, pivot)
            await self?.applyFrameSample(frame, pointer: pointer, token: token)
        }
    }

    /// Nimmt einen Rahmen entgegen und entscheidet, ob er den Zug belegt.
    ///
    /// Die Kennung verwirft Belege aus einem früheren Druck: zwischen Anstoß
    /// und Rückkehr kann die Geste längst vorbei sein.
    private func applyFrameSample(_ frame: WindowFrame?, pointer: ScreenPoint, token: UInt64) {
        guard token == sampleToken, let window = candidate, let press = pressLocation, !dragging else { return }
        sampleInFlight = false
        // Nicht lesbar: kein Beleg. Das nächste `leftMouseDragged` fragt neu.
        guard let frame else { return }
        let verdict = WindowMoveEvidence.classify(
            initial: window.frame, current: frame, pointerFrom: press, pointerTo: pointer
        )
        // Ein Kantenzug bleibt einer, bis die Taste losgelassen wird: die
        // Größe ändert sich, der Ursprung ist nicht der Beleg. Weiter zu
        // fragen kostet AX-Abfragen ohne mögliche Antwort.
        if verdict == .resized {
            samplingClosed = true
            report(.noMovementEvidence(.resizedInstead))
        }
        guard verdict == .moved else { return }
        candidate = nil
        begin(with: window, at: press)
        if dragging, let point = lastDragPoint {
            onEvent?(.moved(point, modifiers: lastDragModifiers))
        }
    }

    /// Setzt alles zurück, was am Bewegungsbeleg hängt. Die erhöhte Kennung
    /// macht einen noch laufenden Abruf wirkungslos.
    private func resetMovementEvidence() {
        candidate = nil
        sampleInFlight = false
        sampleCount = 0
        sampleWindowStart = nil
        samplingClosed = false
        sampleToken &+= 1
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
            await self?.applyLookupResult(window, token: token)
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
            await self?.deliverRightClick(appKitPoint, result)
        }
    }

    /// Reicht das fertige Ergebnis auf dem MainActor an `onRightClick` weiter.
    ///
    /// Eine eigene Methode statt `MainActor.run { self?.onRightClick?(…) }`: der
    /// ältere Compiler der Release-Runner (`macos-15`) lehnt `self` in dieser
    /// Closure als möglichen Data Race ab („sending 'self' risks causing data
    /// races“). Der `await` auf eine MainActor-Methode braucht keine Closure.
    private func deliverRightClick(_ appKitPoint: ScreenPoint, _ result: ZoomButtonLookup.Result) {
        onRightClick?(appKitPoint, result)
    }

    private func applyLookupResult(_ window: DraggedWindow?, token: UInt64) {
        guard token == lookupToken, let press = pressLocation else { return }
        pendingWindow = .some(window)
        // Wenn die Mindeststrecke schon überschritten wurde, während der
        // Lookup lief, holen wir den Bewegungsbeleg jetzt selbst — sonst
        // begänne die Geste erst beim nächsten `leftMouseDragged`, was den
        // Nutzer Pixel kostet. Das `.began` folgt mit dem Beleg
        // (`applyFrameSample`), nicht schon hier.
        if !dragging, readyToBegin {
            considerBegin(window, at: press)
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
        resetMovementEvidence()
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

    /// Ob der Lookup für den aktuellen Druck schon aufgelöst ist. Unterscheidet
    /// deterministisch den Menüleisten-Schutz (#69, löst synchron auf) von
    /// `scheduleWindowLookup` (bleibt bis zum Ergebnis der losgelösten Task auf
    /// „noch nicht aufgelöst“ stehen) — ein Test kann so ohne Rennen auf das
    /// Ergebnis der echten Task warten müssen.
    var _testPendingWindowIsResolved: Bool { pendingWindow != nil }

    /// Gibt die Kennung des laufenden Rahmenabrufs frei. Für Tests, damit ein
    /// Beleg mit passender — oder bewusst veralteter — Kennung ankommt.
    var _testCurrentSampleToken: UInt64 { sampleToken }

    /// Zahl der angestoßenen Rahmenabrufe im laufenden Druck. Für Tests, die
    /// belegen, dass nach Budgetende oder Kantenzug keiner mehr dazukommt.
    var _testFrameSampleRequests: Int { sampleCount }

    /// Spielt einen Rahmenbeleg ein, wie es die losgelöste Task täte.
    func _testApplyFrameSample(_ frame: WindowFrame?, pointer: ScreenPoint, token: UInt64) {
        applyFrameSample(frame, pointer: pointer, token: token)
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

    /// Der Rahmen des Fensters jetzt, in **AppKit**-Koordinaten.
    ///
    /// `nonisolated`, weil er auf einem Hintergrund-Thread läuft (siehe
    /// `requestFrameSample`); `nil`, wenn die App den Rahmen nicht preisgibt.
    nonisolated static func currentFrame(of window: DraggedWindow, primaryTopY: Double) -> WindowFrame? {
        guard let frame = Accessibility.frame(of: window.element) else { return nil }
        return ScreenArrangement.flipVertically(frame, primaryTopY: primaryTopY)
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
