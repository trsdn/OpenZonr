import Foundation
import OpenZonrCore

/// Turns the store's load result into "a configuration, or a full explanation".
///
/// ``ConfigurationStore`` answers with four separate cases on purpose — a
/// missing file is not an error, and an invalid file carries every finding at
/// once. A command line tool has to collapse that into "run" or "explain and
/// stop", and this is the single place where that collapse happens, so the
/// wording of the explanation is written once instead of per subcommand.
enum ConfigurationLoading {

    static func load(from url: URL, store: ConfigurationStore = ConfigurationStore()) throws -> Configuration {
        switch store.load(at: url) {
        case let .loaded(configuration, report, _):
            // Warnings are printed but never block: the validator flags things
            // that are suspicious, not things that are impossible.
            for finding in report.sorted().warnings {
                Log.warn("Konfiguration: \(finding)")
            }
            return configuration

        case let .missing(url):
            throw CommandError("""
            Keine Konfiguration unter \(url.path).

            Standardpfad ist ~/Library/Application Support/OpenZonr/config.json.
            Abweichend über die Umgebungsvariable \(ConfigurationLocation.environmentVariableName)
            oder über --config <pfad>.

            Ein Grundgerüst steht in Examples/openzonr.config.json. Die dort
            eingetragenen Display-Kennungen sind erfunden; die echten liefert:
              openzonr displays --config-fragment
            """)

        case let .invalid(report, url):
            var text = "Die Konfiguration \(url.path) ist nicht verwendbar:\n"
            for finding in report.sorted().findings {
                text += "\n  \(finding)"
            }
            throw CommandError(text)

        case let .failed(error):
            throw CommandError(error.description)
        }
    }
}
