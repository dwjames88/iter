// swift-tools-version: 6.2
// IterUpdater: self-update for the directly distributed Iter.app, plus the release tooling that feeds it.
// Foundation, CryptoKit, Security and Darwin only; no third-party code.
import PackageDescription

// Swift 6 language mode (the default for tools 6.x) gives complete strict concurrency checking.
let strict: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "IterUpdater",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "IterUpdater", targets: ["IterUpdater"]),
        .library(name: "IterReleaseKit", targets: ["IterReleaseKit"]),
        .executable(name: "iter-release", targets: ["IterReleaseTool"]),
        .executable(name: "updater-fixture", targets: ["UpdaterFixture"]),
    ],
    targets: [
        // Versions, feed, Ed25519 verification, download, install and relaunch.
        .target(name: "IterUpdater", swiftSettings: strict),
        // Changelog rewriting and feed building, split out of the CLI so they are testable.
        .target(name: "IterReleaseKit", dependencies: ["IterUpdater"], swiftSettings: strict),
        // The `iter-release` command used by the release scripts.
        .executableTarget(name: "IterReleaseTool", dependencies: ["IterReleaseKit"], swiftSettings: strict),
        // Headless stand-in for Iter.app used by the end-to-end update test.
        .executableTarget(name: "UpdaterFixture", dependencies: ["IterUpdater"], swiftSettings: strict),

        .testTarget(name: "IterUpdaterTests", dependencies: ["IterUpdater"]),
        .testTarget(name: "IterReleaseKitTests", dependencies: ["IterReleaseKit", "IterUpdater"]),
    ]
)
