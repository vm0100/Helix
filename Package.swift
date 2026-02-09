// swift-tools-version: 5.9
// ABOUTME: SPM package defining MutagenKit library for mutagen CLI integration.
// ABOUTME: Provides models, CLI wrapper, and session state management.

import PackageDescription

let package = Package(
    name: "MutagenKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MutagenKit", targets: ["MutagenKit"]),
    ],
    targets: [
        .target(
            name: "MutagenKit",
            path: "Sources/MutagenKit"
        ),
        .testTarget(
            name: "MutagenKitTests",
            dependencies: ["MutagenKit"],
            path: "Tests/MutagenKitTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
