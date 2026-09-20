import Testing
@testable import OpenZonrApp
@testable import OpenZonrCore

/// Die drei Zeilen unter „Zonen beim Ziehen“ und ihre Abbildung auf die
/// Einstellungen.
///
/// Der Haken muss am **wirksamen** Zustand stehen — an dem, was beim nächsten
/// Zug tatsächlich passiert, nicht an dem, was zuletzt angeklickt wurde. Der
/// offene Fehler des Betreuers („die Dropzones kommen nicht, wenn ich Command
/// drücke“) ist genau die Frage, ob Anzeige und Wirkung übereinstimmen.
@Suite("Menü — Zonen beim Ziehen")
struct DropzoneTriggerTests {

    @Test("Die Voreinstellung ist „nur mit ⌘“")
    func defaultIsCommand() {
        #expect(DropzoneTrigger.current(DropzoneSettings()) == .commandHeld)
    }

    @Test("Abgeschaltet schlägt jede Aktivierungsregel")
    func offWins() {
        let settings = DropzoneSettings(enabled: false, activation: .showsWhile(.command))
        #expect(DropzoneTrigger.current(settings) == .off)
    }

    @Test("Ohne Taste heisst: bei jedem Ziehen")
    func everyDrag() {
        #expect(DropzoneTrigger.current(DropzoneSettings(activation: .showsUnless(.none))) == .everyDrag)
    }

    @Test("`showsWhile(.none)` zeigt wirksam immer — und wird auch so angehakt")
    func showsWhileNoneIsEveryDrag() {
        // ``DropzoneActivator`` fällt für `.none` auf „immer zeigen“ zurück.
        // Ein Haken bei „Aus“ wäre hier schlicht falsch.
        #expect(DropzoneTrigger.current(DropzoneSettings(activation: .showsWhile(.none))) == .everyDrag)
        #expect(
            DropzoneActivator.activation(
                settings: DropzoneSettings(activation: .showsWhile(.none)),
                modifiers: [],
                travelled: 100
            ) == .show
        )
    }

    @Test("Eine Regel aus der Datei, die keine der drei Zeilen ist, bekommt keinen falschen Haken")
    func customRuleHasNoChoice() {
        let settings = DropzoneSettings(activation: .showsWhile(.option))
        #expect(DropzoneTrigger.current(settings) == nil)
        #expect(DropzoneTrigger.customLabel(settings) == "Nur mit gehaltener ⌥-Taste")

        let inverse = DropzoneSettings(activation: .showsUnless(.shift))
        #expect(DropzoneTrigger.current(inverse) == nil)
        #expect(DropzoneTrigger.customLabel(inverse) == "Bei jedem Ziehen ausser mit ⇧")
    }

    @Test("Die Wahl verändert nur, was sie verspricht")
    func appliedKeepsEverythingElse() {
        let settings = DropzoneSettings(
            enabled: false,
            activation: .showsUnless(.option),
            offerRule: true,
            minimumDragDistance: 42,
            warnAboutCompetingManagers: false
        )

        let command = DropzoneTrigger.commandHeld.applied(to: settings)
        #expect(command.enabled)
        #expect(command.activation == .showsWhile(.command))
        #expect(command.offerRule)
        #expect(command.minimumDragDistance == 42)
        #expect(command.warnAboutCompetingManagers == false)

        let every = DropzoneTrigger.everyDrag.applied(to: settings)
        #expect(every.enabled)
        #expect(every.activation == .showsUnless(.none))

        // „Aus“ lässt die Regel stehen: wer wieder einschaltet, bekommt zurück,
        // was er hatte — solange er nicht eine der anderen Zeilen wählt.
        let off = DropzoneTrigger.off.applied(to: settings)
        #expect(off.enabled == false)
        #expect(off.activation == .showsUnless(.option))
    }

    @Test("Jede Wahl ist ihr eigener Fixpunkt")
    func roundTrip() {
        for trigger in DropzoneTrigger.allCases where trigger != .off {
            #expect(DropzoneTrigger.current(trigger.applied(to: DropzoneSettings())) == trigger)
        }
        #expect(DropzoneTrigger.current(DropzoneTrigger.off.applied(to: DropzoneSettings())) == .off)
    }

    @Test("Die Beschriftungen sagen, wann die Zonen kommen")
    func labels() {
        #expect(DropzoneTrigger.everyDrag.label == "Bei jedem Ziehen")
        #expect(DropzoneTrigger.commandHeld.label == "Nur mit gehaltener ⌘-Taste")
        #expect(DropzoneTrigger.off.label == "Aus")
    }
}
