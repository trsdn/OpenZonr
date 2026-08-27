import Foundation
import OpenZonrCore

/// Entry point and hand-written argument parsing.
///
/// Three subcommands with a handful of flags do not justify a dependency, and a
/// package without external dependencies stays trivial to build, audit and
/// vendor. If the surface grows past this, swift-argument-parser is the obvious
/// replacement.
@main
struct OpenZonrCLI {

    static let usage = """
    openzonr — Fenster landen dort, wo sie hingehören.

    AUFRUF
      openzonr displays [--config-fragment]
      openzonr windows  [--bundle <bundle-id>] [--all-apps] [--no-filter-verdict]
      openzonr watch    [--config <pfad>] [--dry-run]

    UNTERBEFEHLE
      displays   Zeigt alle angeschlossenen Bildschirme mit ihrer stabilen
                 Identität und dem daraus berechneten Setup-Fingerprint.
                 --config-fragment gibt ein fertiges "displays"-Fragment aus,
                 das direkt in die Konfiguration übernommen werden kann.

      windows    Listet die Fenster laufender Apps mit genau den Merkmalen, die
                 die Regelauswertung liest: Bundle ID, Titel, Rolle, Subrole,
                 Fensterebene, Frame und Zieldisplay.
                 --bundle beschränkt auf eine App, --all-apps nimmt Hintergrund-
                 und Menüleisten-Apps dazu.

      watch      Der Durchstich: beobachtet neu geöffnete Fenster und platziert
                 sie gemäß Konfiguration. Läuft im Vordergrund und protokolliert
                 jeden Schritt. --dry-run entscheidet, ohne Fenster zu bewegen.

    KONFIGURATION
      Standardpfad: ~/Library/Application Support/OpenZonr/config.json
      Überschreibbar mit --config <pfad> oder der Umgebungsvariablen
      OPENZONR_CONFIG. Eine Vorlage liegt unter Examples/openzonr.config.json;
      deren Bildschirmkennungen sind erfunden. Die echten liefert
      "openzonr displays --config-fragment".

    BERECHTIGUNG
      "watch" benötigt den Zugriff auf die Bedienungshilfen
      (Systemeinstellungen → Datenschutz & Sicherheit → Bedienungshilfen).
    """

    static func main() {
        var arguments = Array(CommandLine.arguments.dropFirst())

        guard let subcommand = arguments.first else {
            print(usage)
            exit(2)
        }
        arguments.removeFirst()

        do {
            switch subcommand {
            case "displays":
                let command = DisplaysCommand(
                    emitFragment: arguments.consumeFlag("--config-fragment")
                )
                try arguments.requireEmpty()
                try MainActor.assumeIsolated { try command.run() }

            case "windows":
                let command = WindowsCommand(
                    bundleIdentifier: try arguments.consumeOption("--bundle"),
                    includeAccessoryApps: arguments.consumeFlag("--all-apps"),
                    showFilterVerdict: !arguments.consumeFlag("--no-filter-verdict")
                )
                try arguments.requireEmpty()
                try MainActor.assumeIsolated { try command.run() }

            case "watch":
                let path = try arguments.consumeOption("--config")
                let command = WatchCommand(
                    configurationURL: ConfigurationLocation.resolve(explicitPath: path),
                    dryRun: arguments.consumeFlag("--dry-run")
                )
                try arguments.requireEmpty()
                try MainActor.assumeIsolated { try command.run() }

            case "--help", "-h", "help":
                print(usage)
                exit(0)

            default:
                throw CommandError("Unbekannter Unterbefehl \"\(subcommand)\".\n\n\(usage)")
            }
        } catch let error as CommandError {
            FileHandle.standardError.write(Data((error.description + "\n").utf8))
            exit(1)
        } catch let error as ConfigurationStoreError {
            FileHandle.standardError.write(Data((error.description + "\n").utf8))
            exit(1)
        } catch {
            FileHandle.standardError.write(Data(("Fehler: \(error)\n").utf8))
            exit(1)
        }
    }
}

extension Array where Element == String {
    /// Removes `flag` if present and reports whether it was.
    mutating func consumeFlag(_ flag: String) -> Bool {
        guard let index = firstIndex(of: flag) else { return false }
        remove(at: index)
        return true
    }

    /// Removes `option` and its value, supporting both `--x y` and `--x=y`.
    mutating func consumeOption(_ option: String) throws -> String? {
        if let index = firstIndex(of: option) {
            guard index + 1 < count else {
                throw CommandError("\(option) erwartet einen Wert.")
            }
            let value = self[index + 1]
            removeSubrange(index...(index + 1))
            return value
        }
        if let index = firstIndex(where: { $0.hasPrefix(option + "=") }) {
            let value = String(self[index].dropFirst(option.count + 1))
            remove(at: index)
            guard !value.isEmpty else { throw CommandError("\(option) erwartet einen Wert.") }
            return value
        }
        return nil
    }

    /// Rejects leftovers instead of ignoring them — a mistyped flag that is
    /// silently dropped is worse than an error.
    func requireEmpty() throws {
        guard isEmpty else {
            throw CommandError("Unbekannte Argumente: \(joined(separator: " "))")
        }
    }
}
