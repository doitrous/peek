// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Peek",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic (no AppKit) — testable.
        .target(
            name: "PeekCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The app itself.
        .executableTarget(
            name: "Peek",
            dependencies: ["PeekCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PeekCoreTests",
            dependencies: ["PeekCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
