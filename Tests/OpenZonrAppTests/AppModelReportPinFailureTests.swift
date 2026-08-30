import Foundation
import Testing
@testable import OpenZonrApp
@testable import OpenZonrCore

/// `AppModel.reportPinFailure(_:)` ist die eine Stelle, an der der Ziehen-Weg
/// und der Rechtsklick-Weg ihre Ablehnungen abladen. Der Menüweg
/// (`apply(_:to:)`) und dieser gemeinsame Kanal müssen beides gleichzeitig
/// setzen: die Nachricht **und** die Flagge, an der die Menüzeile ihre Farbe
/// entscheidet. Ist nur eins gesetzt, sagt der Text „Fehler" und die Zeile
/// sieht aus wie ein Erfolg — der Bug-Muster aus PR #24 in genau der Form.
@Suite("AppModel — reportPinFailure")
@MainActor
struct AppModelReportPinFailureTests {

    @Test("Setzt Nachricht und Flagge zusammen")
    func setsBothFields() {
        let model = AppModelFixtures.modelWithoutConfiguration()

        model.reportPinFailure("Anheft-Marke ohne Wirkung: kein Ziel.")

        #expect(model.lastPinFailed == true)
        #expect(model.lastPinMessage == "Anheft-Marke ohne Wirkung: kein Ziel.")
    }

    @Test("Überschreibt eine frühere Erfolgsmeldung vollständig")
    func overwritesAnEarlierSuccessMessage() throws {
        let loaded = try AppModelFixtures.modelWithLoadedConfiguration()
        let model = loaded.model

        // Erst einen Erfolgspfad, damit `lastPinFailed == false` steht.
        let base = model.configuration!
        let ok = model.apply(
            QuickPin.Request(
                bundleIdentifier: "com.example.new",
                applicationName: "Neu",
                profile: "solo",
                target: QuickPin.Target(display: "main", zone: "left")
            ),
            to: base
        )
        #expect(ok == true)
        #expect(model.lastPinFailed == false)

        // Jetzt der Ablehnungspfad: beide Felder müssen umschlagen.
        model.reportPinFailure("Der Zug wurde abgebrochen: Modifier losgelassen.")

        #expect(model.lastPinFailed == true)
        #expect(model.lastPinMessage == "Der Zug wurde abgebrochen: Modifier losgelassen.")
    }
}
