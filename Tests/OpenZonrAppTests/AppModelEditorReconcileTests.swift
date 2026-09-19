import Foundation
import Testing
@testable import OpenZonrApp
@testable import OpenZonrCore

/// Reload, Wiederöffnen und Sichern dürfen eine außerhalb geänderte
/// Konfiguration nie mit einem alten Editorstand überschreiben (Issue #42).
@Suite("AppModel — Editor-Sitzung und Fremdänderungen")
@MainActor
struct AppModelEditorReconcileTests {

    private func externalEdit(_ loaded: LoadedModel) throws -> Configuration {
        var external = AppModelFixtures.minimalConfiguration()
        external.roles.append(ZoneRole(id: "extra", name: "Extra"))
        try ConfigurationStore().save(external, to: loaded.temp.url)
        return external
    }

    private func diskRoles(_ loaded: LoadedModel) throws -> [String] {
        guard case let .loaded(c, _, _) = ConfigurationStore().load(at: loaded.temp.url) else { throw NSError(domain: "test", code: 1) }
        return c.roles.map(\.id.rawValue)
    }

    @Test("Mit Reload, sauberer Editor: Sitzung zeigt den neuen Dateistand")
    func reloadRefreshesCleanSession() throws {
        let loaded = try AppModelFixtures.modelWithLoadedConfiguration()
        let document = try #require(loaded.model.editorDocument())
        let external = try externalEdit(loaded)

        loaded.model.reloadConfiguration()

        #expect(document.configuration == external)
        #expect(document.hasUnsavedChanges == false)
        #expect(loaded.model.configuration == external)
    }

    @Test("Mit Reload, schmutziger Editor: Änderungen bleiben, Sichern gesperrt, Überschreiben möglich")
    func reloadKeepsDirtySessionAndBlocksSave() throws {
        let loaded = try AppModelFixtures.modelWithLoadedConfiguration()
        let document = try #require(loaded.model.editorDocument())
        document.apply { var c = $0; c.defaults.dropzones.enabled = true; return c }
        _ = try externalEdit(loaded)

        loaded.model.reloadConfiguration()

        #expect(document.configuration.defaults.dropzones.enabled == true)
        #expect(document.hasExternalChange)
        #expect(document.save() == false)
        #expect(try diskRoles(loaded).contains("extra"))

        #expect(document.save(overwritingExternalChanges: true))
        #expect(try diskRoles(loaded).contains("extra") == false)
    }

    @Test("Ohne Reload: Sichern eines veralteten Editors wird verweigert und Laufzeit zieht nach")
    func staleSaveWithoutReloadIsRefused() throws {
        let loaded = try AppModelFixtures.modelWithLoadedConfiguration()
        let document = try #require(loaded.model.editorDocument())
        document.apply { var c = $0; c.defaults.dropzones.enabled = true; return c }
        _ = try externalEdit(loaded)   // kein reloadConfiguration()

        #expect(document.save() == false)

        #expect(try diskRoles(loaded).contains("extra"))
        #expect(document.saveProblem?.contains("außerhalb") == true)
        // onExternalChange hat die Laufzeit auf den Dateistand gebracht.
        #expect(loaded.model.configuration?.roles.contains(where: { $0.id == "extra" }) == true)
    }

    @Test("Wiederöffnen: zwischengespeicherter Editor liefert nie den alten Stand")
    func reopeningCachedEditorCannotResurrectStaleConfiguration() throws {
        let loaded = try AppModelFixtures.modelWithLoadedConfiguration()
        _ = loaded.model.editorDocument()          // Fenster „geschlossen“: Sitzung bleibt
        let external = try externalEdit(loaded)    // ohne Reload

        let reopened = try #require(loaded.model.editorDocument())

        #expect(reopened.configuration == external)
        #expect(reopened.hasUnsavedChanges == false)
        #expect(try diskRoles(loaded).contains("extra"))
    }

    @Test("Datei nicht mehr ladbar: sauberer Editor wird verworfen, kein Altstand")
    func unloadableFileDropsCleanSession() throws {
        let loaded = try AppModelFixtures.modelWithLoadedConfiguration()
        _ = loaded.model.editorDocument()
        try Data("{ kaputt".utf8).write(to: loaded.temp.url)

        loaded.model.reloadConfiguration()

        #expect(loaded.model.configuration == nil)
        #expect(loaded.model.document == nil)
        #expect(loaded.model.editorDocument() == nil)
    }

    @Test("Menü-Schalter bei geänderter Datei ohne Reload: verweigert und sichtbar")
    func toggleRefusesToOverwriteExternalChange() throws {
        var configuration = AppModelFixtures.minimalConfiguration()
        configuration.defaults.dropzones.enabled = true
        let loaded = try AppModelFixtures.modelWithLoadedConfiguration(configuration)
        _ = try externalEdit(loaded)

        loaded.model.dropzonesEnabled = false

        #expect(loaded.model.lastPinFailed == true)
        #expect(loaded.model.lastPinMessage?.contains("außerhalb") == true)
        #expect(try diskRoles(loaded).contains("extra"))
    }

    @Test("Menü-Schalter mit schmutzigem Editor erzeugt keinen Scheinkonflikt")
    func toggleWithDirtyEditorCausesNoConflict() throws {
        var configuration = AppModelFixtures.minimalConfiguration()
        configuration.defaults.dropzones.enabled = true
        let loaded = try AppModelFixtures.modelWithLoadedConfiguration(configuration)
        let document = try #require(loaded.model.editorDocument())
        document.apply { var c = $0; c.roles.append(ZoneRole(id: "mine", name: "Mine")); return c }

        loaded.model.dropzonesEnabled = false

        #expect(document.hasExternalChange == false)
        #expect(document.hasUnsavedChanges)
        #expect(document.save())
        #expect(try diskRoles(loaded).contains("mine"))
    }

    @Test("Abgelehnter Menü-Schalter: Fremdänderung am Schalter selbst bleibt in Editor, Laufzeit und Datei gleich")
    func refusedToggleKeepsExternalFlagEverywhere() throws {
        var configuration = AppModelFixtures.minimalConfiguration()
        configuration.defaults.dropzones.enabled = true
        let loaded = try AppModelFixtures.modelWithLoadedConfiguration(configuration)
        let document = try #require(loaded.model.editorDocument())
        var external = AppModelFixtures.minimalConfiguration()
        external.defaults.dropzones.enabled = false
        external.roles.append(ZoneRole(id: "extra", name: "Extra"))
        try ConfigurationStore().save(external, to: loaded.temp.url)

        loaded.model.dropzonesEnabled = false

        #expect(loaded.model.lastPinFailed == true)
        #expect(document.configuration.defaults.dropzones.enabled == false)
        #expect(document.configuration == external)
        #expect(document.hasUnsavedChanges == false)
        #expect(loaded.model.configuration == external)
        #expect(try diskRoles(loaded).contains("extra"))
    }

    @Test("Erste Öffnung nach Fremdänderung ohne Reload: Sitzung baut auf dem Dateistand auf")
    func firstOpenAfterExternalEditUsesDisk() throws {
        let loaded = try AppModelFixtures.modelWithLoadedConfiguration()
        let external = try externalEdit(loaded)

        let document = try #require(loaded.model.editorDocument())

        #expect(document.configuration == external)
        #expect(document.hasUnsavedChanges == false)
    }
}
