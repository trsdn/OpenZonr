import Foundation
import Testing
@testable import OpenZonrApp
@testable import OpenZonrCore

/// Der Menüweg „Aktuelles Fenster hier festhalten" hat zwei Vor-Guards, die
/// ohne echte Fenster prüfbar sind: keine Konfiguration und kein aktives
/// Profil. Beide Sätze sind auch in ``DropzoneController.pin`` und
/// ``ZoomButtonMenu.presentMenu`` in Verwendung — dieselbe Lage muss dort
/// denselben Satz erzeugen. Nach PR #24 stehen die zwei Sätze in
/// ``AppModel.GuardSentence``, damit ein Umschreiben an einer Stelle nicht
/// an einer anderen die Stimme abbricht.
@Suite("AppModel — pinFrontmostWindow Guards")
@MainActor
struct AppModelPinFrontmostGuardsTests {

    @Test("Ohne Konfiguration: gemeinsamer Satz, Fehlerflagge steht")
    func withoutConfiguration() {
        let model = AppModelFixtures.modelWithoutConfiguration()

        model.pinFrontmostWindow()

        #expect(model.lastPinFailed == true)
        #expect(model.lastPinMessage == AppModel.GuardSentence.noConfigurationLoaded)
    }

    @Test("Ohne aktives Profil: gemeinsamer Satz, Fehlerflagge steht")
    func withoutActiveProfile() throws {
        let loaded = try AppModelFixtures.modelWithoutProfile()

        loaded.model.pinFrontmostWindow()

        #expect(loaded.model.lastPinFailed == true)
        #expect(loaded.model.lastPinMessage == AppModel.GuardSentence.noActiveProfile)
    }

    /// Die zwei Sätze müssen sich vom Wortlaut her unterscheiden — sonst wäre
    /// die Trennung zwischen „keine Konfiguration" und „kein Profil" nur im
    /// Bezeichner sichtbar, nicht in der Meldung, die der Nutzer liest.
    @Test("Die beiden Guard-Sätze sagen jeweils Verschiedenes")
    func guardSentencesAreDistinct() {
        #expect(AppModel.GuardSentence.noConfigurationLoaded
                != AppModel.GuardSentence.noActiveProfile)
        #expect(AppModel.GuardSentence.noConfigurationLoaded.isEmpty == false)
        #expect(AppModel.GuardSentence.noActiveProfile.isEmpty == false)
    }
}
