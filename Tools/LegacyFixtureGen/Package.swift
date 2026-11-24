// swift-tools-version: 6.2
//
// LegacyFixtureGen: FIXTURE / DRY-RUN TOOL ONLY.
//
// This package holds a frozen, verbatim copy of the pre-rebuild store code (the old IterCore and IterData modules) plus
// IterFixtureGen, which uses it to write the SwiftData store fixtures in Packages/Iter/Tests/IterStoreTests/Fixtures and to
// dump a store as the OLD code reads it (`--dump`), the "before" side of a migration dry run.
//
// It is NEVER linked into the Mac or iOS app and NEVER a dependency of Packages/Iter. Do not fix, refactor or extend the
// frozen sources: they are the oracle. See README.md in this folder.
import PackageDescription

let strict: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "LegacyFixtureGen",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "IterFixtureGen", targets: ["IterFixtureGen"]),
    ],
    targets: [
        // Domain value types and service protocols (old code, frozen).
        .target(name: "IterCore", swiftSettings: strict),
        // The old SwiftData models, schemas V1-V4, store and .iter trip document (old code, frozen).
        .target(name: "IterData", dependencies: ["IterCore"], resources: [.process("Resources")], swiftSettings: strict),
        // Writes the fixtures and the dumps with the old code (@testable IterData).
        .executableTarget(name: "IterFixtureGen", dependencies: ["IterData", "IterCore"], swiftSettings: strict),
    ]
)
