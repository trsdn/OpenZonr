import Foundation
import Testing
@testable import OpenZonrApp
@testable import OpenZonrCore

/// Ein Editor-Stand darf eine neuere Datei nie stillschweigend überschreiben
/// (Issue #42). Alle Tests arbeiten mit einer echten Datei im Temp-Verzeichnis.
@Suite("ConfigurationDocument — Dateistand und Fremdänderungen")
@MainActor
struct ConfigurationDocumentBaselineTests {

    private func makeDocument() throws -> (ConfigurationDocument, TempConfiguration, Configuration) {
        let base = AppModelFixtures.minimalConfiguration()
        let temp = try AppModelFixtures.writeConfiguration(base)
        return (ConfigurationDocument(configuration: base, url: temp.url), temp, base)
    }

    private func externalEdit(_ base: Configuration, at url: URL) throws -> Configuration {
        var external = base
        external.roles.append(ZoneRole(id: "extra", name: "Extra"))
        try ConfigurationStore().save(external, to: url)
        return external
    }

    private func diskRoles(_ url: URL) throws -> [String] {
        guard case let .loaded(c, _, _) = ConfigurationStore().load(at: url) else { throw NSError(domain: "test", code: 1) }
        return c.roles.map(\.id.rawValue)
    }

    @Test("Sichern ohne Fremdänderung funktioniert wiederholt")
    func ownSavesDoNotConflict() throws {
        // `temp` muss bis zum Ende leben: sein Deinit löscht das Verzeichnis.
        let (document, temp, _) = try makeDocument()
        defer { withExtendedLifetime(temp) {} }
        document.apply { var c = $0; c.defaults.dropzones.enabled = true; return c }
        #expect(document.save())
        document.apply { var c = $0; c.defaults.dropzones.enabled = false; return c }
        #expect(document.save())
        #expect(document.hasExternalChange == false)
    }

    @Test("Schmutzig und Datei außerhalb geändert: Sichern wird verweigert, Datei bleibt")
    func staleSaveIsRefused() throws {
        let (document, temp, base) = try makeDocument()
        document.apply { var c = $0; c.defaults.dropzones.enabled = true; return c }
        _ = try externalEdit(base, at: temp.url)

        #expect(document.save() == false)

        #expect(document.hasExternalChange)
        #expect(document.saveProblem?.contains("außerhalb") == true)
        #expect(try diskRoles(temp.url).contains("extra"))
        // Die eigene Änderung ist nicht verloren.
        #expect(document.configuration.defaults.dropzones.enabled == true)
        #expect(document.hasUnsavedChanges)
    }

    @Test("Ausdrückliches Überschreiben schreibt trotzdem")
    func explicitOverwriteWrites() throws {
        let (document, temp, base) = try makeDocument()
        document.apply { var c = $0; c.defaults.dropzones.enabled = true; return c }
        _ = try externalEdit(base, at: temp.url)
        _ = document.save()

        #expect(document.save(overwritingExternalChanges: true))

        #expect(try diskRoles(temp.url).contains("extra") == false)
        #expect(document.hasExternalChange == false)
        #expect(document.hasUnsavedChanges == false)
    }

    @Test("Verwerfen nach Fremdänderung übernimmt den Dateistand")
    func revertTakesDiskVersion() throws {
        let (document, temp, base) = try makeDocument()
        document.apply { var c = $0; c.defaults.dropzones.enabled = true; return c }
        let external = try externalEdit(base, at: temp.url)
        _ = document.save()

        document.revert()

        #expect(document.configuration == external)
        #expect(document.hasExternalChange == false)
        #expect(document.hasUnsavedChanges == false)
    }

    @Test("Nur Leerraum in der Datei geändert: kein Konflikt")
    func whitespaceOnlyChangeIsNoConflict() throws {
        let (document, temp, _) = try makeDocument()
        document.apply { var c = $0; c.defaults.dropzones.enabled = true; return c }
        var data = try Data(contentsOf: temp.url)
        data.append(Data("\n\n".utf8))
        try data.write(to: temp.url)

        #expect(document.fileChangedOnDisk)
        #expect(document.save())
        #expect(document.hasExternalChange == false)
    }

    @Test("reconcile: sauberer Editor übernimmt die Datei")
    func reconcileCleanAdoptsDisk() throws {
        let (document, temp, base) = try makeDocument()
        let external = try externalEdit(base, at: temp.url)

        document.reconcile(with: external, bytes: ConfigurationDocument.bytes(at: temp.url))

        #expect(document.configuration == external)
        #expect(document.hasUnsavedChanges == false)
        #expect(document.hasExternalChange == false)
        #expect(document.fileChangedOnDisk == false)
    }

    @Test("reconcile: schmutziger Editor behält Änderungen und meldet den Konflikt")
    func reconcileDirtyKeepsEdits() throws {
        let (document, temp, base) = try makeDocument()
        document.apply { var c = $0; c.defaults.dropzones.enabled = true; return c }
        let external = try externalEdit(base, at: temp.url)

        document.reconcile(with: external, bytes: ConfigurationDocument.bytes(at: temp.url))

        #expect(document.configuration.defaults.dropzones.enabled == true)
        #expect(document.hasUnsavedChanges)
        #expect(document.hasExternalChange)
        #expect(document.save() == false)
    }
}
