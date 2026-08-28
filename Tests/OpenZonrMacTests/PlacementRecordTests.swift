import Foundation
import OpenZonrCore
import Testing
@testable import OpenZonrMac

/// A placement record is what the menu shows instead of the log stream. The log
/// explains at length; a menu row has one line, and these tests hold that line
/// to being both short and honest.
struct PlacementRecordTests {

    private func record(outcome: PlacementRecord.Outcome,
                        display: DisplayAlias? = "c49rg9x",
                        zone: ZoneID? = "right-quarter") -> PlacementRecord {
        PlacementRecord(
            applicationName: "TextEdit",
            bundleIdentifier: "com.apple.TextEdit",
            windowTitle: "Unbenannt",
            ruleID: "textedit",
            display: display,
            zone: zone,
            outcome: outcome
        )
    }

    @Test("Das Ziel wird als display/zone geschrieben")
    func targetIsComposed() {
        #expect(record(outcome: .suggested).target == "c49rg9x/right-quarter")
    }

    @Test("Ohne Ziel gibt es keinen Zielstring")
    func targetIsAbsentWithoutZone() {
        #expect(record(outcome: .skipped("kein Treffer"), zone: nil).target == nil)
    }

    @Test("Der Singular wird nicht gepluralisiert")
    func singleAttemptReadsAsSingular() {
        let summary = record(outcome: .placed(attempts: 1, deviation: 0)).summary
        #expect(summary.contains("1 Versuch"))
        #expect(!summary.contains("Versuchen"))
    }

    @Test("Die gemessene Abweichung steht in der Zusammenfassung")
    func deviationIsReported() {
        #expect(record(outcome: .placed(attempts: 2, deviation: 1.0)).summary.contains("1 pt"))
    }

    @Test("Nur eine tatsächliche Platzierung gilt als Erfolg")
    func onlyPlacementCounts() {
        #expect(record(outcome: .placed(attempts: 1, deviation: nil)).isSuccess)
        #expect(!record(outcome: .suggested).isSuccess)
        #expect(!record(outcome: .notExecuted("Testlauf")).isSuccess)
    }

    /// A refusal by the application is the one outcome that deserves attention:
    /// everything else either worked or was a deliberate decision not to act.
    @Test("Nur die Ablehnung durch die App gilt als Fehlschlag")
    func onlyRejectionIsFailure() {
        let frame = WindowFrame(x: 0, y: 0, width: 100, height: 100)
        #expect(record(outcome: .rejected(actual: frame, attempts: 3)).isFailure)
        #expect(!record(outcome: .skipped("Zone belegt")).isFailure)
        #expect(!record(outcome: .placed(attempts: 1, deviation: nil)).isFailure)
    }
}

/// The app and the command line are the same binary, so the argument list is
/// what decides which of the two starts. LaunchServices adds arguments of its
/// own (`-psn_…` historically, `-NSDocumentRevisionsDebugMode` under a debugger),
/// and mistaking one for a subcommand would mean the menu bar icon never
/// appears — a failure with no error message. Hence an explicit list.
struct SubcommandDetectionTests {

    @Test("Jeder dokumentierte Unterbefehl wird erkannt", arguments: ["displays", "windows", "watch", "selftest", "help", "--help", "-h"])
    func recognisesSubcommands(_ argument: String) {
        #expect(OpenZonrCommandLine.isSubcommand(argument))
    }

    @Test("Fremde Argumente starten die App", arguments: [
        "-psn_0_12345",
        "-NSDocumentRevisionsDebugMode",
        "YES",
        "--out",
        "/Users/jemand/Datei.txt",
        ""
    ])
    func ignoresForeignArguments(_ argument: String) {
        #expect(!OpenZonrCommandLine.isSubcommand(argument))
    }
}
