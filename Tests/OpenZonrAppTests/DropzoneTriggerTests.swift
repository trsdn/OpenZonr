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
        #expect(DropzoneTrigger.customRow(settings)?.isActive == true)
        #expect(DropzoneTrigger.customRow(settings)?.label == "Nur mit gehaltener ⌥-Taste (aus der Datei)")

        let inverse = DropzoneSettings(activation: .showsUnless(.shift))
        #expect(DropzoneTrigger.current(inverse) == nil)
        #expect(DropzoneTrigger.customLabel(inverse) == "Bei jedem Ziehen ausser mit ⇧")
    }

    @Test("Ausgeschaltet verschwindet eine Regel aus der Datei nicht aus dem Menü")
    func customRuleStaysVisibleWhileOff() {
        // Der Fehler, den das verhindert: `current` meldet für `enabled: false`
        // schlicht „Aus", und eine an `current == nil` gehängte Zeile wäre dann
        // unsichtbar. Der Editor zeigt `activation` nicht — die Regel wäre weg,
        // ohne dass sie jemand gelöscht hätte.
        let settings = DropzoneSettings(enabled: false, activation: .showsWhile(.option))
        #expect(DropzoneTrigger.current(settings) == .off)
        let row = DropzoneTrigger.customRow(settings)
        #expect(row?.isActive == false)
        // Beide Tatsachen in einem Satz: es ist aus, und die Regel steht noch da.
        #expect(row?.label.contains("Nur mit gehaltener ⌥-Taste") == true)
        #expect(row?.label.contains("zurzeit aus") == true)
    }

    @Test("Eine ausdrückbare Regel bekommt keine eigene Zeile — auch nicht ausgeschaltet")
    func expressibleRuleHasNoCustomRow() {
        #expect(DropzoneTrigger.customRow(DropzoneSettings()) == nil)
        #expect(DropzoneTrigger.customRow(DropzoneSettings(enabled: false)) == nil)
        #expect(DropzoneTrigger.customRow(DropzoneSettings(activation: .showsUnless(.none))) == nil)
    }

    @Test("Die Ausdrückbarkeit hängt nicht am Ein/Aus-Schalter")
    func expressibilityIsIndependentOfEnabled() {
        #expect(DropzoneTrigger.expressing(.showsWhile(.command)) == .commandHeld)
        #expect(DropzoneTrigger.expressing(.showsUnless(.none)) == .everyDrag)
        #expect(DropzoneTrigger.expressing(.showsWhile(.none)) == .everyDrag)
        #expect(DropzoneTrigger.expressing(.showsWhile(.option)) == nil)
        #expect(DropzoneTrigger.expressing(.showsUnless(.shift)) == nil)
    }

    @Test("Der Weg zurück schaltet ein und lässt die Regel unberührt")
    func enablingKeepsTheRule() {
        let off = DropzoneSettings(enabled: false, activation: .showsWhile(.option))
        let back = DropzoneTrigger.enablingKeepingRule(off)
        #expect(back.enabled)
        #expect(back.activation == .showsWhile(.option))
        #expect(DropzoneTrigger.customRow(back)?.isActive == true)
    }

    @Test("Die Elternzeile zeigt den Zustand, ohne dass man sie aufklappt")
    func rowTitleShowsState() {
        #expect(DropzoneTrigger.rowTitle(nil) == "Zonen beim Ziehen")
        #expect(DropzoneTrigger.rowTitle(DropzoneSettings()) == "Zonen beim Ziehen: nur mit ⌘")
        #expect(
            DropzoneTrigger.rowTitle(DropzoneSettings(activation: .showsUnless(.none)))
                == "Zonen beim Ziehen: bei jedem Ziehen"
        )
        #expect(DropzoneTrigger.rowTitle(DropzoneSettings(enabled: false)) == "Zonen beim Ziehen: aus")
        #expect(
            DropzoneTrigger.rowTitle(DropzoneSettings(activation: .showsWhile(.option)))
                == "Zonen beim Ziehen: nur mit ⌥"
        )
        #expect(
            DropzoneTrigger.rowTitle(DropzoneSettings(activation: .showsUnless(.shift)))
                == "Zonen beim Ziehen: bei jedem Ziehen ausser mit ⇧"
        )
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

        // „Aus“ lässt die Regel stehen. Sichtbar bleibt sie über
        // ``DropzoneTrigger/customRow(_:)``, und der Weg zurück ist genau diese
        // Zeile (``enablingKeepingRule(_:)``) — ohne sie wäre das Versprechen
        // „die Regel bleibt" unerfüllbar, weil der Editor `activation` nicht
        // zeigt und jede der drei Wahlen sie überschreibt.
        let off = DropzoneTrigger.off.applied(to: settings)
        #expect(off.enabled == false)
        #expect(off.activation == .showsUnless(.option))
        #expect(DropzoneTrigger.customRow(off)?.isActive == false)
        #expect(DropzoneTrigger.enablingKeepingRule(off).activation == .showsUnless(.option))
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
