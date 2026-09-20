import ApplicationServices
import Foundation
import Testing

@testable import OpenZonrCore
@testable import OpenZonrMac

/// Drücke, die **nie** zu einem `.began` werden, waren bisher vollkommen
/// stumm — und sie sind genau die Lage, die der offene Fehler beschreibt:
/// „die Dropzones kommen nicht". Der neue Kanal ``EventTapDragTracker/onOutcome``
/// macht sie aussprechbar.
///
/// Zwei Zusicherungen stehen hier zusätzlich zur Wortwahl:
/// höchstens **ein** Ergebnis je Druck, und **kein** Ergebnis für einen
/// gewöhnlichen Klick — sonst stünde nach jedem Fensterwechsel ein Satz im Menü.
@Suite("EventTapDragTracker — Ergebnis eines Drucks")
@MainActor
struct EventTapDragOutcomeTests {

    private func makeWindow() -> DraggedWindow {
        DraggedWindow(
            element: AXUIElementCreateSystemWide(),
            processIdentifier: 42,
            bundleIdentifier: "com.example.test",
            applicationName: "Test",
            frame: WindowFrame(x: 0, y: 0, width: 100, height: 100)
        )
    }

    @MainActor
    final class OutcomeBox {
        private(set) var outcomes: [DragOutcome] = []
        func append(_ outcome: DragOutcome) { outcomes.append(outcome) }
    }

    private func makeTracker(
        window: DraggedWindow?,
        now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now }
    ) -> (tracker: EventTapDragTracker, outcomes: OutcomeBox, events: [String]) {
        let box = OutcomeBox()
        let captured = window
        let tracker = EventTapDragTracker(
            primaryTopY: 0,
            windowLookup: { _, _ in captured },
            frameSampler: { _, _ in nil },
            now: now
        )
        tracker.minimumDragDistance = 5
        tracker.onOutcome = { box.append($0) }
        return (tracker, box, [])
    }

    private func press(_ tracker: EventTapDragTracker) {
        tracker.handle(.mouseDown(point: ScreenPoint(x: 0, y: 0), accessibilityPoint: ScreenPoint(x: 0, y: 0)))
    }

    @Test("Ein Klick ohne Weg meldet nichts — sonst stünde nach jedem Fensterwechsel ein Satz im Menü")
    func plainClickIsSilent() {
        let (tracker, box, _) = makeTracker(window: makeWindow())
        press(tracker)
        tracker.handle(.mouseUp(point: ScreenPoint(x: 1, y: 0), modifiers: []))
        #expect(box.outcomes.isEmpty)
    }

    @Test("Kein Fenster unter dem Druckpunkt wird gemeldet")
    func noWindowFound() {
        let (tracker, box, _) = makeTracker(window: nil)
        press(tracker)
        tracker.applyLookupResultForTest(nil)
        tracker.handle(.mouseDragged(point: ScreenPoint(x: 50, y: 0), modifiers: []))
        #expect(box.outcomes == [.noWindowFound])
    }

    @Test("Fenster gefunden, aber losgelassen, bevor ein Beleg da war")
    func releasedBeforeEvidence() {
        let window = makeWindow()
        let (tracker, box, _) = makeTracker(window: window)
        press(tracker)
        tracker.applyLookupResultForTest(window)
        tracker.handle(.mouseDragged(point: ScreenPoint(x: 50, y: 0), modifiers: []))
        // Kein Rahmen lesbar: der Beleg bleibt aus.
        tracker.applyFrameSampleForTest(nil, pointer: ScreenPoint(x: 50, y: 0))
        tracker.handle(.mouseUp(point: ScreenPoint(x: 50, y: 0), modifiers: []))
        #expect(box.outcomes == [.releasedBeforeEvidence])
    }

    @Test("Aufgebrauchtes Zeitbudget wird gemeldet, und danach kein zweites Mal")
    func budgetExhausted() {
        let window = makeWindow()
        let clock = ClockStub()
        let (tracker, box, _) = makeTracker(window: window, now: { clock.read() })
        press(tracker)
        tracker.applyLookupResultForTest(window)
        tracker.handle(.mouseDragged(point: ScreenPoint(x: 50, y: 0), modifiers: []))
        tracker.applyFrameSampleForTest(nil, pointer: ScreenPoint(x: 50, y: 0))

        clock.advance(.seconds(5))
        tracker.handle(.mouseDragged(point: ScreenPoint(x: 60, y: 0), modifiers: []))
        #expect(box.outcomes == [.noMovementEvidence(.budgetExhausted)])

        // Das Loslassen fügt keinen zweiten Satz hinzu.
        tracker.handle(.mouseUp(point: ScreenPoint(x: 60, y: 0), modifiers: []))
        #expect(box.outcomes.count == 1)
    }

    @Test("Ein Kantenzug ist keine Bewegung und sagt das auch")
    func resizedInstead() {
        let window = makeWindow()
        let (tracker, box, _) = makeTracker(window: window)
        press(tracker)
        tracker.applyLookupResultForTest(window)
        tracker.handle(.mouseDragged(point: ScreenPoint(x: 50, y: 0), modifiers: []))
        // Ursprung bleibt, Breite wächst: eine Grössenänderung.
        tracker.applyFrameSampleForTest(
            WindowFrame(x: 0, y: 0, width: 150, height: 100), pointer: ScreenPoint(x: 50, y: 0)
        )
        #expect(box.outcomes == [.noMovementEvidence(.resizedInstead)])
    }

    @Test("Ein echter Zug meldet kein Druck-Ergebnis — darüber erzählt onEvent")
    func realDragReportsNothing() {
        let window = makeWindow()
        let (tracker, box, _) = makeTracker(window: window)
        var kinds: [String] = []
        tracker.onEvent = { event in
            switch event {
            case .began: kinds.append("began")
            case .moved: kinds.append("moved")
            case .ended: kinds.append("ended")
            case .cancelled: kinds.append("cancelled")
            }
        }
        press(tracker)
        tracker.applyLookupResultForTest(window)
        tracker.handle(.mouseDragged(point: ScreenPoint(x: 50, y: 0), modifiers: []))
        tracker.applyFrameSampleForTest(
            WindowFrame(x: 50, y: 0, width: 100, height: 100), pointer: ScreenPoint(x: 50, y: 0)
        )
        tracker.handle(.mouseUp(point: ScreenPoint(x: 50, y: 0), modifiers: []))

        #expect(kinds.first == "began")
        #expect(kinds.last == "ended")
        #expect(box.outcomes.isEmpty)
    }

    @Test("Ein neuer Druck darf wieder melden")
    func secondPressReportsAgain() {
        let (tracker, box, _) = makeTracker(window: nil)
        press(tracker)
        tracker.applyLookupResultForTest(nil)
        tracker.handle(.mouseDragged(point: ScreenPoint(x: 50, y: 0), modifiers: []))
        tracker.handle(.mouseUp(point: ScreenPoint(x: 50, y: 0), modifiers: []))

        press(tracker)
        tracker.applyLookupResultForTest(nil)
        tracker.handle(.mouseDragged(point: ScreenPoint(x: 50, y: 0), modifiers: []))
        #expect(box.outcomes == [.noWindowFound, .noWindowFound])
    }
}
