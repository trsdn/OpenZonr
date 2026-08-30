// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenZonr",
    platforms: [
        // Accessibility, CoreGraphics display and NSWorkspace APIs are all long-established.
        // macOS 14 is chosen for the UI layer that will follow (Observation, MenuBarExtra).
        .macOS(.v14)
    ],
    products: [
        .library(name: "OpenZonrCore", targets: ["OpenZonrCore"]),
        .library(name: "OpenZonrMac", targets: ["OpenZonrMac"]),
        .executable(name: "openzonr", targets: ["openzonr"]),
        .executable(name: "OpenZonrApp", targets: ["OpenZonrApp"])
    ],
    targets: [
        .target(
            name: "OpenZonrCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Everything that talks to macOS: Accessibility, CoreGraphics displays,
        // and the watch engine that ties them to OpenZonrCore. It is its own
        // target because the observation and placement logic inside it was
        // expensive to get right — three of its details were only found by
        // measuring on real hardware (see docs/tracer-bullet.md) — and a second
        // front end must inherit them rather than reimplement them.
        .target(
            name: "OpenZonrMac",
            dependencies: ["OpenZonrCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The command line tool is the tracer bullet and stays the diagnostic
        // instrument. Argument parsing is done by hand — three subcommands do
        // not justify a dependency, and a dependency-free package stays trivial
        // to build and audit.
        .executableTarget(
            name: "openzonr",
            dependencies: ["OpenZonrCore", "OpenZonrMac"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The menu bar app. A SwiftPM executable rather than an Xcode target:
        // Scripts/bundle.sh already produces the signed bundle whose identifier
        // and team the Accessibility grant is bound to, and keeping one build
        // system means `swift build` and `swift test` remain the whole story.
        .executableTarget(
            name: "OpenZonrApp",
            dependencies: ["OpenZonrCore", "OpenZonrMac"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The macOS layer is mostly untestable without a screen and a granted
        // Accessibility permission, and pretending otherwise would produce tests
        // that prove nothing. What is testable are the pure decisions the menu
        // bar app added on top of it, and those are what this target covers.
        .testTarget(
            name: "OpenZonrMacTests",
            dependencies: ["OpenZonrCore", "OpenZonrMac"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Die Zustandslogik der Menüleisten-App. Kein Oberflächentest — was ein
        // Menüeintrag anzeigt oder wie sich eine Geste anfühlt, bleibt „nicht
        // gemessen" (siehe Issue #25). Geprüft werden Zustandsübergänge, die
        // heute nur deshalb ungetestet waren, weil sie zufällig in einem Modul
        // ohne Testziel lagen: `AppModel` (Meldungen für Anheft-Fehler,
        // `apply` in Erfolg und Einspruch, Frontmost-Guard) und der
        // Zustand-teil von `DropzoneController` (Pause-/Aus-Zusicherung, ohne
        // Event-Tap).
        .testTarget(
            name: "OpenZonrAppTests",
            dependencies: ["OpenZonrCore", "OpenZonrMac", "OpenZonrApp"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "OpenZonrCoreTests",
            dependencies: ["OpenZonrCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
