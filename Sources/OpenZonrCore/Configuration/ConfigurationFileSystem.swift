import Foundation

/// The narrow slice of file system behaviour the configuration store needs.
///
/// It exists as a protocol for one reason: the guarantee that a crash during a
/// write never leaves half a configuration file behind can only be proven by
/// making the write fail on purpose. Without this seam that test would have to
/// resort to permissions tricks that behave differently on every machine.
///
/// Intentionally **not** `Sendable`: the disk implementation is a value type and
/// trivially safe, but the in-memory test double holds mutable state, and
/// forcing it to be `Sendable` would mean `@unchecked` — buying nothing for a
/// type that never leaves the test that created it.
public protocol ConfigurationFileSystem {

    /// Whether anything exists at `url`.
    func fileExists(at url: URL) -> Bool

    /// Reads the file at `url`.
    func contents(at url: URL) throws -> Data

    /// Creates `url` and every missing parent directory.
    func createDirectory(at url: URL) throws

    /// Writes `data` to `url`, replacing existing contents. Not atomic — this is
    /// the primitive ``AtomicFileWriter`` builds atomicity from.
    func write(_ data: Data, to url: URL) throws

    /// Moves `temporary` onto `destination`, replacing it if present.
    func replaceItem(at destination: URL, with temporary: URL) throws

    /// Removes the item at `url`. Does nothing when nothing is there.
    func removeItem(at url: URL) throws

    /// Copies `source` to `destination`, replacing an existing destination.
    func copyItem(at source: URL, to destination: URL) throws
}

/// The real file system, backed by `FileManager`.
public struct DiskFileSystem: ConfigurationFileSystem, Sendable {

    public init() {}

    public func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func contents(at url: URL) throws -> Data {
        try Data(contentsOf: url)
    }

    public func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: [])
    }

    public func replaceItem(at destination: URL, with temporary: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            // `replaceItemAt` performs the exchange atomically and preserves the
            // destination's metadata, which a remove-then-move pair would not.
            _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: destination)
        }
    }

    public func removeItem(at url: URL) throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }

    public func copyItem(at source: URL, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }
}
