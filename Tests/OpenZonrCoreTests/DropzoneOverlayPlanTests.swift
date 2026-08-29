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

    @Test("Während eines Zugs mit ⌘ werden die Zonen des Displays gezeigt")
    func zonesOfTheDisplayAreShownDuringADrag() throws {
        // Vorgabe seit Issue #23: ⌘ schaltet die Zonen ein.
        let result = try plan(pointer: ScreenPoint(x: 400, y: 500), modifiers: [.command])
        #expect(result.isVisible)
        #expect(result.zones.count == 2)
        #expect(result.highlighted?.zone == "left")
    }

    @Test("Die Hervorhebung folgt dem Zeiger")
    func theHighlightFollowsThePointer() throws {
        #expect(try plan(pointer: ScreenPoint(x: 400, y: 500), modifiers: [.command]).highlighted?.zone == "left")
        #expect(try plan(pointer: ScreenPoint(x: 1500, y: 500), modifiers: [.command]).highlighted?.zone == "right")
    }

    @Test("Ohne Profil bleibt das Overlay weg")
    func noProfileMeansNoOverlay() throws {
        let result = try plan(pointer: ScreenPoint(x: 400, y: 500), modifiers: [.command], profile: nil)
        #expect(result.isVisible == false)
        #expect(result.zones.isEmpty)
    }

    @Test("Ohne den Einschalter bleibt das Overlay weg — und sagt warum")
    func theModifierGatesTheOverlay() throws {
        // The new default polarity: no key, no zones. Told apart from
        // `.suppressed` so the log and the menu can explain *press ⌘* rather
        // than *release ⌥*.
        let result = try plan(pointer: ScreenPoint(x: 400, y: 500))
        #expect(result.isVisible == false)
        if case let .hidden(activation) = result {
            #expect(activation == .awaitingModifier(.command))
        } else {
            Issue.record("erwartet: hidden(awaitingModifier)")
        }
    }

    @Test("Die alte Form „shows unless“ folgt weiter der Unterdrückung")
    func showsUnlessStillSuppresses() throws {
        // Users who prefer the old polarity have set it explicitly; the plan
        // must keep answering their case, or the migration would be a
        // paper-only promise.
        var settings = DropzoneSettings()
        settings.activation = .showsUnless(.option)
        let result = try plan(pointer: ScreenPoint(x: 400, y: 500), settings: settings, modifiers: [.option])
        #expect(result.isVisible == false)
        if case let .hidden(activation) = result {
            #expect(activation == .suppressed(.option))
        } else {
            Issue.record("erwartet: hidden(suppressed)")
        }
    }

    @Test("Vor der Mindeststrecke bleibt das Overlay weg")
    func theOverlayStaysAwayBeforeTheThreshold() throws {
        let result = try plan(
            pointer: ScreenPoint(x: 3, y: 0),
            origin: ScreenPoint(x: 0, y: 0),
            modifiers: [.command]
        )
        #expect(result.isVisible == false)
    }

    @Test("Über keinem Display gibt es nichts zu zeigen")
    func nothingIsShownOffScreen() throws {
        // Displays do not have to tile a rectangle. A pointer between two
        // monitors is over no display at all, and drawing the previous display's
        // zones there would offer a drop that cannot happen.
        let result = try plan(pointer: ScreenPoint(x: 90_000, y: 90_000), modifiers: [.command])
        #expect(result.isVisible == false)
    }

    @Test("Über der Menüleiste wird nichts angeboten")
    func nothingIsOfferedOverTheMenuBar() throws {
        // The visible frame starts at y = 70 — below it are the menu bar and the
        // Dock, which no zone covers and into which nothing can be dropped.
        // Showing zones there would promise a drop that cannot happen.
        let result = try plan(pointer: ScreenPoint(x: 400, y: 10), modifiers: [.command])
        #expect(result.isVisible == false)
    }
}
