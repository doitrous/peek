// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Peek",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Auto-update framework (EdDSA-signed appcast from GitHub Releases).
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // Pure logic (no AppKit) — testable.
        .target(
            name: "PeekCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // The app itself.
        .executableTarget(
            name: "Peek",
            dependencies: [
                "PeekCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "PeekCoreTests",
            dependencies: ["PeekCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
