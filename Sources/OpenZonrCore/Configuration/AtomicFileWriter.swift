import Foundation

/// Writes a file so that it is either completely new or completely unchanged.
///
/// The sequence is: write a temporary file **in the destination directory**,
/// then replace the destination with it. The temporary file must be a sibling
/// because a replace across file system boundaries is a copy, and a copy can be
/// interrupted halfway.
///
/// If anything fails, the temporary file is removed and the destination is left
/// exactly as it was. A configuration file that is half written is worse than
/// one that is out of date: the first one cannot be loaded at all.
public struct AtomicFileWriter {

    private let fileSystem: any ConfigurationFileSystem

    public init(fileSystem: any ConfigurationFileSystem = DiskFileSystem()) {
        self.fileSystem = fileSystem
    }

    /// Writes `data` to `url`, creating missing parent directories.
    ///
    /// - Throws: ``ConfigurationStoreError/writeFailed(_:underlying:)`` for every
    ///   failure, with the original error described in the payload.
    public func write(_ data: Data, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        let temporary = directory.appendingPathComponent(
            ".\(url.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: false
        )

        do {
            try fileSystem.createDirectory(at: directory)
            try fileSystem.write(data, to: temporary)
        } catch {
            try? fileSystem.removeItem(at: temporary)
            throw ConfigurationStoreError.writeFailed(url, underlying: String(describing: error))
        }

        do {
            try fileSystem.replaceItem(at: url, with: temporary)
        } catch {
            // The destination was not touched; drop the leftover so a failed
            // write does not litter the directory with temporary files.
            try? fileSystem.removeItem(at: temporary)
            throw ConfigurationStoreError.writeFailed(url, underlying: String(describing: error))
        }
    }
}
