import ApplicationServices
import Foundation
import Testing

@testable import OpenZonrCore
@testable import OpenZonrMac

/// Die Zustandsmaschine von ``EventTapDragTracker`` ist reine Logik, sobald der
/// Fenster-Lookup und der Timeout-Fall als Eingaben modellierbar sind. Genau
/// dort landet der Beleg für die zwei Zusicherungen aus Issue #26:
///
/// - **A.** Der Fenster-Lookup wird nie synchron aus dem Rückruf aufgerufen —
///   messbar daran, dass ``EventTapDragTracker.handle(_:)`` selbst dann sofort
///   zurückkehrt, wenn der Lookup lange braucht, und `.began` erst später
///   erscheint, wenn sein Ergebnis vorliegt.
/// - **B.** Ein Tap-Timeout bricht einen laufenden Zug **nicht** ab. Der
///   Zustand bleibt bestehen, das nächste `leftMouseDragged` liefert weiter
///   `.moved`.
@Suite("EventTapDragTracker Zustandsmaschine")
@MainActor
struct EventTapDragTrackerTests {

    private func makeWindow() -> DraggedWindow {
        DraggedWindow(
            element: AXUIElementCreateSystemWide(),
            processIdentifier: 42,
            bundleIdentifier: "com.example.test",
            applicationName: "Test",
            frame: WindowFrame(x: 0, y: 0, width: 100, height: 100)
        )
    }

    /// Setzt einen Tracker mit synchronem Lookup‑Doppel auf und sammelt die
    /// gemeldeten Ereignisse. Ein Lookup, der `nil` zurückgibt, verhält sich
    /// wie ein Druck auf den Schreibtisch.
    private func makeTracker(
        window: DraggedWindow? = nil,
        lookup: (@Sendable (ScreenPoint, Double) -> DraggedWindow?)? = nil,
        frameSampler: @escaping @Sendable (DraggedWindow, Double) -> WindowFrame? = { _, _ in nil }
    ) -> (tracker: EventTapDragTracker, events: EventBox) {
        let box = EventBox()
        let captured = window
        let resolver: @Sendable (ScreenPoint, Double) -> DraggedWindow? = lookup ?? { _, _ in captured }
        let tracker = EventTapDragTracker(primaryTopY: 0, windowLookup: resolver, frameSampler: frameSampler)
        tracker.minimumDragDistance = 5
        tracker.onEvent = { event in box.append(event) }
        return (tracker, box)
    }

    /// Window frame after the title bar was dragged `dx` points to the right.
    private func frame(movedBy dx: Double) -> WindowFrame {
        WindowFrame(x: 0 + dx, y: 0, width: 100, height: 100)
    }

    /// Sammelt Ereignisse und macht sie beobachtbar. Ein eigener Typ, damit die
    /// Tests keine Closures über veränderbare Arrays reichen müssen.
    @MainActor
    final class EventBox {
        private(set) var events: [WindowDragEvent] = []
        func append(_ event: WindowDragEvent) { events.append(event) }
        var kinds: [String] {
            events.map {
                switch $0 {
                case .began: return "began"
                case .moved: return "moved"
                case .ended: return "ended"
                case .cancelled: return "cancelled"
                }
            }
        }
    }

    // MARK: - Fehler A: Lookup nicht im Rückruf

    @Test("Ein synchroner Lookup führt zu einem synchronen Beginn — Referenzfall")
    func synchronousLookupBeginsImmediately() {
        let window = makeWindow()
        let (tracker, box) = makeTracker(window: window)

        tracker.handle(.mouseDown(point: ScreenPoint(x: 100, y: 100), accessibilityPoint: ScreenPoint(x: 100, y: 100)))
        // Der Lookup läuft in einer MainActor-Task — bis dahin passiert nichts.
        #expect(box.events.isEmpty)
        // Erst ein Dragged nach Fertigstellung des Lookups löst `.began` aus.
        // Für die Zustandsmaschine spielen wir die Fertigstellung von Hand
        // ein, weil `Task` erst nach dieser Testfunktion läuft.
        tracker.applyLookupResultForTest(window)
        tracker.handle(.mouseDragged(point: ScreenPoint(x: 110, y: 100), modifiers: []))
        tracker.applyFrameSampleForTest(frame(movedBy: 10), pointer: ScreenPoint(x: 110, y: 100))

        #expect(box.kinds == ["began", "moved"])
    }

    @Test("Beginnt nach spätem Lookup ohne weitere Mausbewegung")
    func lateLookupTriggersBeginOnItsOwn() {
        // Kern des Fixes: die AX-Abfrage dauert, der Nutzer hat aber die
        // Mindeststrecke längst überschritten. Wenn der Lookup fertig wird,
        // muss `.began` sofort nachgereicht werden — sonst geht das Overlay
        // erst mit dem *nächsten* Mausereignis an, was Pixel kostet.
        let window = makeWindow()
        let (tracker, box) = makeTracker(window: window)

        tracker.handle(.mouseDown(point: ScreenPoint(x: 0, y: 0), accessibilityPoint: ScreenPoint(x: 0, y: 0)))
        tracker.handle(.mouseDragged(point: ScreenPoint(x: 50, y: 0), modifiers: []))
        #expect(box.events.isEmpty, "Solange der Lookup nicht antwortet, wird nichts gemeldet.")

        tracker.applyLookupResultForTest(window)
        tracker.applyFrameSampleForTest(frame(movedBy: 50), pointer: ScreenPoint(x: 50, y: 0))

        #expect(box.kinds == ["began", "moved"], "Sobald der Lookup fertig ist, wird der Beginn nachgereicht.")
    }

    @Test("Kein Fenster unter dem Druckpunkt — Beginn unterbleibt still")
    func noWindowMeansNoBegin() {
        let (tracker, box) = makeTracker(window: nil)

        tracker.handle(.mouseDown(point: ScreenPoint(x: 0, y: 0), accessibilityPoint: ScreenPoint(x: 0, y: 0)))
        tracker.applyLookupResultForTest(nil)
        tracker.handle(.mouseDragged(point: ScreenPoint(x: 50, y: 0), modifiers: []))
        tracker.handle(.mouseUp(point: ScreenPoint(x: 50, y: 0), modifiers: []))

        #expect(box.events.isEmpty)
    }

    // MARK: - Fehler B: Timeout beendet den Zug nicht

    @Test("Ein Timeout mitten im Zug beendet den Zug nicht")
    func timeoutDoesNotCancelDrag() {
        // Das ist der harte Beleg für Fehler B aus Issue #26.
        let window = makeWindow()
        let (tracker, box) = makeTracker(window: window)

        tracker.handle(.mouseDown(point: ScreenPoint(x: 0, y: 0), accessibilityPoint: ScreenPoint(x: 0, y: 0)))
        tracker.applyLookupResultForTest(window)
        tracker.handle(.mouseDragged(point: ScreenPoint(x: 50, y: 0), modifiers: []))
        tracker.applyFrameSampleForTest(frame(movedBy: 50), pointer: ScreenPoint(x: 50, y: 0))
        #expect(box.kinds == ["began", "moved"])

        // Der Bescheid trifft ein. Vorher: `.cancelled` — mit diesem Fix:
        // gar nichts. Der Zug läuft weiter.
        tracker.handle(.tapDisabledByTimeout)
        #expect(box.kinds == ["began", "moved"], "Ein Timeout darf keinen Abbruch erzeugen.")

        // Der nächste Drag muss ganz normal ein `.moved` liefern.
        tracker.handle(.mouseDragged(point: ScreenPoint(x: 60, y: 0), modifiers: [.command]))
        #expect(box.kinds == ["began", "moved", "moved"])

        // Und das Loslassen kommt regulär.
        tracker.handle(.mouseUp(point: ScreenPoint(x: 60, y: 0), modifiers: [.command]))
        #expect(box.kinds == ["began", "moved", "moved", "ended"])
    }

    @Test("Verliert das Loslassen im Timeout-Fenster, wird der nächste Druck als Sturz erkannt")
    func lostMouseUpIsRecognisedOnNextPress() {
        // Kann passieren, wenn genau der `mouseUp` in einem Frame liegt, in
        // dem der Tap abgeschaltet ist. Statt für immer im Zug festzuhängen,
        // sagen wir es ehrlich beim nächsten `mouseDown`.
        let window = makeWindow()
        let (tracker, box) = makeTracker(window: window)

        tracker.handle(.mouseDown(point: ScreenPoint(x: 0, y: 0), accessibilityPoint: ScreenPoint(x: 0, y: 0)))
        tracker.applyLookupResultForTest(window)
        tracker.handle(.mouseDragged(point: ScreenPoint(x: 50, y: 0), modifiers: []))
        tracker.applyFrameSampleForTest(frame(movedBy: 50), pointer: ScreenPoint(x: 50, y: 0))
        #expect(box.kinds == ["began", "moved"])

        // Timeout kurz vor dem Loslassen — der Tap ist wieder da, aber das
        // `mouseUp` selbst hat der Tap nie gesehen.
        tracker.handle(.tapDisabledByTimeout)

        // Neue Geste beginnt.
        tracker.handle(.mouseDown(point: ScreenPoint(x: 200, y: 200), accessibilityPoint: ScreenPoint(x: 200, y: 200)))
        #expect(box.kinds == ["began", "moved", "cancelled"], "Der alte Zug wird beim nächsten Druck sauber beendet.")
    }

    @Test("Ein Abbruch durch den Nutzer beendet den Zug")
    func userInputDisableCancels() {
        // `tapDisabledByUserInput` bedeutet, dass der Nutzer die Beobachtung
        // wirklich unterbrochen hat (oder das System sie entzogen). Anders
        // als beim Timeout ist der Zug damit tot.
        let window = makeWindow()
        let (tracker, box) = makeTracker(window: window)

        tracker.handle(.mouseDown(point: ScreenPoint(x: 0, y: 0), accessibilityPoint: ScreenPoint(x: 0, y: 0)))
        tracker.applyLookupResultForTest(window)
        tracker.handle(.mouseDragged(point: ScreenPoint(x: 50, y: 0), modifiers: []))
        tracker.applyFrameSampleForTest(frame(movedBy: 50), pointer: ScreenPoint(x: 50, y: 0))

        tracker.handle(.tapDisabledByUserInput)
        #expect(box.kinds == ["began", "moved", "cancelled"])
    }

    // MARK: - Kleinigkeiten

    @Test("Ein zweiter mouseDown während ausstehendem Lookup verwirft das erste Ergebnis")
    func staleLookupIsDiscarded() {
        let first = makeWindow()
        let second = makeWindow()
        let (tracker, box) = makeTracker(window: nil)

        tracker.handle(.mouseDown(point: ScreenPoint(x: 0, y: 0), accessibilityPoint: ScreenPoint(x: 0, y: 0)))
        // Der Nutzer klickt gleich wieder — der erste Lookup ist damit veraltet.
        tracker.handle(.mouseDown(point: ScreenPoint(x: 200, y: 0), accessibilityPoint: ScreenPoint(x: 200, y: 0)))

        // Ein spätes Ergebnis der ersten Abfrage darf nicht mehr wirken.
        tracker.applyLookupResultForTest(first, useCurrentToken: false)
        tracker.handle(.mouseDragged(point: ScreenPoint(x: 250, y: 0), modifiers: []))
        #expect(box.events.isEmpty)

        // Das Ergebnis der zweiten Abfrage schon. `.began` kommt für den
        // Druckpunkt, und weil der Nutzer in der Zwischenzeit weitergezogen
        // hat, wird das nachgehaltene `.moved` unmittelbar nachgereicht.
        tracker.applyLookupResultForTest(second)
        tracker.applyFrameSampleForTest(frame(movedBy: 50), pointer: ScreenPoint(x: 250, y: 0))
        #expect(box.kinds == ["began", "moved"])
    }

    // MARK: - #37: Bewegungsbeleg

    @Test("Inhaltszug: Rahmen bleibt stehen -> kein began, kein ended")
    func contentDragNeverBegins() {
        let window = makeWindow()
        let (tracker, box) = makeTracker(window: window)

        tracker.handle(.mouseDown(point: ScreenPoint(x: 10, y: 10), accessibilityPoint: ScreenPoint(x: 10, y: 10)))
        tracker.applyLookupResultForTest(window)
        tracker.handle(.mouseDragged(point: ScreenPoint(x: 80, y: 10), modifiers: []))
        tracker.applyFrameSampleForTest(window.frame, pointer: ScreenPoint(x: 80, y: 10))
        tracker.handle(.mouseDragged(point: ScreenPoint(x: 300, y: 200), modifiers: []))
        tracker.applyFrameSampleForTest(window.frame, pointer: ScreenPoint(x: 300, y: 200))
        tracker.handle(.mouseUp(point: ScreenPoint(x: 300, y: 200), modifiers: []))

        #expect(box.events.isEmpty, "Ohne Fensterbewegung darf nichts platziert oder angeheftet werden.")
    }

    @Test("Spaeter Beleg: erst Inhaltszug-Rahmen, dann folgt das Fenster -> began")
    func evidenceArrivingLaterStillBegins() {
        let window = makeWindow()
        let (tracker, box) = makeTracker(window: window)

        tracker.handle(.mouseDown(point: ScreenPoint(x: 0, y: 0), accessibilityPoint: ScreenPoint(x: 0, y: 0)))
        tracker.applyLookupResultForTest(window)
        tracker.handle(.mouseDragged(point: ScreenPoint(x: 20, y: 0), modifiers: []))
        tracker.applyFrameSampleForTest(window.frame, pointer: ScreenPoint(x: 20, y: 0))
        #expect(box.events.isEmpty)

        tracker.handle(.mouseDragged(point: ScreenPoint(x: 60, y: 0), modifiers: [.command]))
        tracker.applyFrameSampleForTest(frame(movedBy: 60), pointer: ScreenPoint(x: 60, y: 0))
        #expect(box.kinds == ["began", "moved"])
    }

    @Test("Kantenzug (Groesse aendert sich) und nicht lesbarer Rahmen begruenden keinen Zug")
    func resizeAndUnreadableFrameDoNotBegin() {
        let window = makeWindow()
        let (tracker, box) = makeTracker(window: window)

        tracker.handle(.mouseDown(point: ScreenPoint(x: 100, y: 50), accessibilityPoint: ScreenPoint(x: 100, y: 50)))
        tracker.applyLookupResultForTest(window)
        tracker.handle(.mouseDragged(point: ScreenPoint(x: 160, y: 50), modifiers: []))
        tracker.applyFrameSampleForTest(
            WindowFrame(x: 0, y: 0, width: 160, height: 100), pointer: ScreenPoint(x: 160, y: 50))
        tracker.applyFrameSampleForTest(nil, pointer: ScreenPoint(x: 160, y: 50))
        tracker.handle(.mouseUp(point: ScreenPoint(x: 160, y: 50), modifiers: []))

        #expect(box.events.isEmpty)
    }

    @Test("Ein Beleg aus einem frueheren Druck wird verworfen")
    func staleFrameSampleIsDiscarded() {
        let window = makeWindow()
        let (tracker, box) = makeTracker(window: window)

        tracker.handle(.mouseDown(point: ScreenPoint(x: 0, y: 0), accessibilityPoint: ScreenPoint(x: 0, y: 0)))
        tracker.applyLookupResultForTest(window)
        tracker.handle(.mouseDragged(point: ScreenPoint(x: 50, y: 0), modifiers: []))
        let oldToken = tracker._testCurrentSampleToken
        tracker.handle(.mouseUp(point: ScreenPoint(x: 50, y: 0), modifiers: []))

        tracker._testApplyFrameSample(frame(movedBy: 50), pointer: ScreenPoint(x: 50, y: 0), token: oldToken)
        #expect(box.events.isEmpty)
    }

    /// #26: the sampler (an AX read) must run on a background thread, never
    /// inside `handle(_:)`, and evidence delivered from there must start the drag.
    @Test("Frame-Sampler laeuft abseits des Hauptthreads und loest das began aus")
    func samplerRunsOffMainThread() async throws {
        let window = makeWindow()
        let probe = ThreadProbe()
        let (tracker, box) = makeTracker(window: window, frameSampler: { w, _ in
            probe.record(isMainThread: Thread.isMainThread)
            return WindowFrame(x: w.frame.x + 50, y: w.frame.y, width: w.frame.width, height: w.frame.height)
        })

        tracker.handle(.mouseDown(point: ScreenPoint(x: 0, y: 0), accessibilityPoint: ScreenPoint(x: 0, y: 0)))
        tracker.handle(.mouseDragged(point: ScreenPoint(x: 50, y: 0), modifiers: []))
        // handle(_:) returned; the lookup and the sample run detached.
        for _ in 0..<300 where box.events.isEmpty {
            try await Task.sleep(for: .milliseconds(10))
        }

        #expect(box.kinds.first == "began")
        #expect(!probe.calls.isEmpty)
        #expect(probe.calls.allSatisfy { $0 == false }, "AX-Zugriff darf nie auf dem Hauptthread laufen.")
    }
}

/// Merkt sich fuer jeden Sampler-Aufruf, ob er auf dem Hauptthread lief.
/// `@unchecked Sendable`, weil der Zugriff ueber ein Schloss laeuft und der
/// Sampler bewusst von einem Hintergrund-Thread aus schreibt.
final class ThreadProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []
    func record(isMainThread: Bool) { lock.lock(); values.append(isMainThread); lock.unlock() }
    var calls: [Bool] { lock.lock(); defer { lock.unlock() }; return values }
}

// MARK: - Testsaat auf dem Tracker

extension EventTapDragTracker {
    /// Reicht ein Lookup‑Ergebnis in die Zustandsmaschine, ohne die
    /// `Task`-Zustellung abzuwarten. Der Zähler ``lookupToken`` wird dabei
    /// mitverwendet — genau wie im echten Weg.
    func applyLookupResultForTest(_ window: DraggedWindow?, useCurrentToken: Bool = true) {
        let token = useCurrentToken ? _testCurrentLookupToken : (_testCurrentLookupToken &- 1)
        _testApplyLookupResult(window, token: token)
    }

    /// Feeds a frame sample as the detached task would, with the current token.
    func applyFrameSampleForTest(_ frame: WindowFrame?, pointer: ScreenPoint) {
        _testApplyFrameSample(frame, pointer: pointer, token: _testCurrentSampleToken)
    }
}
