import Foundation
import Testing

@testable import OpenZonrCore

/// Suppression, threshold and the settings that drive them.
struct DropzoneActivationTests {

    @Test("Zonen erscheinen, sobald weit genug gezogen wurde")
    func zonesAppearAfterTheThreshold() {
        let settings = DropzoneSettings()
        #expect(DropzoneActivator.activation(settings: settings, modifiers: [], travelled: 100) == .show)
    }

    @Test("Unterhalb der Mindeststrecke passiert nichts")
    func nothingHappensBelowTheThreshold() {
        // Without this, a plain click on a title bar would flash the overlay.
        let settings = DropzoneSettings()
        let activation = DropzoneActivator.activation(settings: settings, modifiers: [], travelled: 3)
        #expect(activation.showsZones == false)
        if case let .belowThreshold(travelled, required) = activation {
            #expect(travelled == 3)
            #expect(required == settings.minimumDragDistance)
        } else {
            Issue.record("erwartet: belowThreshold, bekommen: \(activation)")
        }
    }

    @Test("Die Modifikatortaste unterdrückt die Zonen")
    func modifierSuppressesTheZones() {
        let settings = DropzoneSettings()
        #expect(settings.suppressionModifier == .option)
        let activation = DropzoneActivator.activation(settings: settings, modifiers: [.option], travelled: 500)
        #expect(activation == .suppressed(.option))
        #expect(activation.showsZones == false)
    }

    @Test("Ein anderer Modifikator unterdrückt nicht")
    func anotherModifierDoesNotSuppress() {
        // ⌘-dragging moves a background window without activating it — an
        // established macOS gesture. Claiming it for suppression would break
        // something the user already relies on, so only the configured key counts.
        let settings = DropzoneSettings()
        #expect(DropzoneActivator.activation(settings: settings, modifiers: [.command], travelled: 500) == .show)
    }

    @Test("Modifikator „keiner“ schaltet die Unterdrückung ab")
    func noModifierMeansNoSuppression() {
        var settings = DropzoneSettings()
        settings.suppressionModifier = .none
        let all: ModifierState = [.shift, .control, .option, .command]
        #expect(DropzoneActivator.activation(settings: settings, modifiers: all, travelled: 500) == .show)
    }

    @Test("Abgeschaltet schlägt alles andere")
    func disabledBeatsEverything() {
        var settings = DropzoneSettings()
        settings.enabled = false
        #expect(DropzoneActivator.activation(settings: settings, modifiers: [], travelled: 999) == .disabled)
    }

    @Test("Die Strecke wird euklidisch gemessen")
    func distanceIsEuclidean() {
        let distance = DropzoneActivator.distance(
            from: ScreenPoint(x: 0, y: 0),
            to: ScreenPoint(x: 3, y: 4)
        )
        #expect(distance == 5)
    }

    @Test("Jede Nichtanzeige nennt einen Grund")
    func everyRefusalExplainsItself() {
        let cases: [DropzoneActivation] = [
            .disabled,
            .suppressed(.option),
            .belowThreshold(travelled: 2, required: 12),
        ]
        for activation in cases {
            #expect(activation.explanation.isEmpty == false)
        }
    }
}

/// Reading the settings, above all out of files written before they existed.
struct DropzoneSettingsDecodingTests {

    @Test("Eine Konfiguration ohne dropzones-Block lädt weiter")
    func configurationWithoutDropzonesStillLoads() throws {
        // The trap this guards: adding a non-optional field to GlobalDefaults
        // makes every existing config.json fail to decode — not the new key, the
        // whole file. The user would see "keine Konfiguration" and blame the
        // update, correctly.
        let json = """
        {"version": 1, "defaults": {"placementTiming": {"waitForFirstWindow": 3}}}
        """
        let defaults = try JSONDecoder().decode(GlobalDefaults.self, from: Data(json.utf8))
        #expect(defaults.dropzones == DropzoneSettings())
    }

    @Test("Ein halber dropzones-Block ergänzt die Vorgaben")
    func partialDropzonesBlockFallsBackToDefaults() throws {
        let json = """
        {"enabled": false, "suppressionModifier": "shift"}
        """
        let settings = try JSONDecoder().decode(DropzoneSettings.self, from: Data(json.utf8))
        #expect(settings.enabled == false)
        #expect(settings.suppressionModifier == .shift)
        #expect(settings.minimumDragDistance == DropzoneSettings().minimumDragDistance)
        #expect(settings.offerRule == DropzoneSettings().offerRule)
    }

    @Test("Die Einstellungen überleben eine Runde durch JSON")
    func settingsSurviveARoundTrip() throws {
        var settings = DropzoneSettings()
        settings.suppressionModifier = .control
        settings.minimumDragDistance = 20
        settings.offerRule = false
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(DropzoneSettings.self, from: data) == settings)
    }

    @Test("Das mitgelieferte Beispiel lädt mit Dropzone-Vorgaben")
    func shippedExampleLoadsWithDefaults() throws {
        let configuration = try TestConfigurations.example()
        #expect(configuration.defaults.dropzones.enabled)
    }

    @Test("Jeder Modifikator hat einen deutschen Namen")
    func everyModifierIsNamed() {
        for modifier in DropzoneModifier.allCases {
            #expect(modifier.label.isEmpty == false)
        }
    }

    @Test("Der Modifikatorzustand erkennt genau die gedrückte Taste")
    func modifierStateMatchesOnlyItself() {
        let state: ModifierState = [.option]
        #expect(state.holds(.option))
        #expect(state.holds(.command) == false)
        // "none" is not a key; nothing can hold it down.
        #expect(state.holds(.none) == false)
    }

    @Test("Die Pause hält auch das Ziehen an")
    func pauseStopsTheDragHalfToo() {
        // The review found the two halves disagreeing: the tracker kept
        // listening during a pause while the menu and the log said nothing
        // would be placed any more. Whichever way it is answered, it has to be
        // answered once — and this is that one place.
        var settings = DropzoneSettings()
        settings.enabled = true
        #expect(DropzoneActivator.suspension(settings: settings, isPaused: true) == .paused)
        #expect(DropzoneActivator.suspension(settings: settings, isPaused: false) == nil)
    }

    @Test("Abgeschaltet bleibt abgeschaltet, auch ohne Pause")
    func switchedOffBeatsEverything() {
        var settings = DropzoneSettings()
        settings.enabled = false
        #expect(DropzoneActivator.suspension(settings: settings, isPaused: false) == .switchedOff)
        // Both at once still names the setting, because that is what the user
        // has to change to get the feature back after resuming.
        #expect(DropzoneActivator.suspension(settings: settings, isPaused: true) == .switchedOff)
    }

    @Test("Jeder Grund zu schweigen sagt, warum")
    func everySuspensionExplainsItself() {
        for suspension in [DropzoneSuspension.switchedOff, .paused] {
            #expect(suspension.explanation.isEmpty == false)
        }
    }
}
