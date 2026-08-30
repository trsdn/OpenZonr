import Foundation
@testable import OpenZonrApp
@testable import OpenZonrCore
@testable import OpenZonrMac

/// Aufbauhilfen für Tests der App-Zustandslogik.
///
/// Die Zustände, die interessant sind, hängen alle daran, was `AppModel` gerade
/// „weiß" — Konfiguration geladen oder nicht, Profil aktiv oder nicht, Editor
/// offen oder nicht. Ein Test soll genau eine dieser Achsen setzen und die
/// anderen kennen. Die Bausteine hier machen das lesbar; der Aufbau bleibt
/// bewusst dünn (kein Framework), damit ein Test noch selbst dokumentiert, was
/// er einrichtet.
///
/// Kein Zugriff auf Bedienungshilfen, kein Fenster nach vorne holen, kein
/// Event-Tap: alles passiert im Speicher, `windowAccess` bleibt `.notTrusted`
/// und `startEngineIfPossible` schaltet folglich nichts ein. Genau das ist der
/// Punkt: die geprüften Zustandsübergänge brauchen keinen Bildschirm.
enum AppModelFixtures {

    /// Eine kleine gültige Konfiguration mit einem Bildschirm, zwei Zonen und
    /// zwei Regeln. `dropzones.enabled` steht auf `false`, damit ein
    /// versehentlicher `restart()` am `DropzoneController` nicht anfängt,
    /// einen Event-Tap zu installieren; die Tests, die die Ziehen-Zusicherung
    /// prüfen, drehen den Schalter selbst um.
    static func minimalConfiguration() -> Configuration {
        Configuration(
            version: Configuration.currentVersion,
            displays: [
                DisplayDescriptor(
                    alias: "main",
                    displayName: "Hauptbildschirm",
                    identity: .builtin,
                    layouts: [
                        Layout(
                            id: "halves",
                            name: "Zwei Hälften",
                            zones: [
                                Zone(id: "left", name: "Links", frame: RelativeRect(x: 0, y: 0, width: 0.5, height: 1)),
                                Zone(id: "right", name: "Rechts", frame: RelativeRect(x: 0.5, y: 0, width: 0.5, height: 1))
                            ]
                        )
                    ],
                    defaultLayoutID: "halves"
                )
            ],
            roles: [
                ZoneRole(id: "editor", name: "Editor"),
                ZoneRole(id: "communication", name: "Kommunikation")
            ],
            profiles: [
                Profile(
                    id: "solo",
                    name: "Solo",
                    fingerprint: ProfileFingerprint(displays: ["main"]),
                    layouts: ["main": "halves"],
                    roleBindings: [
                        RoleBinding(role: "editor", display: "main", zone: "left"),
                        RoleBinding(role: "communication", display: "main", zone: "right")
                    ],
                    fallback: RoleBinding(role: "editor", display: "main", zone: "left")
                )
            ],
            rules: [
                PlacementRule(
                    id: "editor-rule",
                    name: "Editor",
                    priority: 10,
                    match: WindowMatch(bundleIdentifier: "com.example.editor"),
                    action: PlacementAction(role: "editor")
                )
            ],
            defaults: GlobalDefaults(
                dropzones: DropzoneSettings(enabled: false)
            )
        )
    }

    /// Legt eine Konfiguration in einem temporären Verzeichnis ab und gibt den
    /// Pfad zurück. Das Verzeichnis wird beim Deinitialisieren wieder gelöscht.
    static func writeConfiguration(_ configuration: Configuration) throws -> TempConfiguration {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("openzonr-app-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("config.json")
        try ConfigurationStore().save(configuration, to: url)
        return TempConfiguration(url: url, directory: directory)
    }

    /// Ein `AppModel` mit geladener Konfiguration und aktivem Profil, aber ohne
    /// Bedienungshilfen. Standardaufbau für die meisten Tests: alles ausser
    /// dem Zugriff auf echte Fenster ist eingerichtet.
    @MainActor
    static func modelWithLoadedConfiguration(_ configuration: Configuration? = nil) throws -> LoadedModel {
        let configuration = configuration ?? minimalConfiguration()
        let temp = try writeConfiguration(configuration)
        let model = AppModel(configurationURL: temp.url)
        model.reloadConfiguration()
        // Ohne echten `WatchEngine` gibt es keinen Profilzustand — wir bauen ihn
        // von Hand. `apply(_:to:)` liest `activeProfile`, deshalb muss er stehen.
        model._setProfileStateForTesting(.matched(configuration.profiles[0]))
        return LoadedModel(model: model, temp: temp)
    }

    /// Ein `AppModel` mit geladener Konfiguration, aber ohne Profilzustand —
    /// die Lage „Kein Profil ist aktiv" für die Guard-Prüfung.
    @MainActor
    static func modelWithoutProfile(_ configuration: Configuration? = nil) throws -> LoadedModel {
        let configuration = configuration ?? minimalConfiguration()
        let temp = try writeConfiguration(configuration)
        let model = AppModel(configurationURL: temp.url)
        model.reloadConfiguration()
        return LoadedModel(model: model, temp: temp)
    }

    /// Ein `AppModel` ohne Konfiguration überhaupt: der Pfad zeigt ins Leere.
    @MainActor
    static func modelWithoutConfiguration() -> AppModel {
        let missing = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("openzonr-missing-\(UUID().uuidString).json")
        let model = AppModel(configurationURL: missing)
        model.reloadConfiguration()
        return model
    }
}

/// Ein geschriebenes Konfigurationsverzeichnis, das sich beim Freigeben selbst
/// aufräumt. Das wäre auch in einem `defer` in jedem Test möglich — diese
/// Klasse macht es einheitlich und schwer zu vergessen.
final class TempConfiguration: @unchecked Sendable {
    let url: URL
    let directory: URL

    init(url: URL, directory: URL) {
        self.url = url
        self.directory = directory
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}

@MainActor
struct LoadedModel {
    let model: AppModel
    let temp: TempConfiguration
}
