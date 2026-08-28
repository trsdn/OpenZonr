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
        .executable(name: "openzonr", targets: ["openzonr"])
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
        .testTarget(
            name: "OpenZonrCoreTests",
            dependencies: ["OpenZonrCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
