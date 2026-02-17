// swift-tools-version: 5.9
// ABOUTME: SPM package defining HelixKit library for mutagen CLI integration.
// ABOUTME: Provides models, CLI wrapper, and session state management.

import PackageDescription

let package = Package(
    name: "HelixKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "HelixKit", targets: ["HelixKit"]),
    ],
    targets: [
        .systemLibrary(
            name: "CHelixDiff",
            path: "Sources/CHelixDiff"
        ),
        .target(
            name: "HelixKit",
            dependencies: ["CHelixDiff"],
            path: "Sources/HelixKit",
            linkerSettings: [
                .unsafeFlags([
                    "-LRustDiff/target/release",
                ]),
            ]
        ),
        .testTarget(
            name: "HelixKitTests",
            dependencies: ["HelixKit"],
            path: "Tests/HelixKitTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
