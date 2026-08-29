import Foundation
import Testing

@testable import OpenZonrCore

/// Suppression, threshold and the settings that drive them.
struct DropzoneActivationTests {

    @Test("Mit ⌘ gedrückt erscheinen die Zonen — die Vorgabe seit Issue #23")
    func zonesAppearWhileCommandIsHeld() {
        // The measured swap: on window drags ⌘ already means *bewegen, ohne zu
        // aktivieren* (drei Läufe, 29.08.2026). Making ⌘ the switch that shows
        // the zones ties them to exactly the case where the drag does not steal
        // focus. Anyone expecting the old *drag always shows* behaviour has to
        // set `activation: {showsUnless: option}` — the migration below keeps
        // existing files on that older polarity.
        let settings = DropzoneSettings()
        #expect(settings.activation == .showsWhile(.command))
        #expect(DropzoneActivator.activation(settings: settings, modifiers: [.command], travelled: 100) == .show)
    }

    @Test("Ohne ⌘ bleiben die Zonen weg — mit einem Grund, der es sagt")
    func withoutTheModifierTheZonesStayAway() {
        // Told apart from `.suppressed`: the menu and the log have to be able
        // to say *press ⌘ to see the zones* instead of the old *release ⌥*.
        // A first-time user without either sentence has no way to discover the
        // feature at all.
        let activation = DropzoneActivator.activation(
            settings: DropzoneSettings(), modifiers: [], travelled: 500
        )
        #expect(activation == .awaitingModifier(.command))
        #expect(activation.showsZones == false)
    }

    @Test("Unterhalb der Mindeststrecke passiert nichts, auch mit ⌘")
    func nothingHappensBelowTheThreshold() {
        // Without this, a plain click on a title bar would flash the overlay.
        let settings = DropzoneSettings()
        let activation = DropzoneActivator.activation(settings: settings, modifiers: [.command], travelled: 3)
        #expect(activation.showsZones == false)
        if case let .belowThreshold(travelled, required) = activation {
            #expect(travelled == 3)
            #expect(required == settings.minimumDragDistance)
        } else {
            Issue.record("erwartet: belowThreshold, bekommen: \(activation)")
        }
    }

    @Test("Die alte Form „immer zeigen, außer bei Taste X“ unterdrückt weiter")
    func showsUnlessSuppressesLikeBefore() {
        // The legacy polarity, kept for people who prefer it: zones on every
        // drag, key silences them. `showsUnless(.option)` is exactly the shape
        // an existing config.json with `suppressionModifier: "option"` migrates
        // to (see the settings decoding suite).
        var settings = DropzoneSettings()
        settings.activation = .showsUnless(.option)
        #expect(DropzoneActivator.activation(settings: settings, modifiers: [.option], travelled: 500) == .suppressed(.option))
        #expect(DropzoneActivator.activation(settings: settings, modifiers: [], travelled: 500) == .show)
    }

    @Test("Ein anderer Modifikator unterdrückt bei der alten Form nicht")
    func anotherModifierDoesNotSuppress() {
        // ⌘-dragging moves a background window without activating it — an
        // established macOS gesture. Claiming it for suppression would break
        // something the user already relies on, so only the configured key
        // counts.
        var settings = DropzoneSettings()
        settings.activation = .showsUnless(.option)
        #expect(DropzoneActivator.activation(settings: settings, modifiers: [.command], travelled: 500) == .show)
    }

    @Test("„keiner“ bei showsUnless heißt: immer zeigen")
    func showsUnlessNoneMeansAlways() {
        var settings = DropzoneSettings()
        settings.activation = .showsUnless(.none)
        let all: ModifierState = [.shift, .control, .option, .command]
        #expect(DropzoneActivator.activation(settings: settings, modifiers: all, travelled: 500) == .show)
    }

    @Test("„keiner“ bei showsWhile ist sinnlos und wird als always gelesen")
    func showsWhileNoneFallsThroughToShown() {
        // A rule that requires *nothing* to be held is exactly what
        // `showsUnless(.none)` already says. Rather than reject the file at
        // load — which would take an existing feature away from anyone who
        // typed it — the activation treats it as the same thing: no gate.
        var settings = DropzoneSettings()
        settings.activation = .showsWhile(.none)
        #expect(DropzoneActivator.activation(settings: settings, modifiers: [], travelled: 500) == .show)
    }

    @Test("Abgeschaltet schlägt alles andere")
    func disabledBeatsEverything() {
        var settings = DropzoneSettings()
        settings.enabled = false
        #expect(DropzoneActivator.activation(settings: settings, modifiers: [.command], travelled: 999) == .disabled)
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
            .awaitingModifier(.command),
            .belowThreshold(travelled: 2, required: 12),
        ]
        for activation in cases {
            #expect(activation.explanation.isEmpty == false)
        }
    }

    @Test("Der Grund „drück ⌘“ nennt die Taste")
    func awaitingModifierNamesTheKey() {
        // Not decoration: a first-time user who sees the zones stay away needs
        // to read *press ⌘ so the zones appear* somewhere. If the sentence did
        // not name the key, the menu could not explain the new default.
        let sentence = DropzoneActivation.awaitingModifier(.command).explanation
        #expect(sentence.contains("Befehl"))
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
        {"enabled": false, "activation": {"showsWhile": "shift"}}
        """
        let settings = try JSONDecoder().decode(DropzoneSettings.self, from: Data(json.utf8))
        #expect(settings.enabled == false)
        #expect(settings.activation == .showsWhile(.shift))
        #expect(settings.minimumDragDistance == DropzoneSettings().minimumDragDistance)
        #expect(settings.offerRule == DropzoneSettings().offerRule)
    }

    @Test("Die Einstellungen überleben eine Runde durch JSON")
    func settingsSurviveARoundTrip() throws {
        var settings = DropzoneSettings()
        settings.activation = .showsUnless(.control)
        settings.minimumDragDistance = 20
        settings.offerRule = true
        let data = try JSONEncoder().encode(settings)
        #expect(try JSONDecoder().decode(DropzoneSettings.self, from: data) == settings)
    }

    @Test("Ein alter suppressionModifier bildet auf showsUnless ab")
    func legacySuppressionModifierMigratesToShowsUnless() throws {
        // The trap this guards is exactly the one the issue names: without a
        // migration, a config.json written before this change would silently
        // move to the new default, and the user's zones would stop appearing
        // on a plain drag. The old key still counts, and its polarity — *shows
        // unless* — is what it always meant.
        let json = """
        {"suppressionModifier": "option"}
        """
        let settings = try JSONDecoder().decode(DropzoneSettings.self, from: Data(json.utf8))
        #expect(settings.activation == .showsUnless(.option))
    }

    @Test("Der neue Aktivierungsschlüssel schlägt den alten")
    func newActivationKeyBeatsTheLegacyOne() throws {
        // A hand-written override should not be overturned by an outdated
        // sibling. The migration path exists for files that carry only the old
        // key; files that carry both mean the new one.
        let json = """
        {"suppressionModifier": "option", "activation": {"showsWhile": "shift"}}
        """
        let settings = try JSONDecoder().decode(DropzoneSettings.self, from: Data(json.utf8))
        #expect(settings.activation == .showsWhile(.shift))
    }

    @Test("Ein Aktivierungs-Feld ohne Form ist ein Fehler, keine stille Vorgabe")
    func activationWithoutFormRejectsTheFile() {
        // An empty `activation: {}` would be silently helpful — falling back to
        // the default — and would hide a typo in exactly the setting whose new
        // polarity people are least likely to notice.
        let json = """
        {"activation": {}}
        """
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(DropzoneSettings.self, from: Data(json.utf8))
        }
    }

    @Test("Die neue Vorgabe ist ⌘ als Einschalter, Rückfrage aus")
    func newDefaultsMatchTheIssue() {
        // The two changes the issue asks for in one line, so a future edit that
        // moves one of them stumbles here rather than in a user's log.
        let defaults = DropzoneSettings()
        #expect(defaults.activation == .showsWhile(.command))
        #expect(defaults.offerRule == false)
    }

    @Test("Das gespeicherte Feld heißt activation, nicht suppressionModifier")
    func encodingUsesTheNewKeyOnly() throws {
        // Two names for the same setting in the same file is the shape most
        // likely to drift on the next hand edit. Only the new key is written;
        // the old one exists as a read-only migration bridge.
        let data = try JSONEncoder().encode(DropzoneSettings())
        let json = String(decoding: data, as: UTF8.self)
        #expect(json.contains("activation"))
        #expect(json.contains("suppressionModifier") == false)
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
