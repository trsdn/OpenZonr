import Foundation
import Testing
@testable import OpenZonrApp
@testable import OpenZonrCore

/// „Zonen beim Ziehen“ schreibt die Aktivierungsregel genauso wie der frühere
/// Ein/Aus-Schalter den Schalter geschrieben hat (Issue #41): sofort wirksam,
/// sofort gesichert, ohne die Editor-Sitzung anzufassen.
///
/// Die Fälle sind dieselben wie in ``AppModelDropzoneToggleTests``, weil es
/// derselbe Schreibweg ist — und genau deshalb müssen sie hier noch einmal
/// stehen: der Weg ist jetzt für zwei Einstellungen zuständig, und die
/// Zusicherung gilt für beide oder für keine.
@Suite("AppModel — Zonen beim Ziehen sichern")
@MainActor
struct AppModelDropzoneTriggerTests {

    private func onDisk(_ loaded: LoadedModel) throws -> Configuration {
        guard case let .loaded(configuration, _, _) = ConfigurationStore().load(at: loaded.temp.url) else {
            throw NSError(domain: "test", code: 1)
        }
        return configuration
    }

    /// Ausgangslage: eingeschaltet, Zonen bei jedem Ziehen. Von dort ist jede
    /// der drei Wahlen eine echte Änderung.
    private func everyDragModel() throws -> LoadedModel {
        var configuration = AppModelFixtures.minimalConfiguration()
        configuration.defaults.dropzones.enabled = true
        configuration.defaults.dropzones.activation = .showsUnless(.none)
        return try AppModelFixtures.modelWithLoadedConfiguration(configuration)
    }

    @Test("Editor nie geöffnet: die Wahl wirkt und steht in der Datei")
    func editorNeverOpened() throws {
        let loaded = try everyDragModel()
        #expect(loaded.model.document == nil)
        #expect(loaded.model.dropzoneTrigger == .everyDrag)

        loaded.model.setDropzoneTrigger(.commandHeld)

        #expect(loaded.model.dropzoneTrigger == .commandHeld)
        #expect(try onDisk(loaded).defaults.dropzones.activation == .showsWhile(.command))
        #expect(loaded.model.document == nil)
    }

    @Test("Editor offen und sauber: die Wahl wirkt, der Editor bleibt sauber")
    func editorOpenClean() throws {
        let loaded = try everyDragModel()
        let document = try #require(loaded.model.editorDocument())

        loaded.model.setDropzoneTrigger(.commandHeld)

        #expect(loaded.model.dropzoneTrigger == .commandHeld)
        #expect(try onDisk(loaded).defaults.dropzones.activation == .showsWhile(.command))
        #expect(document.configuration.defaults.dropzones.activation == .showsWhile(.command))
        #expect(document.hasUnsavedChanges == false)
    }

    @Test("Editor offen und schmutzig: fremde Änderungen bleiben ungesichert erhalten")
    func editorOpenDirty() throws {
        let loaded = try everyDragModel()
        let document = try #require(loaded.model.editorDocument())
        document.apply { var c = $0; c.roles.append(ZoneRole(id: "extra", name: "Extra")); return c }
        #expect(document.hasUnsavedChanges)

        loaded.model.setDropzoneTrigger(.commandHeld)

        #expect(loaded.model.dropzoneTrigger == .commandHeld)
        let saved = try onDisk(loaded)
        #expect(saved.defaults.dropzones.activation == .showsWhile(.command))
        #expect(saved.roles.contains(where: { $0.id == "extra" }) == false)
        #expect(document.configuration.roles.contains(where: { $0.id == "extra" }))
        #expect(document.configuration.defaults.dropzones.activation == .showsWhile(.command))
        #expect(document.hasUnsavedChanges)
    }

    @Test("„Aus“ und zurück gehen durch denselben Weg")
    func offAndBack() throws {
        let loaded = try everyDragModel()

        loaded.model.setDropzoneTrigger(.off)
        #expect(loaded.model.dropzoneTrigger == .off)
        #expect(try onDisk(loaded).defaults.dropzones.enabled == false)

        loaded.model.setDropzoneTrigger(.commandHeld)
        #expect(loaded.model.dropzoneTrigger == .commandHeld)
        let saved = try onDisk(loaded)
        #expect(saved.defaults.dropzones.enabled)
        #expect(saved.defaults.dropzones.activation == .showsWhile(.command))
    }

    @Test("Schreibfehler: das Menü zeigt weiter den wirksamen Zustand, der Fehler ist sichtbar")
    func persistenceFailureIsSurfaced() throws {
        let loaded = try everyDragModel()
        let document = try #require(loaded.model.editorDocument())
        // Verzeichnis schreibgeschützt: das atomare Schreiben schlägt fehl.
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o555], ofItemAtPath: loaded.temp.directory.path
        )
        defer {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: loaded.temp.directory.path
            )
        }

        loaded.model.setDropzoneTrigger(.commandHeld)

        #expect(loaded.model.dropzoneTrigger == .everyDrag)
        #expect(loaded.model.lastPinFailed == true)
        #expect(loaded.model.lastPinMessage?.isEmpty == false)
        #expect(document.configuration.defaults.dropzones.activation == .showsUnless(.none))
        #expect(document.hasUnsavedChanges == false)
    }

    @Test("Eine Wahl, die nichts ändert, schreibt auch nichts")
    func noopDoesNotWrite() throws {
        let loaded = try everyDragModel()
        let before = try Data(contentsOf: loaded.temp.url)

        loaded.model.setDropzoneTrigger(.everyDrag)

        #expect(try Data(contentsOf: loaded.temp.url) == before)
        #expect(loaded.model.lastPinFailed == false)
    }

    @Test("Das Ergebnis des letzten Zugs steht im Modell und wird zu einem Satz")
    func lastDragOutcomeIsRecorded() throws {
        let loaded = try everyDragModel()
        #expect(loaded.model.lastDragOutcome == nil)

        loaded.model.recordDragOutcome(.zonesHidden(.awaitingModifier(.command)))

        #expect(loaded.model.lastDragOutcome == .zonesHidden(.awaitingModifier(.command)))
        #expect(
            DragOutcomeWording.sentence(for: loaded.model.lastDragOutcome)
                == "Letzter Zug: keine Zonen — ⌘ war nicht gedrückt."
        )
    }
}
