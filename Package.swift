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
        .library(name: "OpenZonrCore", targets: ["OpenZonrCore"])
    ],
    targets: [
        .target(
            name: "OpenZonrCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "OpenZonrCoreTests",
            dependencies: ["OpenZonrCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
