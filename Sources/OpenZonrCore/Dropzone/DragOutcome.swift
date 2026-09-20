import Foundation

/// Was beim letzten Zug herauskam — als ein Wert.
///
/// Der Grund für diesen Typ ist ein offener Fehler: auf der Maschine des
/// Betreuers erscheinen die Zonen nicht, wenn ⌘ gedrückt wird, und niemand kann
/// von aussen sehen, woran es liegt. Der Zug scheitert an einer von mehreren
/// Stellen, und alle sind unsichtbar — kein Fenster unter dem Zeiger, kein
/// Bewegungsbeleg (#37), die Taste nicht gesehen, gar kein Zug erkannt.
///
/// Statt das Protokoll durchzusehen, hält die App das Ergebnis des letzten Zugs
/// fest und schreibt einen Satz ins Menü. Der Wert hier ist die Entscheidung,
/// ``DragOutcomeWording`` ist der Satz — getrennt, damit der Satz ohne
/// Bedienungshilfen prüfbar ist.
public enum DragOutcome: Hashable, Sendable {

    /// Die Zonen waren während des Zugs zu sehen.
    case zonesShown

    /// Ein Fensterzug lief, die Zonen blieben aber aus — mit der Begründung,
    /// die ``DropzoneActivator`` dafür geliefert hat.
    case zonesHidden(DropzoneActivation)

    /// Ein Fensterzug lief, aber für die angeschlossenen Bildschirme ist kein
    /// Setup aktiv — dann gibt es keine Zonen, die man anzeigen könnte.
    case noSetupActive

    /// Ein Fensterzug lief, die Zonen blieben aus, und es wurde **kein** Grund
    /// aufgezeichnet — etwa weil zwischen Anfang und Ende kein einziges
    /// `.moved` ankam.
    ///
    /// Ein eigener Fall und kein Rückfall auf ``zonesHidden(_:)`` mit
    /// ``DropzoneActivation/disabled``: der würde eine Ursache behaupten, die
    /// niemand gemessen hat. „Ich weiss es nicht" ist hier die einzige
    /// ehrliche Auskunft — und bei einem Fehler, dessen Ursache offen ist,
    /// auch die einzige nützliche.
    case zonesHiddenWithoutReason

    /// Unter dem Druckpunkt lag kein Fenster. Ein Zug auf dem Schreibtisch, in
    /// einer Textansicht, an einem Scrollbalken.
    case noWindowFound

    /// Ein Fenster war da, aber seine Bewegung liess sich nicht belegen (#37).
    case noMovementEvidence(MovementGap)

    /// Losgelassen, bevor ein Beleg eintraf.
    case releasedBeforeEvidence

    /// Der Zug wurde abgebrochen.
    case cancelled(reason: String)

    /// Warum der Bewegungsbeleg ausblieb.
    public enum MovementGap: Hashable, Sendable {
        /// Die Zeit für Rahmenabrufe war aufgebraucht, ohne dass sich der
        /// Rahmen bewegt hat — oder der Rahmen war nie lesbar.
        case budgetExhausted
        /// Der Rahmen hat sich geändert, aber als Grössenänderung: ein
        /// Kantenzug, kein Verschieben.
        case resizedInstead
    }
}

/// Ein Satz in Alltagssprache für ``DragOutcome``.
///
/// Rein und ohne AppKit, weil genau das die Stelle ist, die man prüfen kann:
/// Der Satz steht im Menü und ist die einzige Rückmeldung, die ein Nutzer über
/// das Ziehen bekommt. Ein falscher Satz wäre schlimmer als gar keiner.
public enum DragOutcomeWording {

    /// - Returns: `nil`, wenn noch kein Zug beobachtet wurde — dann steht im
    ///   Menü auch keine Zeile.
    public static func sentence(for outcome: DragOutcome?) -> String? {
        guard let outcome else { return nil }
        return "Letzter Zug: \(tail(outcome))"
    }

    private static func tail(_ outcome: DragOutcome) -> String {
        switch outcome {
        case .zonesShown:
            return "Zonen wurden angezeigt."
        case let .zonesHidden(activation):
            return hidden(activation)
        case .noSetupActive:
            return "keine Zonen — für die angeschlossenen Bildschirme ist kein Setup aktiv."
        case .zonesHiddenWithoutReason:
            return "keine Zonen — der Grund wurde nicht aufgezeichnet."
        case .noWindowFound:
            return "kein Fenster unter dem Zeiger erkannt."
        case .noMovementEvidence(.budgetExhausted):
            return "Bewegung nicht als Fensterzug erkannt."
        case .noMovementEvidence(.resizedInstead):
            return "das Fenster wurde in der Grösse geändert, nicht bewegt."
        case .releasedBeforeEvidence:
            return "losgelassen, bevor sich das Fenster bewegt hat."
        case let .cancelled(reason):
            return "abgebrochen — \(reason)"
        }
    }

    private static func hidden(_ activation: DropzoneActivation) -> String {
        switch activation {
        case .show:
            return "Zonen wurden angezeigt."
        case .disabled:
            return "keine Zonen — „Zonen beim Ziehen“ steht auf „Aus“."
        case let .suppressed(modifier):
            guard let symbol = modifier.symbol else { return "keine Zonen." }
            return "keine Zonen — \(symbol) war gedrückt."
        case let .awaitingModifier(modifier):
            guard let symbol = modifier.symbol else { return "keine Zonen." }
            return "keine Zonen — \(symbol) war nicht gedrückt."
        case .belowThreshold:
            return "keine Zonen — es wurde zu kurz gezogen."
        }
    }
}
