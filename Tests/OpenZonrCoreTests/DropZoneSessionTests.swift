import Foundation
import Testing

@testable import OpenZonrCore

/// The behaviour of one drag.
///
/// These rules are what separates a dropzone that feels calm from one that
/// flickers, and none of them needs a window server to be proven.
struct DropZoneSessionTests {

    // MARK: - Fixtures

    private static func candidate(
        _ zone: ZoneID,
        x: Double,
        y: Double,
        width: Double,
        height: Double
    ) -> DropCandidate {
        DropCandidate(
            display: "main",
            layout: "halves",
            zone: zone,
            name: zone.rawValue,
            frame: WindowFrame(x: x, y: y, width: width, height: height)
        )
    }

    private static let left = candidate("left", x: 0, y: 0, width: 960, height: 1000)
    private static let right = candidate("right", x: 960, y: 0, width: 960, height: 1000)
    /// Spans both halves, so it is always the less specific of the two.
    private static let focus = candidate("focus", x: 200, y: 100, width: 1520, height: 800)

    // MARK: - Activation

    @Test("Ein Klick ohne Bewegung platziert nichts")
    func aClickWithoutMovementPlacesNothing() {
        var session = DropZoneSession()
        session.begin(at: ScreenPoint(x: 500, y: 500))
        session.update(at: ScreenPoint(x: 502, y: 501), suppressed: false, candidates: [Self.left])

        #expect(session.isTracking)
        #expect(!session.isActive)
        #expect(session.highlighted == nil)
        #expect(session.end() == nil)
    }

    @Test("Nach genügend Bewegung erscheint die Zone")
    func theZoneAppearsOnceTheDragIsRealB() {
        var session = DropZoneSession()
        session.begin(at: ScreenPoint(x: 500, y: 500))
        session.update(at: ScreenPoint(x: 540, y: 500), suppressed: false, candidates: [Self.left])

        #expect(session.isActive)
        #expect(session.highlighted == Self.left)
        #expect(session.end() == Self.left)
    }

    @Test("Nach dem Ende ist die Sitzung wieder leer")
    func theSessionIsEmptyAgainAfterwards() {
        var session = DropZoneSession()
        session.begin(at: ScreenPoint(x: 500, y: 500))
        session.update(at: ScreenPoint(x: 540, y: 500), suppressed: false, candidates: [Self.left])
        _ = session.end()

        #expect(!session.isTracking)
        #expect(!session.isActive)
        #expect(session.highlighted == nil)
        // A second end() must not hand out the same target twice.
        #expect(session.end() == nil)
    }

    @Test("Abbrechen platziert nichts")
    func cancellingPlacesNothing() {
        var session = DropZoneSession()
        session.begin(at: ScreenPoint(x: 500, y: 500))
        session.update(at: ScreenPoint(x: 540, y: 500), suppressed: false, candidates: [Self.left])
        session.cancel()

        #expect(session.highlighted == nil)
        #expect(session.end() == nil)
    }

    // MARK: - Suppression

    @Test("Die Modifikatortaste unterdrückt das Overlay")
    func theModifierSuppressesTheOverlay() {
        var session = DropZoneSession()
        session.begin(at: ScreenPoint(x: 500, y: 500))
        session.update(at: ScreenPoint(x: 540, y: 500), suppressed: true, candidates: [Self.left])

        #expect(session.isActive)
        #expect(session.highlighted == nil)
        #expect(session.end() == nil)
    }

    @Test("Loslassen der Taste mitten im Ziehen holt das Overlay zurück")
    func releasingTheModifierMidDragBringsTheOverlayBack() {
        var session = DropZoneSession()
        session.begin(at: ScreenPoint(x: 500, y: 500))
        session.update(at: ScreenPoint(x: 540, y: 500), suppressed: true, candidates: [Self.left])
        session.update(at: ScreenPoint(x: 545, y: 500), suppressed: false, candidates: [Self.left])

        #expect(session.highlighted == Self.left)
    }

    // MARK: - Hysteresis

    @Test("Ein Zittern an der Kante wechselt die Zone nicht")
    func atremorAtTheBoundaryDoesNotSwitchZones() {
        var session = DropZoneSession(settings: .init(activationDistance: 12, switchMargin: 16))
        session.begin(at: ScreenPoint(x: 500, y: 500))
        session.update(at: ScreenPoint(x: 600, y: 500), suppressed: false, candidates: [Self.left])
        #expect(session.highlighted == Self.left)

        // Two points past the boundary — inside "right", but not decisively.
        session.update(at: ScreenPoint(x: 962, y: 500), suppressed: false, candidates: [Self.right])
        #expect(session.highlighted == Self.left)
    }

    @Test("Entschlossenes Überqueren wechselt die Zone")
    func committingToTheNewZoneSwitches() {
        var session = DropZoneSession(settings: .init(activationDistance: 12, switchMargin: 16))
        session.begin(at: ScreenPoint(x: 500, y: 500))
        session.update(at: ScreenPoint(x: 600, y: 500), suppressed: false, candidates: [Self.left])
        session.update(at: ScreenPoint(x: 1100, y: 500), suppressed: false, candidates: [Self.right])

        #expect(session.highlighted == Self.right)
    }

    @Test("Verlässt der Zeiger alle Zonen, bleibt nichts hervorgehoben")
    func leavingEveryZoneClearsTheHighlight() {
        var session = DropZoneSession()
        session.begin(at: ScreenPoint(x: 500, y: 500))
        session.update(at: ScreenPoint(x: 600, y: 500), suppressed: false, candidates: [Self.left])
        session.update(at: ScreenPoint(x: 600, y: 5000), suppressed: false, candidates: [])

        #expect(session.highlighted == nil)
        #expect(session.end() == nil)
    }

    // MARK: - Cycling

    @Test("Die spezifischste Zone ist vorgewählt")
    func theMostSpecificZoneIsPreselected() {
        var session = DropZoneSession()
        session.begin(at: ScreenPoint(x: 500, y: 500))
        session.update(at: ScreenPoint(x: 600, y: 500), suppressed: false, candidates: [Self.left, Self.focus])

        #expect(session.highlighted == Self.left)
    }

    @Test("Durchschalten erreicht die großzügigere Zone und läuft rundherum")
    func cyclingReachesTheGenerousZoneAndWrapsAround() {
        var session = DropZoneSession()
        session.begin(at: ScreenPoint(x: 500, y: 500))
        session.update(at: ScreenPoint(x: 600, y: 500), suppressed: false, candidates: [Self.left, Self.focus])

        session.cycle(candidates: [Self.left, Self.focus])
        #expect(session.highlighted == Self.focus)

        session.cycle(candidates: [Self.left, Self.focus])
        #expect(session.highlighted == Self.left)
    }

    @Test("Eine ausdrücklich gewählte Zone überlebt weitere Mausbewegung")
    func anExplicitChoiceSurvivesFurtherMovement() {
        var session = DropZoneSession()
        session.begin(at: ScreenPoint(x: 500, y: 500))
        session.update(at: ScreenPoint(x: 600, y: 500), suppressed: false, candidates: [Self.left, Self.focus])
        session.cycle(candidates: [Self.left, Self.focus])

        // Moving on: without the pin, "left" would win again as the more specific.
        session.update(at: ScreenPoint(x: 620, y: 520), suppressed: false, candidates: [Self.left, Self.focus])
        #expect(session.highlighted == Self.focus)
    }

    @Test("Verlässt der Zeiger die gewählte Zone, greift wieder die Vorauswahl")
    func leavingThePinnedZoneFallsBackToThePreselection() {
        var session = DropZoneSession()
        session.begin(at: ScreenPoint(x: 500, y: 500))
        session.update(at: ScreenPoint(x: 600, y: 500), suppressed: false, candidates: [Self.left, Self.focus])
        session.cycle(candidates: [Self.left, Self.focus])

        session.update(at: ScreenPoint(x: 1400, y: 500), suppressed: false, candidates: [Self.right])
        #expect(session.highlighted == Self.right)
    }

    @Test("Vor der Aktivierung gibt es nichts durchzuschalten")
    func thereIsNothingToCycleBeforeActivation() {
        var session = DropZoneSession()
        session.begin(at: ScreenPoint(x: 500, y: 500))
        session.cycle(candidates: [Self.left, Self.focus])

        #expect(session.highlighted == nil)
    }
}
