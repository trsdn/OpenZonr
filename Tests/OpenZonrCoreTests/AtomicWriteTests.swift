import Foundation
import Testing
@testable import OpenZonrCore

/// A configuration file that is half written cannot be loaded at all — it is
/// strictly worse than one that is out of date. These tests hold the writer to
/// its promise: the destination is either completely new or completely
/// untouched, and no debris is left behind either way.
struct AtomicWriteTests {

    private let url = URL(fileURLWithPath: "/tmp/openzonr/config.json")
    private var directory: URL { url.deletingLastPathComponent() }

    private func existingContents() -> Data { Data("alte Konfiguration\n".utf8) }

    @Test("Die Zieldatei wird über eine Zwischendatei ersetzt")
    func writesThroughATemporaryFile() throws {
        let fileSystem = InMemoryFileSystem()
        let writer = AtomicFileWriter(fileSystem: fileSystem)
        let payload = Data("neu\n".utf8)

        try writer.write(payload, to: url)

        #expect(fileSystem.data(at: url) == payload)
        // Geschrieben wurde zuerst die Zwischendatei — und zwar im selben
        // Verzeichnis, weil ein Ersetzen über Dateisystemgrenzen hinweg
        // ein Kopiervorgang wäre und der sich unterbrechen lässt.
        let temporaryPath = try #require(fileSystem.writtenPaths.first)
        #expect(temporaryPath != url.path)
        #expect(URL(fileURLWithPath: temporaryPath).deletingLastPathComponent().path == directory.path)
        #expect(URL(fileURLWithPath: temporaryPath).lastPathComponent.hasSuffix(".tmp"))
        // Nach dem Ersetzen bleibt nur die Zieldatei übrig.
        #expect(fileSystem.paths(in: directory) == [url.path])
    }

    @Test("Nach einem fehlgeschlagenen Ersetzen bleibt die Zieldatei unverändert")
    func failedReplaceLeavesTargetUntouched() {
        let original = existingContents()
        let fileSystem = InMemoryFileSystem(files: [url: original])
        fileSystem.failures.replace = true
        let writer = AtomicFileWriter(fileSystem: fileSystem)

        #expect(throws: ConfigurationStoreError.self) {
            try writer.write(Data("neu\n".utf8), to: url)
        }

        #expect(fileSystem.data(at: url) == original)
        // Keine Zwischendatei bleibt zurück.
        #expect(fileSystem.paths(in: directory) == [url.path])
    }

    @Test("Nach einem fehlgeschlagenen Schreiben bleibt die Zieldatei unverändert")
    func failedWriteLeavesTargetUntouched() {
        let original = existingContents()
        let fileSystem = InMemoryFileSystem(files: [url: original])
        fileSystem.failures.write = true
        let writer = AtomicFileWriter(fileSystem: fileSystem)

        #expect(throws: ConfigurationStoreError.self) {
            try writer.write(Data("neu\n".utf8), to: url)
        }

        #expect(fileSystem.data(at: url) == original)
        #expect(fileSystem.paths(in: directory) == [url.path])
    }

    @Test("Ein fehlgeschlagenes Anlegen des Verzeichnisses schreibt nichts")
    func failedDirectoryCreationWritesNothing() {
        let fileSystem = InMemoryFileSystem()
        fileSystem.failures.createDirectory = true
        let writer = AtomicFileWriter(fileSystem: fileSystem)

        #expect(throws: ConfigurationStoreError.self) {
            try writer.write(Data("neu\n".utf8), to: url)
        }

        #expect(fileSystem.data(at: url) == nil)
        #expect(fileSystem.paths(in: directory).isEmpty)
    }

    @Test("Der Fehler nennt die Zieldatei")
    func errorNamesTheDestination() {
        let fileSystem = InMemoryFileSystem(files: [url: existingContents()])
        fileSystem.failures.replace = true
        let writer = AtomicFileWriter(fileSystem: fileSystem)

        do {
            try writer.write(Data("neu\n".utf8), to: url)
            Issue.record("Erwartet wurde ein Fehler")
        } catch let error as ConfigurationStoreError {
            guard case let .writeFailed(failedURL, _) = error else {
                Issue.record("Erwartet wurde .writeFailed, geliefert wurde \(error)")
                return
            }
            #expect(failedURL == url)
        } catch {
            Issue.record("Unerwarteter Fehlertyp: \(error)")
        }
    }

    @Test("Auch der Store lässt die Zieldatei nach einem Fehlschlag unverändert")
    func storeSaveIsAtomicToo() throws {
        let original = try ConfigurationCoding.encode(TestConfigurations.minimal())
        let fileSystem = InMemoryFileSystem(files: [url: original])
        fileSystem.failures.replace = true
        let store = ConfigurationStore(fileSystem: fileSystem)

        var changed = TestConfigurations.minimal()
        changed.roles.append(ZoneRole(id: "neu", name: "Neu"))

        #expect(throws: ConfigurationStoreError.self) {
            try store.save(changed, to: url)
        }
        #expect(fileSystem.data(at: url) == original)
    }

    @Test("Jeder Schreibvorgang verwendet einen eigenen Zwischendateinamen")
    func temporaryNamesAreUnique() throws {
        let fileSystem = InMemoryFileSystem()
        let writer = AtomicFileWriter(fileSystem: fileSystem)

        try writer.write(Data("a\n".utf8), to: url)
        try writer.write(Data("b\n".utf8), to: url)

        // Zwei parallele Schreibvorgänge dürfen sich nicht dieselbe
        // Zwischendatei teilen, sonst zerstört einer das Ergebnis des anderen.
        let temporaries = fileSystem.writtenPaths.filter { $0.hasSuffix(".tmp") }
        #expect(temporaries.count == 2)
        #expect(Set(temporaries).count == 2)
    }
}
