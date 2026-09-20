import Testing
@testable import OpenZonrCore

/// Der Satz, der im Menü steht, wenn ein Zug vorbei ist.
///
/// Er ist die einzige Rückmeldung über das Ziehen, die ein Nutzer je zu sehen
/// bekommt — und der einzige Hinweis, den der offene Fehler „die Zonen kommen
/// nicht mit ⌘" hinterlässt. Ein falscher Satz führt die Suche in die falsche
/// Richtung, deshalb steht jede Formulierung hier einzeln.
@Suite("Letzter Zug — der Satz im Menü")
struct DragOutcomeWordingTests {

    @Test("Ohne beobachteten Zug gibt es keine Zeile")
    func noOutcomeNoLine() {
        #expect(DragOutcomeWording.sentence(for: nil) == nil)
    }

    @Test("Zonen gesehen")
    func shown() {
        #expect(DragOutcomeWording.sentence(for: .zonesShown) == "Letzter Zug: Zonen wurden angezeigt.")
    }

    @Test("Der Fall aus dem offenen Fehler: ⌘ war nicht gedrückt")
    func awaitingCommand() {
        #expect(
            DragOutcomeWording.sentence(for: .zonesHidden(.awaitingModifier(.command)))
                == "Letzter Zug: keine Zonen — ⌘ war nicht gedrückt."
        )
    }

    @Test("Die alte Polarität: Taste hat die Zonen unterdrückt")
    func suppressed() {
        #expect(
            DragOutcomeWording.sentence(for: .zonesHidden(.suppressed(.option)))
                == "Letzter Zug: keine Zonen — ⌥ war gedrückt."
        )
    }

    @Test("Abgeschaltet nennt den Menüeintrag, nicht das Feld in der Datei")
    func disabled() {
        #expect(
            DragOutcomeWording.sentence(for: .zonesHidden(.disabled))
                == "Letzter Zug: keine Zonen — „Zonen beim Ziehen“ steht auf „Aus“."
        )
    }

    @Test("Zu kurz gezogen — ohne Zahlen")
    func belowThreshold() {
        #expect(
            DragOutcomeWording.sentence(for: .zonesHidden(.belowThreshold(travelled: 3, required: 12)))
                == "Letzter Zug: keine Zonen — es wurde zu kurz gezogen."
        )
    }

    @Test("Eine Taste ohne Symbol lässt keine Lücke im Satz")
    func noneModifier() {
        #expect(
            DragOutcomeWording.sentence(for: .zonesHidden(.awaitingModifier(.none)))
                == "Letzter Zug: keine Zonen."
        )
    }

    @Test("Kein Setup aktiv")
    func noSetup() {
        #expect(
            DragOutcomeWording.sentence(for: .noSetupActive)
                == "Letzter Zug: keine Zonen — für die angeschlossenen Bildschirme ist kein Setup aktiv."
        )
    }

    @Test("Kein Fenster unter dem Zeiger")
    func noWindow() {
        #expect(
            DragOutcomeWording.sentence(for: .noWindowFound)
                == "Letzter Zug: kein Fenster unter dem Zeiger erkannt."
        )
    }

    @Test("Kein Bewegungsbeleg — die zwei Gründe klingen verschieden")
    func noEvidence() {
        #expect(
            DragOutcomeWording.sentence(for: .noMovementEvidence(.budgetExhausted))
                == "Letzter Zug: Bewegung nicht als Fensterzug erkannt."
        )
        #expect(
            DragOutcomeWording.sentence(for: .noMovementEvidence(.resizedInstead))
                == "Letzter Zug: das Fenster wurde in der Grösse geändert, nicht bewegt."
        )
    }

    @Test("Losgelassen, bevor der Beleg da war")
    func released() {
        #expect(
            DragOutcomeWording.sentence(for: .releasedBeforeEvidence)
                == "Letzter Zug: losgelassen, bevor sich das Fenster bewegt hat."
        )
    }

    @Test("Ein Abbruch nennt seinen Grund")
    func cancelled() {
        #expect(
            DragOutcomeWording.sentence(for: .cancelled(reason: "Der Tap wurde abgeschaltet."))
                == "Letzter Zug: abgebrochen — Der Tap wurde abgeschaltet."
        )
    }

    @Test("Ein `show`, das als `hidden` verpackt ankommt, lügt nicht")
    func hiddenShowIsStillShown() {
        #expect(DragOutcomeWording.sentence(for: .zonesHidden(.show)) == "Letzter Zug: Zonen wurden angezeigt.")
    }

    @Test("Jedes Tastensymbol steht für genau eine Taste")
    func symbols() {
        #expect(DropzoneModifier.command.symbol == "⌘")
        #expect(DropzoneModifier.option.symbol == "⌥")
        #expect(DropzoneModifier.control.symbol == "⌃")
        #expect(DropzoneModifier.shift.symbol == "⇧")
        #expect(DropzoneModifier.none.symbol == nil)
    }
}
