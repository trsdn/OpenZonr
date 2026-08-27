import Foundation
@testable import OpenZonrCore

/// Fixtures shared by the tests.
///
/// Two kinds of configuration are used throughout:
///
/// - ``example()`` — the shipped `Examples/openzonr.config.json`. It is
///   documentation, so every test that touches it also guards it against drift.
/// - ``minimal()`` — the smallest configuration that validates. Tests that check
///   a single validation rule start from it and break exactly one thing, so the
///   resulting report contains exactly the finding under test and nothing else.
enum TestConfigurations {

    // MARK: - The shipped example

    /// Locates `Examples/openzonr.config.json` relative to this source file.
    static var exampleURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Support
            .deletingLastPathComponent() // OpenZonrCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // package root
            .appendingPathComponent("Examples/openzonr.config.json")
    }

    static func exampleData() throws -> Data {
        try Data(contentsOf: exampleURL)
    }

    static func example() throws -> Configuration {
        try ConfigurationCoding.decode(exampleData())
    }

    // MARK: - Synthetic fixtures

    /// One built-in display with a two-zone layout, two roles, one profile, one
    /// rule. Valid, and small enough that a report against it is easy to read.
    static func minimal() -> Configuration {
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
                ),
                PlacementRule(
                    id: "chat-rule",
                    name: "Chat",
                    priority: 5,
                    match: WindowMatch(bundleIdentifier: "com.example.chat"),
                    action: PlacementAction(role: "communication")
                )
            ]
        )
    }

    /// ``minimal()`` after applying `mutate`, for tests that break exactly one thing.
    static func minimal(_ mutate: (inout Configuration) -> Void) -> Configuration {
        var configuration = minimal()
        mutate(&configuration)
        return configuration
    }

    // MARK: - Windows

    /// A window snapshot with sensible defaults, so a test only states what it
    /// actually cares about.
    static func window(
        bundleIdentifier: String? = "com.example.editor",
        processIdentifier: Int32 = 501,
        title: String? = "Dokument",
        role: String? = "AXWindow",
        subrole: String? = "AXStandardWindow",
        frame: WindowFrame = WindowFrame(x: 0, y: 0, width: 1200, height: 800),
        isFirstWindowAfterLaunch: Bool = true,
        observedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        windowLayer: Int = 0
    ) -> WindowSnapshot {
        WindowSnapshot(
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier,
            title: title,
            role: role,
            subrole: subrole,
            frame: frame,
            isFirstWindowAfterLaunch: isFirstWindowAfterLaunch,
            observedAt: observedAt,
            windowLayer: windowLayer
        )
    }

    /// A window identifier, for occupancy and manual override tests.
    static func identifier(_ token: String, processIdentifier: Int32 = 501) -> WindowIdentifier {
        WindowIdentifier(processIdentifier: processIdentifier, token: token)
    }

    // MARK: - Displays

    /// A 1920×1080 display whose visible frame is reduced by the menu bar (25 pt)
    /// and the Dock (70 pt at the bottom), positioned at the AppKit origin.
    static let mainVisibleFrame = VisibleFrame(x: 0, y: 70, width: 1920, height: 1080 - 25 - 70)

    /// A secondary display placed to the *left* of the main one, which gives it
    /// a negative origin — the case that breaks naive coordinate maths.
    static let leftVisibleFrame = VisibleFrame(x: -1440, y: 0, width: 1440, height: 900)
}
