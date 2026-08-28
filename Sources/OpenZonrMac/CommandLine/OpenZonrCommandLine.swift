import Foundation
import OpenZonrCore

/// The command line surface, and hand-written argument parsing.
///
/// Three subcommands with a handful of flags do not justify a dependency, and a
/// package without external dependencies stays trivial to build, audit and
/// vendor. If the surface grows past this, swift-argument-parser is the obvious
/// replacement.
///
/// It lives in the shared library rather than in the `openzonr` target for one
/// concrete reason. The Accessibility grant is bound to a bundle at a path, and
/// the two front ends have to share it: the menu bar app dispatches to exactly
/// this code when it is invoked with a subcommand, so
/// `OpenZonr.app/Contents/MacOS/OpenZonr windows` is the *same signed binary*
/// the user granted, not a second one that would need its own approval.
public enum OpenZonrCommandLine {

    public static let usage = """
    openzonr — Fenster landen dort, wo sie hingehören.

    AUFRUF
      openzonr displays [--config-fragment]
      openzonr windows  [--bundle <bundle-id>] [--all-apps] [--no-filter-verdict]
      openzonr watch    [--config <pfad>] [--dry-run]
      openzonr selftest [--out <pfad>] [--prompt]
      openzonr dragprobe [--seconds <n>] [--out <pfad>] [--synthesize]

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

      selftest   Meldet, ob dieses Programm Fenster sehen kann — Signatur,
                 Startweg und tatsächlicher Fensterzugriff. --out schreibt den
                 Bericht zusätzlich in eine Datei; das ist der einzige Weg, den
                 über LaunchServices gestarteten Fall zu messen, dessen Ausgabe
                 sonst verlorengeht:
                   open -n -a OpenZonr --args selftest --out /tmp/openzonr.txt

      dragprobe  Misst beide Wege, eine Fensterbewegung zu erkennen —
                 CGEventTap und kAXMovedNotification — nebeneinander:
                 Einrichtung, Ereignisrate, Latenz, größte Lücke und ob das
                 Loslassen ein Ereignis ist oder abgefragt werden muss.
                 --seconds legt die Messdauer je Weg fest (Vorgabe 5),
                 --synthesize erzeugt die Mausereignisse selbst, damit auch
                 ohne Hand an der Maus Zahlen entstehen — sie werden im
                 Bericht als synthetisch ausgewiesen.

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

    /// Subcommands this tool answers to.
    ///
    /// Used by the app to decide whether it was started as a tool or as an app,
    /// which is why it is a list rather than "anything that is not a flag":
    /// LaunchServices passes arguments of its own, and mistaking one of them for
    /// a subcommand would keep the menu bar icon from ever appearing.
    public static let subcommands = ["displays", "windows", "watch", "selftest", "dragprobe", "help", "--help", "-h"]

    public static func isSubcommand(_ argument: String) -> Bool {
        subcommands.contains(argument)
    }

    public static func run(_ argumentList: [String]) -> Never {
        var arguments = argumentList

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

            case "selftest":
                let command = SelftestCommand(
                    outputPath: try arguments.consumeOption("--out"),
                    prompt: arguments.consumeFlag("--prompt")
                )
                try arguments.requireEmpty()
                try MainActor.assumeIsolated { try command.run() }

            case "dragprobe":
                let secondsArgument = try arguments.consumeOption("--seconds")
                let seconds = secondsArgument.flatMap(Double.init) ?? 5
                guard seconds > 0 else { throw CommandError("--seconds erwartet eine positive Zahl.") }
                let command = DragProbeCommand(
                    seconds: seconds,
                    outputPath: try arguments.consumeOption("--out"),
                    synthesize: arguments.consumeFlag("--synthesize")
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
        exit(0)
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
