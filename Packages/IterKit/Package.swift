// swift-tools-version: 6.2
// IterKit: everything in Iter that is not macOS UI. Platform-neutral so an iOS target can reuse it.
import PackageDescription

// Swift 6 language mode (the default for tools 6.x) gives complete strict concurrency checking.
let strict: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "IterKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "IterCore", targets: ["IterCore"]),
        .library(name: "IterAstro", targets: ["IterAstro"]),
        .library(name: "IterLight", targets: ["IterLight"]),
        .library(name: "IterData", targets: ["IterData"]),
        .library(name: "IterServices", targets: ["IterServices"]),
        .library(name: "IterDesign", targets: ["IterDesign"]),
        .library(name: "IterFeatures", targets: ["IterFeatures"]),
        .executable(name: "iter-tokens", targets: ["IterTokensTool"]),
    ],
    targets: [
        // Domain value types and service protocols. Foundation only.
        .target(name: "IterCore", swiftSettings: strict),
        // Solar and lunar position and events. Own maths, no ported library.
        .target(name: "IterAstro", dependencies: ["IterCore"], swiftSettings: strict),
        // Light windows, the Light Index, confidence, reasons, the backward schedule, light-first ordering.
        .target(name: "IterLight", dependencies: ["IterCore", "IterAstro"], swiftSettings: strict),
        // SwiftData models, the store, curated spots, the .iter trip document.
        .target(name: "IterData", dependencies: ["IterCore"], resources: [.process("Resources")], swiftSettings: strict),
        // WeatherKit, MapKit, Foundation Models, sample data.
        .target(name: "IterServices", dependencies: ["IterCore", "IterLight", "IterData"], swiftSettings: strict),
        // Design tokens: one registry, a SwiftUI API, and small shared primitives.
        .target(name: "IterDesign", dependencies: ["IterCore"], swiftSettings: strict),
        // Observable view models shared by every platform's UI.
        .target(name: "IterFeatures", dependencies: ["IterCore", "IterAstro", "IterLight", "IterData", "IterServices"], swiftSettings: strict),
        // Exports/imports Design/tokens.json (DTCG) and the asset-catalog colour sets.
        .executableTarget(name: "IterTokensTool", dependencies: ["IterDesign"], swiftSettings: strict),

        .testTarget(name: "IterCoreTests", dependencies: ["IterCore"]),
        .testTarget(name: "IterAstroTests", dependencies: ["IterAstro"]),
        .testTarget(name: "IterLightTests", dependencies: ["IterLight", "IterAstro"]),
        .testTarget(name: "IterDataTests", dependencies: ["IterData"]),
        .testTarget(name: "IterServicesTests", dependencies: ["IterServices"], resources: [.copy("Fixtures")]),
        .testTarget(name: "IterDesignTests", dependencies: ["IterDesign"]),
        .testTarget(name: "IterFeaturesTests", dependencies: ["IterFeatures"]),
    ]
)
