import Foundation
import Testing
@testable import OpenZonrApp
@testable import OpenZonrCore

/// Der Menü-Schalter „Fenster in Zonen ziehen“ muss unabhängig davon wirken,
/// ob der Editor je geöffnet wurde (Issue #41).
@Suite("AppModel — Ziehen-Schalter im Menü")
@MainActor
struct AppModelDropzoneToggleTests {

    private func onDisk(_ loaded: LoadedModel) throws -> Configuration {
        guard case let .loaded(configuration, _, _) = ConfigurationStore().load(at: loaded.temp.url) else {
            throw NSError(domain: "test", code: 1)
        }
        return configuration
    }

    private func enabledModel() throws -> LoadedModel {
        var configuration = AppModelFixtures.minimalConfiguration()
        configuration.defaults.dropzones.enabled = true
        return try AppModelFixtures.modelWithLoadedConfiguration(configuration)
    }

    @Test("Editor nie geöffnet: Schalter wirkt und steht in der Datei")
    func editorNeverOpened() throws {
        let loaded = try enabledModel()
        #expect(loaded.model.document == nil)

        loaded.model.dropzonesEnabled = false

        #expect(loaded.model.dropzonesEnabled == false)
        #expect(try onDisk(loaded).defaults.dropzones.enabled == false)
        #expect(loaded.model.document == nil)
    }

    @Test("Editor offen und sauber: Schalter wirkt, Editor bleibt sauber")
    func editorOpenClean() throws {
        let loaded = try enabledModel()
        let document = try #require(loaded.model.editorDocument())

        loaded.model.dropzonesEnabled = false

        #expect(loaded.model.dropzonesEnabled == false)
        #expect(try onDisk(loaded).defaults.dropzones.enabled == false)
        #expect(document.configuration.defaults.dropzones.enabled == false)
        #expect(document.hasUnsavedChanges == false)
    }

    @Test("Editor offen und schmutzig: fremde Änderungen bleiben ungesichert erhalten")
    func editorOpenDirty() throws {
        let loaded = try enabledModel()
        let document = try #require(loaded.model.editorDocument())
        document.apply { var c = $0; c.roles.append(ZoneRole(id: "extra", name: "Extra")); return c }
        #expect(document.hasUnsavedChanges)

        loaded.model.dropzonesEnabled = false

        #expect(loaded.model.dropzonesEnabled == false)
        let saved = try onDisk(loaded)
        #expect(saved.defaults.dropzones.enabled == false)
        // Die ungesicherte Rolle steht weder in der Datei noch ist sie verloren.
        #expect(saved.roles.contains(where: { $0.id == "extra" }) == false)
        #expect(document.configuration.roles.contains(where: { $0.id == "extra" }))
        #expect(document.configuration.defaults.dropzones.enabled == false)
        #expect(document.hasUnsavedChanges)
    }

    @Test("Geschlossen, aber zwischengespeichert: gleich wie offen")
    func closedButCached() throws {
        let loaded = try enabledModel()
        _ = loaded.model.editorDocument()  // „Fenster zu“ ändert am Modell nichts

        loaded.model.dropzonesEnabled = false
        loaded.model.dropzonesEnabled = true

        #expect(loaded.model.dropzonesEnabled == true)
        #expect(try onDisk(loaded).defaults.dropzones.enabled == true)
        #expect(loaded.model.document?.configuration.defaults.dropzones.enabled == true)
        #expect(loaded.model.document?.hasUnsavedChanges == false)
    }

    @Test("Schreibfehler: Schalter zeigt weiter den wirksamen Zustand, Fehler sichtbar, Editor unverändert")
    func persistenceFailureIsSurfaced() throws {
        let loaded = try enabledModel()
        let document = try #require(loaded.model.editorDocument())
        // Verzeichnis schreibgeschützt: das atomare Schreiben schlägt fehl.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: loaded.temp.directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: loaded.temp.directory.path) }

        loaded.model.dropzonesEnabled = false

        #expect(loaded.model.dropzonesEnabled == true)
        #expect(loaded.model.lastPinFailed == true)
        #expect(loaded.model.lastPinMessage?.isEmpty == false)
        #expect(document.configuration.defaults.dropzones.enabled == true)
        #expect(document.hasUnsavedChanges == false)
    }
}
