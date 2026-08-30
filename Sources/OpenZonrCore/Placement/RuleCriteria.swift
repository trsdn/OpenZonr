import Foundation

/// Welche Kriterien einer Regel lassen sich ohne ein tatsächlich beobachtetes
/// Fenster überhaupt beantworten — und welche nicht?
///
/// Dieser Typ ist der eigentliche Wert der Dry-Run-Zeile für Fall B: für ein
/// Bundle, dessen App gerade nicht läuft, gibt es kein `WindowSnapshot`. Wer
/// die Rege trotzdem „ausrechnet", indem er Titel, Rolle, Subrolle,
/// Größe, Seitenverhältnis und „nur das erste Fenster" implizit ignoriert oder
/// erfindet, gibt eine Vermutung im Gewand einer Rechnung aus. Dieselbe
/// Fehlerklasse, die dieses Projekt sonst bekämpft.
///
/// Der Auslöser für diesen Typ steht ausführlich in Issue #19: in der real
/// existierenden Konfiguration prüfen alle drei Regeln ausschließlich das
/// Bundle. Ein naiver Dry-Run wäre dort zufällig exakt und würde still falsch
/// in dem Moment, in dem die erste Titel- oder Größenregel hinzukäme.
///
/// Die Fassung als reine Funktion ist Absicht: keine Abhängigkeit auf
/// `NSScreen`, keine auf AppKit, keine auf das Fenstersystem — der Test läuft
/// auf jeder Kiste, auch in CI.
public enum RuleCriteria {

    /// Ein einzelnes Kriterium, das eine Regel prüft.
    public enum Criterion: Hashable, Sendable, CustomStringConvertible {
        case bundleIdentifier(String)
        case title(pattern: String)
        case roles([String])
        case subroles([String])
        case minimumSize(WindowSize)
        case maximumSize(WindowSize)
        case aspectRatio(AspectRatioRange)
        case onlyFirstWindowAfterLaunch(Bool)

        /// Beschriftung für die Oberfläche. Bewusst kurz — die Dry-Run-Zeile
        /// ist eine Zeile, keine Liste.
        public var description: String {
            switch self {
            case .bundleIdentifier: return "Bundle-Kennung"
            case .title:            return "Fenstertitel"
            case .roles:            return "Rolle (AX)"
            case .subroles:         return "Subrolle (AX)"
            case .minimumSize:      return "Mindestgröße"
            case .maximumSize:      return "Höchstgröße"
            case .aspectRatio:      return "Seitenverhältnis"
            case .onlyFirstWindowAfterLaunch:
                                    return "erstes Fenster nach Start"
            }
        }
    }

    /// Auswertung eines `WindowMatch` samt globaler Voreinstellungen unter der
    /// Annahme, dass nur die Bundle-Kennung bekannt ist.
    ///
    /// - `decidable` sind Kriterien, deren Wahrheitswert allein aus der
    ///   Bundle-Kennung und den Voreinstellungen folgt. Genau eines: die
    ///   Bundle-Kennung selbst, wenn die Regel überhaupt eine setzt.
    /// - `undecidable` sind alle Kriterien, die erst am realen Fenster
    ///   messbar werden.
    public struct Report: Hashable, Sendable {
        public var decidable: [Criterion]
        public var undecidable: [Criterion]

        public init(decidable: [Criterion], undecidable: [Criterion]) {
            self.decidable = decidable
            self.undecidable = undecidable
        }

        /// `true`, wenn eine Auskunft „diese Regel greift" ohne Fenster nur eine
        /// Teilauskunft sein kann.
        public var requiresObservation: Bool { !undecidable.isEmpty }
    }

    /// Zerlegt eine `WindowMatch` in die beiden Listen.
    ///
    /// Der Filter aus `DefaultWindowFilter` (Ebene 0, `allowedSubroles`,
    /// `minimumWindowSize`) prüft ebenfalls Fensterdaten. Er ist nicht Teil des
    /// `WindowMatch` und wird deshalb nicht hier gemeldet — dafür gibt es
    /// ``report(for:defaults:)``.
    public static func report(for match: WindowMatch) -> Report {
        var decidable: [Criterion] = []
        var undecidable: [Criterion] = []

        if let bundleIdentifier = match.bundleIdentifier {
            decidable.append(.bundleIdentifier(bundleIdentifier))
        }
        if let titlePattern = match.titlePattern {
            undecidable.append(.title(pattern: titlePattern))
        }
        if let roles = match.roles {
            undecidable.append(.roles(roles))
        }
        if let subroles = match.subroles {
            undecidable.append(.subroles(subroles))
        }
        if let minimumSize = match.minimumSize {
            undecidable.append(.minimumSize(minimumSize))
        }
        if let maximumSize = match.maximumSize {
            undecidable.append(.maximumSize(maximumSize))
        }
        if let aspectRatio = match.aspectRatio {
            undecidable.append(.aspectRatio(aspectRatio))
        }
        if let onlyFirstWindowAfterLaunch = match.onlyFirstWindowAfterLaunch {
            undecidable.append(.onlyFirstWindowAfterLaunch(onlyFirstWindowAfterLaunch))
        }

        return Report(decidable: decidable, undecidable: undecidable)
    }

    /// Zerlegt eine `WindowMatch` samt globalen Voreinstellungen.
    ///
    /// Zusätzlich zu ``report(for:)`` schlägt die per Voreinstellung geerbte
    /// „nur das erste Fenster"-Regel unter ``Report/undecidable`` durch,
    /// solange die Regel selbst keinen expliziten Wert setzt und die
    /// Voreinstellung aktiv ist. Andere Filter des `DefaultWindowFilter`
    /// (Ebene, `allowedSubroles`, `minimumWindowSize`) sind ebenfalls
    /// beobachtungsabhängig, aber sie sind Systemfilter und keine
    /// regelspezifischen Kriterien — sie stehen nicht in der Zeile für *diese*
    /// Regel, weil sie für jede Regel gelten.
    public static func report(for match: WindowMatch, defaults: GlobalDefaults) -> Report {
        var report = self.report(for: match)
        if match.onlyFirstWindowAfterLaunch == nil, defaults.onlyFirstWindowAfterLaunch {
            report.undecidable.append(.onlyFirstWindowAfterLaunch(true))
        }
        return report
    }
}
