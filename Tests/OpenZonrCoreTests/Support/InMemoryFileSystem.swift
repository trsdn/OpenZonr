import Foundation
@testable import OpenZonrCore

/// A file system that lives in a dictionary, with the ability to fail on demand.
///
/// The point of the atomic writer is that a failure leaves the destination
/// untouched. That guarantee cannot be tested against a real disk without
/// resorting to permission tricks that behave differently on every machine, so
/// the failure is injected here instead.
final class InMemoryFileSystem: ConfigurationFileSystem {

    /// Errors this file system raises.
    enum Failure: Error, Equatable {
        case notFound(String)
        case injected(String)
    }

    /// Which operation should fail.
    struct FailurePlan {
        var write = false
        var replace = false
        var read = false
        var createDirectory = false
        var copy = false
    }

    private(set) var files: [String: Data] = [:]
    private(set) var directories: Set<String> = []

    /// Operations that should raise ``Failure/injected(_:)`` instead of running.
    var failures = FailurePlan()

    /// Every path ever written, in order — used to prove that a temporary file
    /// was created as a sibling of the destination.
    private(set) var writtenPaths: [String] = []

    init(files: [URL: Data] = [:]) {
        for (url, data) in files {
            self.files[url.path] = data
            self.directories.insert(url.deletingLastPathComponent().path)
        }
    }

    // MARK: - Inspection

    func data(at url: URL) -> Data? { files[url.path] }

    /// Paths of all files inside `directory`, sorted.
    func paths(in directory: URL) -> [String] {
        files.keys
            .filter { URL(fileURLWithPath: $0).deletingLastPathComponent().path == directory.path }
            .sorted()
    }

    // MARK: - ConfigurationFileSystem

    func fileExists(at url: URL) -> Bool {
        files[url.path] != nil
    }

    func contents(at url: URL) throws -> Data {
        if failures.read { throw Failure.injected("read") }
        guard let data = files[url.path] else { throw Failure.notFound(url.path) }
        return data
    }

    func createDirectory(at url: URL) throws {
        if failures.createDirectory { throw Failure.injected("createDirectory") }
        directories.insert(url.path)
    }

    func write(_ data: Data, to url: URL) throws {
        if failures.write { throw Failure.injected("write") }
        files[url.path] = data
        writtenPaths.append(url.path)
    }

    func replaceItem(at destination: URL, with temporary: URL) throws {
        if failures.replace { throw Failure.injected("replaceItem") }
        guard let data = files[temporary.path] else { throw Failure.notFound(temporary.path) }
        files[destination.path] = data
        files[temporary.path] = nil
    }

    func removeItem(at url: URL) throws {
        files[url.path] = nil
    }

    func copyItem(at source: URL, to destination: URL) throws {
        if failures.copy { throw Failure.injected("copyItem") }
        guard let data = files[source.path] else { throw Failure.notFound(source.path) }
        files[destination.path] = data
    }
}
