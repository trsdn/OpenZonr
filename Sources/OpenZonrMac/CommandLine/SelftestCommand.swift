import AppKit
import Foundation

/// Reports what this process can actually see, and writes it where a caller can
/// read it.
///
/// It exists because the interesting case is not measurable from a shell. A
/// process started from a terminal inherits the terminal's Accessibility trust,
/// so `AXIsProcessTrusted()` answers `true` even when this bundle has no grant
/// of its own — while the window reads, which do not inherit, quietly return
/// placeholders. The honest measurement needs the program started the way it is
/// normally started: by LaunchServices, from the Finder or as a login item.
///
/// LaunchServices discards standard output, hence `--out`:
///
///     open -n -a ~/Applications/OpenZonr.app --args selftest --out /tmp/openzonr-selftest.txt
///
/// The same binary, launched the same way the menu bar app is, answering the
/// one question that decides whether anything else can work.
@MainActor
struct SelftestCommand {

    let outputPath: String?
    /// Ask macOS to show its Accessibility dialog when the grant is missing.
    ///
    /// Worth a flag of its own because the dialog is what puts the bundle into
    /// the list in the first place; without it a user has to find the app in the
    /// Finder and drag it there.
    let prompt: Bool

    func run() throws {
        var lines: [String] = []
        func emit(_ line: String = "") { lines.append(line) }

        emit("OpenZonr Selbsttest — \(Self.timestamp())")
        emit()

        let bundle = Bundle.main
        emit("Programm")
        emit("  Pfad:        \(bundle.bundlePath)")
        emit("  Identifier:  \(bundle.bundleIdentifier ?? "—")")
        emit("  Start:       \(Self.launchDescription())")
        emit()

        let signing = CodeSigningStatus.current()
        emit("Signatur")
        emit("  \(signing.summary)")
        emit()

        let trusted = Accessibility.isTrusted(promptIfNeeded: prompt)
        let access = Accessibility.probeWindowAccess()
        emit("Bedienungshilfen")
        emit("  AXIsProcessTrusted():   \(trusted)")
        emit("  probeWindowAccess():    \(Self.describe(access))")
        emit()
        emit(Self.verdict(trusted: trusted, access: access))

        let report = lines.joined(separator: "\n") + "\n"
        print(report, terminator: "")

        if let outputPath {
            let url = URL(fileURLWithPath: (outputPath as NSString).expandingTildeInPath)
            do {
                try report.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                throw CommandError("Konnte \(url.path) nicht schreiben: \(error.localizedDescription)")
            }
        }
    }

    private static func describe(_ access: Accessibility.WindowAccess) -> String {
        switch access {
        case .granted: return "granted — echte Fenster mit Subrolle und Größe"
        case .notTrusted: return "notTrusted — keine Freigabe für dieses Bundle"
        case .degraded: return "degraded — Vertrauen gemeldet, aber nur Stellvertreter"
        case .inconclusive: return "inconclusive — keine geeignete App zum Prüfen gefunden"
        }
    }

    /// Distinguishes the two launch paths, because they answer differently.
    ///
    /// A process launched by LaunchServices is reparented to `launchd` (PID 1)
    /// and has no controlling terminal. One started from a shell has both.
    private static func launchDescription() -> String {
        let parent = getppid()
        let viaLaunchServices = parent == 1
        let name = Self.processName(of: parent) ?? "PID \(parent)"
        return viaLaunchServices
            ? "über LaunchServices (Elternprozess launchd) — der maßgebliche Fall"
            : "aus einer Shell (Elternprozess \(name)) — erbt fremdes Vertrauen"
    }

    private static func processName(of pid: pid_t) -> String? {
        NSRunningApplication(processIdentifier: pid)?.localizedName
    }

    private static func verdict(trusted: Bool, access: Accessibility.WindowAccess) -> String {
        switch access {
        case .granted:
            return "Ergebnis: nutzbar. Fensterzugriff bestätigt."
        case .inconclusive:
            return """
            Ergebnis: unentschieden. Es lief keine App mit einem gewöhnlichen \
            Fenster, an der sich der Zugriff prüfen ließe. Eine sichtbare App \
            öffnen und erneut messen.
            """
        case .notTrusted:
            return """
            Ergebnis: nicht nutzbar — dieses Bundle ist nicht freigegeben.

            \(Accessibility.permissionInstructions)
            """
        case .degraded:
            return """
            Ergebnis: nicht nutzbar — Vertrauen gemeldet, Fenster aber nicht \
            lesbar.

            \(Accessibility.degradedAccessInstructions)
            """
        }
    }

    private static func timestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = .current
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime, .withSpaceBetweenDateAndTime]
        return formatter.string(from: Date())
    }
}
