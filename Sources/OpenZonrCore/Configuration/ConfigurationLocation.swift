import Foundation

/// Resolves where the configuration file lives.
///
/// Three sources, in decreasing precedence:
///
/// 1. an explicit path handed in by the caller (command line flag, test),
/// 2. the environment variable ``environmentVariableName``,
/// 3. `~/Library/Application Support/OpenZonr/config.json`.
///
/// The Application Support directory is the location Apple expects, which keeps
/// the file out of the way for users who never touch it. The environment
/// override exists for the other group: people who keep their configuration in
/// a dotfile repository and want it version controlled next to everything else.
/// Supporting both costs one variable and settles the question for good.
///
/// The environment is passed in rather than read from `ProcessInfo` inside the
/// resolving code, so tests never have to mutate the process environment.
public enum ConfigurationLocation {

    /// Environment variable that overrides the default path.
    public static let environmentVariableName = "OPENZONR_CONFIG"

    /// File name used inside the default directory.
    public static let fileName = "config.json"

    /// Directory the configuration lives in when no override is given.
    public static func defaultDirectory(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("OpenZonr", isDirectory: true)
    }

    /// The configuration file location for the given inputs.
    ///
    /// - Parameters:
    ///   - explicitPath: A path supplied by the caller. Wins over everything else.
    ///   - environment: Environment to consult for ``environmentVariableName``.
    ///   - homeDirectory: Home directory used to build the default path.
    public static func resolve(
        explicitPath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL {
        if let explicitPath, !explicitPath.isEmpty {
            return expand(explicitPath, homeDirectory: homeDirectory)
        }
        if let fromEnvironment = environment[environmentVariableName], !fromEnvironment.isEmpty {
            return expand(fromEnvironment, homeDirectory: homeDirectory)
        }
        return defaultDirectory(homeDirectory: homeDirectory)
            .appendingPathComponent(fileName, isDirectory: false)
    }

    /// Expands a leading `~` and resolves relative paths against the current
    /// working directory.
    ///
    /// `~` is expanded manually against the supplied home directory instead of
    /// through `NSString.expandingTildeInPath`, which would silently consult the
    /// real home directory and make tests depend on the machine they run on.
    private static func expand(_ path: String, homeDirectory: URL) -> URL {
        if path == "~" {
            return homeDirectory
        }
        if path.hasPrefix("~/") {
            return homeDirectory.appendingPathComponent(String(path.dropFirst(2)))
        }
        return URL(fileURLWithPath: path)
    }
}
