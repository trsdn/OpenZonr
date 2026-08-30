import Foundation

/// Loads a ``Configuration`` from disk and reports problems in a form a user can
/// act on.
///
/// The tracer bullet keeps this deliberately small: read, decode, validate the
/// cross references the type system cannot express. Migration between schema
/// versions is not implemented yet — an unknown version is refused rather than
/// silently reinterpreted.
public enum ConfigurationLoader {

    /// Everything that can go wrong while loading, phrased for the CLI.
    public enum LoadError: Error, CustomStringConvertible {
        case fileNotFound(URL)
        case unreadable(URL, any Error)
        case malformed(URL, any Error)
        case unsupportedVersion(found: Int, supported: Int)
        case invalid([String])

        public var description: String {
            switch self {
            case let .fileNotFound(url):
                return """
                Keine Konfiguration unter \(url.path) gefunden.
                Lege eine an — \(ConfigurationLoader.exampleHint)
                """
            case let .unreadable(url, error):
                return "Konfiguration \(url.path) ist nicht lesbar: \(error.localizedDescription)"
            case let .malformed(url, error):
                return "Konfiguration \(url.path) ist kein gültiges JSON für dieses Schema: \(error)"
            case let .unsupportedVersion(found, supported):
                return """
                Konfigurationsversion \(found) wird nicht unterstützt (dieser Build kennt \(supported)).
                Migrationen sind noch nicht implementiert.
                """
            case let .invalid(problems):
                return "Konfiguration ist in sich widersprüchlich:\n" + problems.map { "  - \($0)" }.joined(separator: "\n")
            }
        }
    }

    static let exampleHint = "Examples/openzonr.config.json ist eine gültige Vorlage, "
        + "die echten Display-Identitäten liefert `openzonr displays --config-fragment`."

    /// Where OpenZonr looks when no path is given.
    ///
    /// `~/.config/openzonr/config.json` wins over `Application Support` because
    /// the configuration is a text file people will want in their dotfiles
    /// repository, and because a path that can be typed is worth a lot for a
    /// command line tool. See `docs/offene-fragen.md`, question 6.
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/openzonr/config.json")
    }

    /// Reads and validates a configuration file.
    public static func load(from url: URL) throws -> Configuration {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw LoadError.fileNotFound(url)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw LoadError.unreadable(url, error)
        }

        let configuration: Configuration
        do {
            configuration = try JSONDecoder().decode(Configuration.self, from: data)
        } catch {
            throw LoadError.malformed(url, error)
        }

        guard configuration.version == Configuration.currentVersion else {
            throw LoadError.unsupportedVersion(
                found: configuration.version,
                supported: Configuration.currentVersion
            )
        }

        let problems = validate(configuration)
        guard problems.isEmpty else { throw LoadError.invalid(problems) }

        return configuration
    }

    /// Cross-reference checks that `Codable` cannot perform.
    ///
    /// Runs at load time rather than at placement time on purpose: a dangling
    /// zone reference should be a startup error, not a window that mysteriously
    /// stays where it was.
    public static func validate(_ configuration: Configuration) -> [String] {
        var problems: [String] = []

        let displaysByAlias = Dictionary(
            configuration.displays.map { ($0.alias, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        if displaysByAlias.count != configuration.displays.count {
            problems.append("Mehrere Displays teilen sich denselben alias")
        }

        let knownRoles = Set(configuration.roles.map(\.id))
        for rule in configuration.rules where !knownRoles.contains(rule.action.role) {
            problems.append("Regel \"\(rule.id)\" verweist auf unbekannte Rolle \"\(rule.action.role)\"")
        }

        for rule in configuration.rules {
            if let pattern = rule.match.titlePattern,
               (try? NSRegularExpression(pattern: pattern)) == nil {
                problems.append("Regel \"\(rule.id)\" hat ein ungültiges titlePattern: \(pattern)")
            }
        }

        for display in configuration.displays
        where !display.layouts.contains(where: { $0.id == display.defaultLayoutID }) {
            problems.append("Display \"\(display.alias)\" hat kein Layout \"\(display.defaultLayoutID)\"")
        }

        for profile in configuration.profiles {
            for alias in profile.fingerprint.displays where displaysByAlias[alias] == nil {
                problems.append("Profil \"\(profile.id)\" nennt im Fingerprint unbekanntes Display \"\(alias)\"")
            }

            for binding in profile.roleBindings + [profile.fallback] {
                guard let display = displaysByAlias[binding.display] else {
                    problems.append("Profil \"\(profile.id)\" bindet auf unbekanntes Display \"\(binding.display)\"")
                    continue
                }
                let layoutID = profile.layouts[binding.display] ?? display.defaultLayoutID
                guard let layout = display.layouts.first(where: { $0.id == layoutID }) else {
                    problems.append("Profil \"\(profile.id)\": Display \"\(display.alias)\" kennt kein Layout \"\(layoutID)\"")
                    continue
                }
                if !layout.zones.contains(where: { $0.id == binding.zone }) {
                    problems.append("Profil \"\(profile.id)\": Layout \"\(layout.id)\" enthält keine Zone \"\(binding.zone)\"")
                }
            }
        }

        let fingerprints = configuration.profiles.map(\.fingerprint.normalized)
        if Set(fingerprints).count != fingerprints.count {
            problems.append("Zwei Profile haben denselben Fingerprint — die Auswahl wäre nicht eindeutig")
        }

        return problems
    }
}
