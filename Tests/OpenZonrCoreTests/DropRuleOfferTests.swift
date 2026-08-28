import Foundation
import Testing

@testable import OpenZonrCore

/// Turning a drop into a rule — and refusing to, when it would be a guess.
struct DropRuleOfferTests {

    private func zone(display: DisplayAlias = "main", zone: ZoneID = "right") -> Dropzone {
        Dropzone(
            display: display,
            zone: zone,
            name: "Rechts",
            relativeFrame: RelativeRect(x: 0.5, y: 0, width: 0.5, height: 1),
            frame: WindowFrame(x: 960, y: 0, width: 960, height: 1080),
            visibleFrame: VisibleFrame(x: 0, y: 0, width: 1920, height: 1080)
        )
    }

    @Test("Ein Ablegen ergibt eine Anfrage auf genau diese Zone")
    func dropProducesARequestForThatZone() throws {
        let request = try DropRuleOffer.request(
            for: DroppedWindow(bundleIdentifier: "com.apple.TextEdit", applicationName: "TextEdit"),
            droppedInto: zone(),
            profile: "office",
            settings: DropzoneSettings()
        ).get()

        #expect(request.bundleIdentifier == "com.apple.TextEdit")
        #expect(request.profile == "office")
        #expect(request.target.display == "main")
        #expect(request.target.zone == "right")
    }

    @Test("Ohne Bundle-Kennung wird nichts angeboten")
    func noOfferWithoutABundleIdentifier() {
        // A rule keyed on a display name would match the wrong thing tomorrow.
        // Refusing is the honest answer; inventing a key is not.
        let result = DropRuleOffer.request(
            for: DroppedWindow(bundleIdentifier: nil, applicationName: "Namenlos"),
            droppedInto: zone(),
            profile: "office",
            settings: DropzoneSettings()
        )
        #expect(result.isFailure)
    }

    @Test("Eine leere Bundle-Kennung zählt wie keine")
    func emptyBundleIdentifierCountsAsMissing() {
        let result = DropRuleOffer.request(
            for: DroppedWindow(bundleIdentifier: "", applicationName: "Leer"),
            droppedInto: zone(),
            profile: "office",
            settings: DropzoneSettings()
        )
        #expect(result.isFailure)
    }

    @Test("Abgeschaltetes Angebot fragt nicht")
    func switchedOffOfferStaysQuiet() {
        var settings = DropzoneSettings()
        settings.offerRule = false
        let result = DropRuleOffer.request(
            for: DroppedWindow(bundleIdentifier: "com.apple.TextEdit", applicationName: "TextEdit"),
            droppedInto: zone(),
            profile: "office",
            settings: settings
        )
        #expect(result.isFailure)
    }

    @Test("Die Frage nennt die Zone beim Namen")
    func theQuestionNamesTheZone() {
        // "Diese App immer hier öffnen?" leaves the user guessing which zone
        // "hier" resolved to when zones overlap — and a rule written from a
        // misunderstanding is worse than no rule.
        let question = DropRuleOffer.question(
            for: DroppedWindow(bundleIdentifier: "com.apple.TextEdit", applicationName: "TextEdit"),
            zone: zone()
        )
        #expect(question.contains("TextEdit"))
        #expect(question.contains("Rechts"))
        #expect(question.contains("main"))
    }

    @Test("Die Anfrage aus dem Ablegen schreibt eine Regel, die auch gewinnt")
    func theRequestActuallyWinsThroughQuickPin() throws {
        // The whole point of routing through QuickPin: it picks a priority that
        // beats the existing rules instead of adding one that silently loses.
        let base = TestConfigurations.minimal()
        let profile = try #require(base.profiles.first)
        let request = try DropRuleOffer.request(
            for: DroppedWindow(bundleIdentifier: "com.apple.TextEdit", applicationName: "TextEdit"),
            droppedInto: zone(display: "main", zone: "left"),
            profile: profile.id,
            settings: DropzoneSettings()
        ).get()

        let outcome = try QuickPin.pin(request, into: base)
        #expect(outcome.configuration.rules.count == base.rules.count + 1)
        #expect(outcome.summary.isEmpty == false)
    }

    @Test("Zweimal dasselbe Ablegen verdoppelt die Regel nicht")
    func droppingTwiceDoesNotDuplicateTheRule() throws {
        let base = TestConfigurations.minimal()
        let profile = try #require(base.profiles.first)
        let request = try DropRuleOffer.request(
            for: DroppedWindow(bundleIdentifier: "com.apple.TextEdit", applicationName: "TextEdit"),
            droppedInto: zone(display: "main", zone: "left"),
            profile: profile.id,
            settings: DropzoneSettings()
        ).get()

        let once = try QuickPin.pin(request, into: base)
        let twice = try QuickPin.pin(request, into: once.configuration)
        #expect(twice.configuration.rules.count == once.configuration.rules.count)
    }
}

extension Result {
    fileprivate var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}
