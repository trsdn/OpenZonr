import Foundation

/// Wo im Update-Ablauf die App gerade steht.
///
/// Eigener Typ und nicht `AppUpdater`s eigener Zustand: was die Menüleiste
/// anzeigt, ist eine Entscheidung dieser App, und sie soll ohne Netz, ohne
/// Bundle und ohne `AppUpdater` prüfbar sein.
enum UpdateState: Equatable {
    /// Nichts läuft, nichts liegt bereit.
    case idle
    /// Eine Suche, die der Nutzer angestossen hat, läuft.
    case checking
    /// Die letzte ausdrückliche Suche fand nichts Neueres.
    case upToDate
    /// Ein gefundenes Update wird geladen und geprüft.
    case downloading(version: String)
    /// Geladen und geprüft — ein Klick genügt.
    case readyToInstall(version: String)
    /// Der Bundle-Tausch läuft. Danach startet die App neu.
    case installing
    /// Suche oder Installation ist gescheitert.
    case failed(String)
}

/// Die reinen Entscheidungen rund um Updates: wann fällig, was voreingestellt,
/// was im Menü steht.
///
/// Getrennt von ``UpdateManager``, weil dort alles am Netz und an einem echten
/// Bundle hängt. Hier hängt nichts daran, und genau das ist geprüft (siehe
/// `Tests/OpenZonrAppTests/UpdatePolicyTests.swift`).
enum UpdatePolicy {

    /// Gesucht wird höchstens einmal am Tag.
    static let checkInterval: TimeInterval = 24 * 60 * 60

    /// Nachgesehen wird stündlich, ob die Tagesfrist abgelaufen ist.
    ///
    /// Ein schlichter 24-Stunden-Wecker würde auf einem Mac, der nachts
    /// schläft, beliebig lange nie klingeln: der Timer läuft im Schlaf nicht
    /// weiter, und der nächste Termin verschiebt sich mit jedem Ruhezustand.
    /// Stündlich aufwachen und die Uhr lesen tut das nicht.
    static let wakeInterval: TimeInterval = 60 * 60

    /// Der Voreinstellungsschlüssel des automatischen Suchens.
    static let automaticChecksKey = "checkForUpdatesAutomatically"

    /// Ob eine automatische Suche fällig ist.
    ///
    /// Ohne vorherige Suche ist sie es sofort — sonst würde eine frisch
    /// gestartete App bis zum nächsten Tag nichts von einem Update erfahren.
    static func isCheckDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= checkInterval
    }

    /// Der Anfangswert des Schalters „Automatisch nach Updates suchen“.
    ///
    /// Voreingestellt an. `UserDefaults.bool(forKey:)` würde das nicht
    /// hergeben: es liefert `false`, wenn der Schlüssel fehlt, und kann damit
    /// „nie eingestellt“ nicht von „ausgeschaltet“ unterscheiden. Deshalb geht
    /// der Weg über `object(forKey:)`.
    static func automaticChecksEnabled(stored: Any?) -> Bool {
        (stored as? Bool) ?? true
    }

    /// Ob gerade etwas läuft, das eine zweite Suche stören würde.
    static func isBusy(_ state: UpdateState) -> Bool {
        switch state {
        case .checking, .downloading, .installing: return true
        case .idle, .upToDate, .readyToInstall, .failed: return false
        }
    }

    /// Die Zeile, die im Menü über den Update-Einträgen steht — oder `nil`,
    /// wenn es nichts zu sagen gibt.
    ///
    /// `.idle` sagt nichts: eine Zeile „nichts los“ wäre Rauschen in einem
    /// Menü, das ohnehin lang ist.
    static func statusLine(for state: UpdateState) -> String? {
        switch state {
        case .idle:
            return nil
        case .checking:
            return "Suche nach Updates …"
        case .upToDate:
            return "OpenZonr ist aktuell"
        case let .downloading(version):
            return "Update \(version) wird geladen …"
        case let .readyToInstall(version):
            return "Update \(version) liegt bereit"
        case .installing:
            return "Update wird installiert …"
        case let .failed(message):
            return "Update fehlgeschlagen: \(message)"
        }
    }

    /// Die Aufschrift des Installieren-Knopfs — oder `nil`, solange nichts
    /// bereitliegt und der Knopf deshalb gar nicht erst erscheint.
    static func installTitle(for state: UpdateState) -> String? {
        guard case let .readyToInstall(version) = state else { return nil }
        return "Installieren und neu starten (\(version))"
    }
}
