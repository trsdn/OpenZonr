import Foundation
import Testing

@testable import OpenZonrCore

/// What the overlay shows, decided without a screen.
struct DropzoneOverlayPlanTests {

    private func plan(
        pointer: ScreenPoint,
        origin: ScreenPoint = ScreenPoint(x: 0, y: 0),
        settings: DropzoneSettings = DropzoneSettings(),
        modifiers: ModifierState = [],
        profile: ProfileID? = "default"
    ) throws -> DropzoneOverlayPlan.Plan {
        let configuration = TestConfigurations.minimal()
        let resolved = profile == nil ? nil : configuration.profiles.first?.id
        return DropzoneOverlayPlan.plan(
            pointer: pointer,
            origin: origin,
            configuration: configuration,
            profile: resolved,
            visibleFrames: ["main": TestConfigurations.mainVisibleFrame],
            settings: settings,
            modifiers: modifiers
        )
    }

    @Test("Während eines Zugs werden die Zonen des Displays gezeigt")
    func zonesOfTheDisplayAreShownDuringADrag() throws {
        let result = try plan(pointer: ScreenPoint(x: 400, y: 500))
        #expect(result.isVisible)
        #expect(result.zones.count == 2)
        #expect(result.highlighted?.zone == "left")
    }

    @Test("Die Hervorhebung folgt dem Zeiger")
    func theHighlightFollowsThePointer() throws {
        #expect(try plan(pointer: ScreenPoint(x: 400, y: 500)).highlighted?.zone == "left")
        #expect(try plan(pointer: ScreenPoint(x: 1500, y: 500)).highlighted?.zone == "right")
    }

    @Test("Ohne Profil bleibt das Overlay weg")
    func noProfileMeansNoOverlay() throws {
        let result = try plan(pointer: ScreenPoint(x: 400, y: 500), profile: nil)
        #expect(result.isVisible == false)
        #expect(result.zones.isEmpty)
    }

    @Test("Der Modifikator lässt das Overlay verschwinden")
    func theModifierHidesTheOverlay() throws {
        let result = try plan(pointer: ScreenPoint(x: 400, y: 500), modifiers: [.option])
        #expect(result.isVisible == false)
        if case let .hidden(activation) = result {
            #expect(activation == .suppressed(.option))
        } else {
            Issue.record("erwartet: hidden")
        }
    }

    @Test("Vor der Mindeststrecke bleibt das Overlay weg")
    func theOverlayStaysAwayBeforeTheThreshold() throws {
        let result = try plan(pointer: ScreenPoint(x: 3, y: 0), origin: ScreenPoint(x: 0, y: 0))
        #expect(result.isVisible == false)
    }

    @Test("Über keinem Display gibt es nichts zu zeigen")
    func nothingIsShownOffScreen() throws {
        // Displays do not have to tile a rectangle. A pointer between two
        // monitors is over no display at all, and drawing the previous display's
        // zones there would offer a drop that cannot happen.
        let result = try plan(pointer: ScreenPoint(x: 90_000, y: 90_000))
        #expect(result.isVisible == false)
    }

    @Test("Über der Menüleiste wird nichts angeboten")
    func nothingIsOfferedOverTheMenuBar() throws {
        // The visible frame starts at y = 70 — below it are the menu bar and the
        // Dock, which no zone covers and into which nothing can be dropped.
        // Showing zones there would promise a drop that cannot happen.
        let result = try plan(pointer: ScreenPoint(x: 400, y: 10))
        #expect(result.isVisible == false)
    }
}
