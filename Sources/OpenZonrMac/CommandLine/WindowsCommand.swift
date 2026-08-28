import AppKit
import Foundation
import OpenZonrCore

/// `openzonr windows` — the command that turns observed windows into match
/// criteria.
///
/// Writing a rule means guessing which attributes distinguish the window you
/// want from the ones you do not. This subcommand removes the guessing: it
/// prints exactly the attributes the rule engine reads, in the same terms.
struct WindowsCommand {

    var bundleIdentifier: String?
    var includeAccessoryApps: Bool
    var showFilterVerdict: Bool

    @MainActor
    func run() throws {
        // Diagnostics must not pop the system dialog, but staying silent about
        // a missing permission would make an empty listing look like an empty
        // desktop.
        switch Accessibility.probeWindowAccess() {
        case .notTrusted:
            print("⚠️  Kein Zugriff auf die Bedienungshilfen — die Liste bleibt leer.\n")
            print(Accessibility.permissionInstructions)
            print("")
        case .degraded:
            print("⚠️  Zugriff degradiert — die Liste bleibt unvollständig.\n")
            print(Accessibility.degradedAccessInstructions)
            print("")
        case .granted, .inconclusive:
            break
        }

        let items = WindowInventory.allWindows(
            bundleIdentifier: bundleIdentifier,
            includeAccessoryApps: includeAccessoryApps
        )

        guard !items.isEmpty else {
            if let bundleIdentifier {
                throw CommandError("Keine Fenster für \(bundleIdentifier) gefunden — läuft die App?")
            }
            throw CommandError("Keine Fenster gefunden. Fehlt der Zugriff auf die Bedienungshilfen?")
        }

        let arrangement = ScreenArrangement(snapshots: SystemDisplays.snapshots())
        let filter = DefaultWindowFilter()
        let defaults = GlobalDefaults()

        var currentBundle: String?
        for item in items {
            let snapshot = item.snapshot
            let bundle = snapshot.bundleIdentifier ?? "(ohne Bundle ID)"
            if bundle != currentBundle {
                currentBundle = bundle
                let name = item.application.localizedName ?? bundle
                print("\n\(name)  —  \(bundle)  (pid \(snapshot.processIdentifier))")
            }

            let display = arrangement.display(containingAccessibilityFrame: snapshot.frame)
            print("    Titel      \(quoted(snapshot.title))")
            print("    Rolle      \(snapshot.role ?? "—") / \(snapshot.subrole ?? "—")   Ebene \(snapshot.windowLayer)")
            print("    Frame      \(snapshot.frame.shortDescription)   (AX, Ursprung oben links)")
            print("    Display    \(display?.localizedName ?? "unbekannt")")

            if showFilterVerdict {
                switch filter.evaluate(snapshot, defaults: defaults) {
                case .accepted:
                    print("    Filter     Kandidat für Platzierung")
                case let .rejected(reason):
                    print("    Filter     abgelehnt: \(reason)")
                }
            }
        }

        print("""

        Hinweise zum Ableiten von Regeln:
          • Ebene 0 sind echte App-Fenster. Alles darüber ist Systemoberfläche
            (Dock 20, Mitteilungszentrale 21, Menüleiste 24, Kontrollzentrum 25)
            und wird von OpenZonr grundsätzlich ignoriert.
          • Fenstertitel sind bei Outlook, Edge und Safari zustandsabhängig und
            damit als alleiniges Kriterium unbrauchbar. Bevorzuge Bundle ID,
            Subrole, Mindestgröße und onlyFirstWindowAfterLaunch.
          • Mehrere deckungsgleiche Fenster derselben App mit leerem Titel sind
            normal — genau dagegen hilft onlyFirstWindowAfterLaunch.
        """)
    }

    private func quoted(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "(leer)" }
        return "\"\(value)\""
    }
}
