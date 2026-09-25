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
            case .grantAccess: return localized("menuStatus.action.grantAccess", "Grant Access …")
            case .explain: return localized("menuStatus.action.explain", "What to Do? …")
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
                title: localized(
                    "menuStatus.line.needsPermission",
                    "Access is missing — without it OpenZonr cannot move windows"
                ),
                action: .grantAccess
            )
        case .needsConfiguration:
            return Line(
                title: hasProblem
                    ? localized("menuStatus.line.needsConfiguration.unreadable", "The settings cannot be read")
                    : localized("menuStatus.line.needsConfiguration.notSetUp", "Nothing set up yet"),
                action: .explain
            )
        case .noProfile:
            return Line(
                title: localized(
                    "menuStatus.line.noProfile",
                    "No setup matches the connected screens"
                ),
                action: .explain
            )
        case .paused:
            return Line(
                title: localized("menuStatus.line.paused", "Paused — nothing is placed automatically"),
                action: nil
            )
        case .active:
            if isPaused {
                // Cannot occur in the model; the decision still belongs here
                // and not in the view.
                return Line(
                    title: localized("menuStatus.line.paused", "Paused — nothing is placed automatically"),
                    action: nil
                )
            }
            guard let profileName, !profileName.isEmpty else {
                return Line(title: localized("menuStatus.line.active.noName", "Ready"), action: nil)
            }
            return Line(
                title: localized("menuStatus.line.active.withName", "Ready — Setup “%@”", profileName),
                action: nil
            )
        }
    }

    /// Was der Update-Block ganz oben im Menü zeigt.
    ///
    /// Eigener Wert und keine `if`-Verschachtelung in der Ansicht, weil die
    /// Verschachtelung genau hier schon einmal falsch war: die Zustandszeile
    /// stand innerhalb der Bedingung „es gibt einen Installieren-Knopf“, und
    /// damit hatten „wird geladen“, „wird installiert“ und ein im Hintergrund
    /// gescheiterter Versuch **gar keine** Oberfläche mehr. Die Zeile ist die
    /// äussere Bedingung, die Knöpfe sind die innere.
    struct UpdateBanner: Equatable {
        /// Die Zustandszeile, oder `nil`, wenn es nichts zu sagen gibt.
        var line: String?
        /// Die Aufschrift des Installieren-Knopfs, oder `nil`.
        var installTitle: String?

        /// Ob überhaupt etwas erscheint.
        var isVisible: Bool { line != nil }
    }

    static func updateBanner(for state: UpdateState) -> UpdateBanner {
        UpdateBanner(
            line: UpdatePolicy.statusLine(for: state),
            installTitle: UpdatePolicy.installTitle(for: state)
        )
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
        case .everyDrag: return localized("dropzoneTrigger.label.everyDrag", "Every Drag")
        case .commandHeld: return localized("dropzoneTrigger.label.commandHeld", "Only While Holding ⌘")
        case .off: return localized("dropzoneTrigger.label.off", "Off")
        }
    }

    /// Same statement for the parent row, where it sits after a colon:
    /// "Zones while dragging: only with ⌘".
    var shortLabel: String {
        switch self {
        case .everyDrag: return localized("dropzoneTrigger.shortLabel.everyDrag", "every drag")
        case .commandHeld: return localized("dropzoneTrigger.shortLabel.commandHeld", "only with ⌘")
        case .off: return localized("dropzoneTrigger.shortLabel.off", "off")
        }
    }

    /// Welche der drei Zeilen diese Aktivierungsregel ausdrückt — **ohne**
    /// Rücksicht darauf, ob die Zonen gerade eingeschaltet sind.
    ///
    /// Die Trennung ist der Punkt: `enabled` und `activation` sind zwei Felder,
    /// und „Aus“ löscht die Regel nicht. Wer das zusammenwirft, verliert eine
    /// von Hand eingetragene Regel aus den Augen, sobald jemand ausschaltet —
    /// und der Editor zeigt `activation` nicht, es gäbe also keinen Weg zurück.
    static func expressing(_ activation: DropzoneActivationRule) -> DropzoneTrigger? {
        switch activation {
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

    /// Der **wirksame** Zustand der geladenen Einstellungen.
    ///
    /// `nil`, wenn in der Datei eine Regel steht, die keine der drei
    /// Möglichkeiten ausdrückt — etwa „nur mit ⌥“ aus einer alten Fassung oder
    /// von Hand geschrieben. Dann gehört ein eigener, angehakter Eintrag ins
    /// Menü; ein Haken an der nächstähnlichen Zeile wäre schlicht falsch.
    static func current(_ settings: DropzoneSettings) -> DropzoneTrigger? {
        guard settings.enabled else { return .off }
        return expressing(settings.activation)
    }

    /// Die Aufschrift der Elternzeile, damit der Zustand sichtbar ist, ohne das
    /// Untermenü zu öffnen.
    ///
    /// Beim alten Schalter stand der Zustand auf der obersten Ebene; mit dem
    /// Untermenü läge er eine Ebene tiefer, und das wäre ein Rückschritt genau
    /// in der Frage, um die es hier geht.
    static func rowTitle(_ settings: DropzoneSettings?) -> String {
        let base = localized("dropzoneTrigger.rowTitle.base", "Zones While Dragging")
        guard let settings else { return base }
        if let current = current(settings) {
            return localized("dropzoneTrigger.rowTitle.withState", "%@: %@", base, current.shortLabel)
        }
        return localized(
            "dropzoneTrigger.rowTitle.withState", "%@: %@", base, customShortLabel(settings.activation)
        )
    }

    /// Die Zeile für eine Regel aus der Datei, die keine der drei Wahlen ist —
    /// oder `nil`, wenn es keine solche gibt.
    ///
    /// Sie erscheint **auch**, während die Zonen aus sind. Sonst verschwände
    /// eine von Hand eingetragene Regel aus dem Menü, sobald jemand „Aus“
    /// wählt, und käme nie wieder zum Vorschein: der Editor zeigt `activation`
    /// nicht, und jede der drei Wahlen überschreibt sie.
    static func customRow(_ settings: DropzoneSettings) -> CustomRow? {
        guard expressing(settings.activation) == nil else { return nil }
        if settings.enabled {
            return CustomRow(
                label: localized("dropzoneTrigger.customRow.active", "%@ (from the file)", customLabel(settings)),
                isActive: true
            )
        }
        // Both facts in one sentence: it is off, and the rule is still there.
        return CustomRow(
            label: localized(
                "dropzoneTrigger.customRow.inactive",
                "The file says “%@” — currently off, turn back on here",
                customLabel(settings)
            ),
            isActive: false
        )
    }

    /// Eine Zeile für eine Regel, die keine der drei Wahlen ist.
    struct CustomRow: Equatable {
        var label: String
        /// Ob die Regel gerade wirkt (und deshalb einen Haken trägt). Trägt sie
        /// keinen, ist die Zeile der Weg zurück: anklicken schaltet ein, ohne
        /// die Regel anzutasten.
        var isActive: Bool
    }

    /// Schaltet die Zonen ein und lässt die Aktivierungsregel unberührt.
    ///
    /// Das ist der Weg zurück, den ``applied(to:)`` verspricht: „Aus“ lässt die
    /// Regel stehen, und ohne diesen Weg wäre das Versprechen unerfüllbar.
    static func enablingKeepingRule(_ settings: DropzoneSettings) -> DropzoneSettings {
        var settings = settings
        settings.enabled = true
        return settings
    }

    private static func customShortLabel(_ activation: DropzoneActivationRule) -> String {
        switch activation {
        case let .showsWhile(modifier):
            guard let symbol = modifier.symbol else {
                return localized("dropzoneTrigger.shortLabel.everyDrag", "every drag")
            }
            return localized("dropzoneTrigger.customShortLabel.onlyWith", "only with %@", symbol)
        case let .showsUnless(modifier):
            guard let symbol = modifier.symbol else {
                return localized("dropzoneTrigger.shortLabel.everyDrag", "every drag")
            }
            return localized("dropzoneTrigger.customShortLabel.everyDragExcept", "every drag except with %@", symbol)
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
            guard let symbol = modifier.symbol else {
                return localized("dropzoneTrigger.label.everyDrag", "Every Drag")
            }
            return localized("dropzoneTrigger.customLabel.onlyWhileHolding", "Only While Holding %@", symbol)
        case let .showsUnless(modifier):
            guard let symbol = modifier.symbol else {
                return localized("dropzoneTrigger.label.everyDrag", "Every Drag")
            }
            return localized("dropzoneTrigger.customLabel.everyDragExcept", "Every Drag Except With %@", symbol)
        }
    }
}
