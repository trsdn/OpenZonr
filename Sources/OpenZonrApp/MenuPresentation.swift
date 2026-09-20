import Foundation
import OpenZonrCore

/// Der Text des Menüs, getrennt von seiner Darstellung.
///
/// Das Menü war zu technisch: es zeigte Zustandsnamen aus dem Programm
/// („Kein Profil passt — 2 Profile in der Konfiguration“) statt zu sagen, was
/// los ist und was zu tun wäre. Der Umbau verlegt die Wortwahl hierher, weil
/// sie damit prüfbar wird — eine `MenuBarExtra` lässt sich nicht aufklappen und
/// ablesen, eine Funktion schon.
enum MenuStatus {

    /// Die eine Zeile, die sagt, woran man ist — plus höchstens ein Knopf.
    struct Line: Equatable {
        var title: String
        var action: Action?
    }

    /// Was in der aktuellen Lage zu tun wäre. Beide Wege enden im Statusfenster,
    /// aber sie versprechen Verschiedenes, und ein Knopf muss halten, was sein
    /// Titel sagt.
    enum Action: Equatable {
        /// Fehlender Zugriff — der einzige Fall, in dem gar nichts geht.
        case grantAccess
        /// Etwas fehlt oder passt nicht; das Fenster erklärt, was.
        case explain

        var title: String {
            switch self {
            case .grantAccess: return "Zugriff freigeben …"
            case .explain: return "Was ist zu tun? …"
            }
        }
    }

    /// Die Kopfzeile: Name und Fassung, immer als erster Eintrag.
    ///
    /// Aus Issue #56. Ohne sie beginnt das Menü mit einer Zustandszeile, und in
    /// einer Menüleiste mit einem Dutzend Symbolen ist nicht zu sehen, wessen
    /// Menü gerade offen ist. Die Fassung steht dazu, weil die häufigste Frage
    /// an einen Fehlerbericht „welche Version?“ lautet.
    ///
    /// `__VERSION__` ist der Platzhalter aus `Info.plist`, den erst der Bau
    /// ersetzt; ein Bundle, das ihn noch trägt, zeigt lieber gar keine Nummer.
    static func header(version: String?) -> String {
        guard let version, !version.isEmpty, version != "__VERSION__" else { return "OpenZonr" }
        return "OpenZonr \(version)"
    }

    /// - Parameters:
    ///   - status: der Zustand, den das Modell führt.
    ///   - profileName: Name des aktiven Setups, wenn eines aktiv ist.
    ///   - isPaused: ob die Platzierung von Hand angehalten wurde.
    ///   - hasProblem: ob beim Laden der Einstellungen etwas gemeldet wurde.
    ///     Unterscheidet „noch nichts eingerichtet“ von „nicht lesbar“ — zwei
    ///     Lagen, die sich völlig verschieden anfühlen und bisher denselben
    ///     Satz bekamen.
    static func line(
        status: AppModel.Status,
        profileName: String?,
        isPaused: Bool,
        hasProblem: Bool
    ) -> Line {
        switch status {
        case .needsPermission:
            return Line(
                title: "Zugriff fehlt — ohne ihn kann OpenZonr keine Fenster bewegen",
                action: .grantAccess
            )
        case .needsConfiguration:
            return Line(
                title: hasProblem
                    ? "Die Einstellungen lassen sich nicht lesen"
                    : "Noch nichts eingerichtet",
                action: .explain
            )
        case .noProfile:
            return Line(
                title: "Kein Setup passt zu den angeschlossenen Bildschirmen",
                action: .explain
            )
        case .paused:
            return Line(title: "Pausiert — es wird nichts automatisch platziert", action: nil)
        case .active:
            if isPaused {
                // Kann im Modell nicht vorkommen; die Entscheidung gehört
                // trotzdem hierher und nicht in die Ansicht.
                return Line(title: "Pausiert — es wird nichts automatisch platziert", action: nil)
            }
            guard let profileName, !profileName.isEmpty else {
                return Line(title: "Bereit", action: nil)
            }
            return Line(title: "Bereit — Setup „\(profileName)“", action: nil)
        }
    }
}

/// Wann die Zonen beim Ziehen erscheinen — als das, was im Menü zur Wahl steht.
///
/// Bisher standen dafür zwei voneinander unabhängige Dinge im Menü: ein Schalter
/// „Fenster in Zonen ziehen“ und, gar nicht sichtbar, die Aktivierungsregel aus
/// der Datei. Wer die Zonen nicht sah, konnte am Schalter nichts erkennen. Die
/// drei Möglichkeiten hier sagen jeweils genau, **wann** die Zonen kommen — das
/// ist die Frage, die ein Nutzer tatsächlich hat.
enum DropzoneTrigger: String, CaseIterable, Identifiable, Sendable {
    case everyDrag
    case commandHeld
    case off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .everyDrag: return "Bei jedem Ziehen"
        case .commandHeld: return "Nur mit gehaltener ⌘-Taste"
        case .off: return "Aus"
        }
    }

    /// Der **wirksame** Zustand der geladenen Einstellungen.
    ///
    /// `nil`, wenn in der Datei eine Regel steht, die keine der drei
    /// Möglichkeiten ausdrückt — etwa „nur mit ⌥“ aus einer alten Fassung oder
    /// von Hand geschrieben. Dann gehört ein eigener, angehakter Eintrag ins
    /// Menü; ein Haken an der nächstähnlichen Zeile wäre schlicht falsch.
    static func current(_ settings: DropzoneSettings) -> DropzoneTrigger? {
        guard settings.enabled else { return .off }
        switch settings.activation {
        case .showsWhile(.command):
            return .commandHeld
        case .showsUnless(.none), .showsWhile(.none):
            // `showsWhile(.none)` fällt in ``DropzoneActivator`` auf „immer
            // zeigen“ zurück; wirksam ist das dasselbe wie `showsUnless(.none)`.
            return .everyDrag
        default:
            return nil
        }
    }

    /// Wie diese Wahl die Einstellungen verändert. Alles andere bleibt, wie es
    /// war — insbesondere Mindeststrecke und Angebots-Schalter.
    func applied(to settings: DropzoneSettings) -> DropzoneSettings {
        var settings = settings
        switch self {
        case .off:
            settings.enabled = false
        case .everyDrag:
            settings.enabled = true
            settings.activation = .showsUnless(.none)
        case .commandHeld:
            settings.enabled = true
            settings.activation = .showsWhile(.command)
        }
        return settings
    }

    /// Ein Satz für eine Regel aus der Datei, die keine der drei Wahlen ist.
    static func customLabel(_ settings: DropzoneSettings) -> String {
        switch settings.activation {
        case let .showsWhile(modifier):
            guard let symbol = modifier.symbol else { return "Bei jedem Ziehen" }
            return "Nur mit gehaltener \(symbol)-Taste"
        case let .showsUnless(modifier):
            guard let symbol = modifier.symbol else { return "Bei jedem Ziehen" }
            return "Bei jedem Ziehen ausser mit \(symbol)"
        }
    }
}
