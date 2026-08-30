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
        .executable(name: "openzonr", targets: ["openzonr"])
    ],
    targets: [
        .target(
            name: "OpenZonrCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // The command line tool is the tracer bullet: it is the smallest shell
        // around OpenZonrCore that can actually move a window. Argument parsing
        // is done by hand — three subcommands do not justify a dependency, and
        // a dependency-free package stays trivial to build and audit.
        .executableTarget(
            name: "openzonr",
            dependencies: ["OpenZonrCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "OpenZonrCoreTests",
            dependencies: ["OpenZonrCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
