import Foundation
import Testing

@testable import OpenZonrCore

/// Turning a drop into a rule — and refusing to, when it would be a guess.
struct DropRuleOfferTests {

    /// The panel-driven `request` path was tested first, and now runs against
    /// the *ask afterwards* switch that Issue #23 turned off by default. Every
    /// test in this suite that uses `.request` opts back in explicitly, so a
    /// failure here means the panel path — not the badge path — is broken.
    private func offeringSettings() -> DropzoneSettings {
        var settings = DropzoneSettings()
        settings.offerRule = true
        return settings
    }

    private func zone(display: DisplayAlias = "main", zone: ZoneID = "right") -> Dropzone {
        // The name follows the ID: a helper that calls every zone "Rechts"
        // makes a test about zone names pass for the wrong reason.
        let names: [ZoneID: String] = ["left": "Links", "right": "Rechts"]
        return Dropzone(
            display: display,
            zone: zone,
            name: names[zone] ?? String(describing: zone),
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
            profile: "solo",
            settings: offeringSettings(),
            configuration: TestConfigurations.minimal()
        ).get()

        #expect(request.bundleIdentifier == "com.apple.TextEdit")
        #expect(request.profile == "solo")
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
            profile: "solo",
            settings: offeringSettings(),
            configuration: TestConfigurations.minimal()
        )
        #expect(result.isFailure)
    }

    @Test("Eine leere Bundle-Kennung zählt wie keine")
    func emptyBundleIdentifierCountsAsMissing() {
        let result = DropRuleOffer.request(
            for: DroppedWindow(bundleIdentifier: "", applicationName: "Leer"),
            droppedInto: zone(),
            profile: "solo",
            settings: offeringSettings(),
            configuration: TestConfigurations.minimal()
        )
        #expect(result.isFailure)
    }

    @Test("Abgeschaltetes Angebot fragt nicht")
    func switchedOffOfferStaysQuiet() {
        var settings = offeringSettings()
        settings.offerRule = false
        let result = DropRuleOffer.request(
            for: DroppedWindow(bundleIdentifier: "com.apple.TextEdit", applicationName: "TextEdit"),
            droppedInto: zone(),
            profile: "solo",
            settings: settings,
            configuration: TestConfigurations.minimal()
        )
        #expect(result.isFailure)
    }

    @Test("Die Vorgabe seit Issue #23: das Angebot ist aus, request scheitert")
    func newDefaultSuppressesTheRequestPath() {
        // A regression check on the default: if the panel default ever slid
        // back to `true`, the badge would still work but the *ask afterwards*
        // interruption would return, unmentioned. That is the exact shape of
        // silent behaviour change this project rejects.
        let result = DropRuleOffer.request(
            for: DroppedWindow(bundleIdentifier: "com.apple.TextEdit", applicationName: "TextEdit"),
            droppedInto: zone(),
            profile: "solo",
            settings: DropzoneSettings(),
            configuration: TestConfigurations.minimal()
        )
        if case let .failure(refusal) = result {
            #expect(refusal == .offerSwitchedOff)
        } else {
            Issue.record("erwartet: offerSwitchedOff, bekommen: \(result)")
        }
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
            settings: offeringSettings(),
            configuration: base
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
            settings: offeringSettings(),
            configuration: base
        ).get()

        let once = try QuickPin.pin(request, into: base)
        let twice = try QuickPin.pin(request, into: once.configuration)
        #expect(twice.configuration.rules.count == once.configuration.rules.count)
    }

    @Test("Wo die Regel schon hinzeigt, wird nicht gefragt")
    func noOfferWhenTheRuleAlreadyPointsThere() throws {
        // The review found this: the question was posed regardless, a yes ran
        // into QuickPin's retarget branch, the unchanged configuration was
        // saved and Log.success reported a change that never happened. An
        // offer is only worth making when a yes would change something.
        let base = TestConfigurations.minimal()
        let profile = try #require(base.profiles.first)
        let request = try DropRuleOffer.request(
            for: DroppedWindow(bundleIdentifier: "com.apple.TextEdit", applicationName: "TextEdit"),
            droppedInto: zone(display: "main", zone: "left"),
            profile: profile.id,
            settings: offeringSettings(),
            configuration: base
        ).get()

        let pinned = try QuickPin.pin(request, into: base).configuration

        // Same app, same zone, but now the rule is already there.
        let second = DropRuleOffer.request(
            for: DroppedWindow(bundleIdentifier: "com.apple.TextEdit", applicationName: "TextEdit"),
            droppedInto: zone(display: "main", zone: "left"),
            profile: profile.id,
            settings: offeringSettings(),
            configuration: pinned
        )
        #expect(second.isFailure)
        if case let .failure(refusal) = second {
            #expect(refusal == .alreadyPinned(applicationName: "TextEdit", zoneName: "Links"))
        }
    }

    @Test("Dieselbe App in eine andere Zone wird sehr wohl gefragt")
    func droppingIntoADifferentZoneStillAsks() throws {
        // The counterpart to the test above: refusing whenever a rule exists
        // would break the one gesture the feature is for — moving an app
        // somewhere else and saying "from now on, here".
        let base = TestConfigurations.minimal()
        let profile = try #require(base.profiles.first)
        let toLeft = try DropRuleOffer.request(
            for: DroppedWindow(bundleIdentifier: "com.apple.TextEdit", applicationName: "TextEdit"),
            droppedInto: zone(display: "main", zone: "left"),
            profile: profile.id,
            settings: offeringSettings(),
            configuration: base
        ).get()
        let pinned = try QuickPin.pin(toLeft, into: base).configuration

        let toRight = DropRuleOffer.request(
            for: DroppedWindow(bundleIdentifier: "com.apple.TextEdit", applicationName: "TextEdit"),
            droppedInto: zone(display: "main", zone: "right"),
            profile: profile.id,
            settings: offeringSettings(),
            configuration: pinned
        )
        #expect(toRight.isFailure == false)
    }

    @Test("Eine Zone, die es in der Konfiguration nicht gibt, wird nicht angeboten")
    func noOfferForAZoneThatIsNotInTheConfiguration() throws {
        // Asking a question whose yes would throw is worse than staying quiet:
        // the user answers, nothing happens, and nobody says why.
        let base = TestConfigurations.minimal()
        let profile = try #require(base.profiles.first)
        let result = DropRuleOffer.request(
            for: DroppedWindow(bundleIdentifier: "com.apple.TextEdit", applicationName: "TextEdit"),
            droppedInto: zone(display: "main", zone: "erfunden"),
            profile: profile.id,
            settings: offeringSettings(),
            configuration: base
        )
        #expect(result.isFailure)
    }
}

/// The badge path: the user says *and pin* with the mouse, not with a panel.
///
/// A separate suite because the badge and the panel are two entrances to one
/// rule, and mixing their tests would hide the case that matters most: a
/// release on the badge must write a rule *regardless* of the panel setting
/// that is now off by default.
struct DropRuleOfferPinTests {

    private func zone(display: DisplayAlias = "main", zone: ZoneID = "right") -> Dropzone {
        let names: [ZoneID: String] = ["left": "Links", "right": "Rechts"]
        return Dropzone(
            display: display,
            zone: zone,
            name: names[zone] ?? String(describing: zone),
            relativeFrame: RelativeRect(x: 0.5, y: 0, width: 0.5, height: 1),
            frame: WindowFrame(x: 960, y: 0, width: 960, height: 1080),
            visibleFrame: VisibleFrame(x: 0, y: 0, width: 1920, height: 1080)
        )
    }

    @Test("Die Marke schreibt die Regel, auch wenn das Angebotspanel aus ist")
    func pinPathIgnoresThePanelSwitch() throws {
        // The defining property of the badge, and the reason `pin` exists next
        // to `request`. Gate the badge on `offerRule` and a release on the
        // badge would silently do nothing for every default install, which is
        // the exact silent failure the *ask afterwards* switch is meant to
        // eliminate — not perpetuate.
        let base = TestConfigurations.minimal()
        let profile = try #require(base.profiles.first)
        let request = try DropRuleOffer.pin(
            for: DroppedWindow(bundleIdentifier: "com.apple.TextEdit", applicationName: "TextEdit"),
            droppedInto: zone(display: "main", zone: "left"),
            profile: profile.id,
            configuration: base
        ).get()
        #expect(request.target.zone == "left")

        let outcome = try QuickPin.pin(request, into: base)
        #expect(outcome.configuration.rules.count == base.rules.count + 1)
    }

    @Test("Die Marke fragt QuickPin, ob überhaupt etwas zu ändern wäre")
    func pinRefusesWhenTheRuleAlreadyPointsThere() throws {
        // Same *already pointed there* discipline as the panel path. A badge
        // that silently rewrote an identical rule would be Log.success without
        // effect — the same class of silent success the panel path guards
        // against, in a new place.
        let base = TestConfigurations.minimal()
        let profile = try #require(base.profiles.first)
        let first = try DropRuleOffer.pin(
            for: DroppedWindow(bundleIdentifier: "com.apple.TextEdit", applicationName: "TextEdit"),
            droppedInto: zone(display: "main", zone: "left"),
            profile: profile.id,
            configuration: base
        ).get()
        let pinned = try QuickPin.pin(first, into: base).configuration

        let again = DropRuleOffer.pin(
            for: DroppedWindow(bundleIdentifier: "com.apple.TextEdit", applicationName: "TextEdit"),
            droppedInto: zone(display: "main", zone: "left"),
            profile: profile.id,
            configuration: pinned
        )
        #expect(again.isFailure)
        if case let .failure(refusal) = again {
            #expect(refusal == .alreadyPinned(applicationName: "TextEdit", zoneName: "Links"))
        }
    }

    @Test("Auch die Marke braucht eine Bundle-Kennung")
    func pinRefusesWithoutABundleIdentifier() throws {
        // If the badge could invent a key, two entrances to the same rule
        // would soon produce two different keys — and rules matching by name
        // would drift as soon as an app was renamed or a display was renamed.
        // The refusal is the same on both paths, for the same reason.
        let base = TestConfigurations.minimal()
        let profile = try #require(base.profiles.first)
        let result = DropRuleOffer.pin(
            for: DroppedWindow(bundleIdentifier: nil, applicationName: "Namenlos"),
            droppedInto: zone(),
            profile: profile.id,
            configuration: base
        )
        #expect(result.isFailure)
    }
}

extension Result {
    fileprivate var isFailure: Bool {
        if case .failure = self { return true }
        return false
    }
}
