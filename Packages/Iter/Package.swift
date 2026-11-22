// swift-tools-version: 6.2
// Iter: everything in the rebuilt Iter that is not an app shell. The Mac and iOS apps link this package (and the Mac
// app IterUpdater) and nothing else. Layout and dependency rules: docs/rebuild/BLUEPRINT.md §3.
// Swift 6 language mode (the default for tools 6.x) gives complete strict concurrency checking. No third-party code.
import PackageDescription

let strict: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
]

let package = Package(
    name: "Iter",
    defaultLocalization: "en",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "IterModel", targets: ["IterModel"]),
        .library(name: "IterAstro", targets: ["IterAstro"]),
        .library(name: "IterSky", targets: ["IterSky"]),
        .library(name: "IterPlan", targets: ["IterPlan"]),
        .library(name: "IterStore", targets: ["IterStore"]),
        .library(name: "IterSources", targets: ["IterSources"]),
        .library(name: "IterSourcesLive", targets: ["IterSourcesLive"]),
        .library(name: "IterAI", targets: ["IterAI"]),
        .library(name: "IterDiscovery", targets: ["IterDiscovery"]),
        .library(name: "IterConditions", targets: ["IterConditions"]),
        .library(name: "IterGo", targets: ["IterGo"]),
        .library(name: "IterGoActivity", targets: ["IterGoActivity"]),
        .library(name: "IterSync", targets: ["IterSync"]),
        .library(name: "IterUI", targets: ["IterUI"]),
        .library(name: "IterFeatures", targets: ["IterFeatures"]),
        .library(name: "IterScreens", targets: ["IterScreens"]),
        .executable(name: "iter-tokens", targets: ["IterTokensTool"]),
    ],
    targets: [
        // Pure value types: places, trips, stops, provenance, weather fields, discovery candidates. Foundation only.
        .target(name: "IterModel", swiftSettings: strict),
        // Sun, moon and galactic-centre positions and events. Pure.
        .target(name: "IterAstro", dependencies: ["IterModel"], swiftSettings: strict),
        // Light-window geometry, the Forecast and Live Sky Index, confidence and staleness. Pure.
        .target(name: "IterSky", dependencies: ["IterModel", "IterAstro"], swiftSettings: strict),
        // Scheduler v2, live schedule, day layout and builder rows. Pure.
        .target(name: "IterPlan", dependencies: ["IterModel", "IterSky"], swiftSettings: strict),
        // SwiftData: frozen V1 to V4, V5, the migration plan, store location, backup before migration, repositories,
        // the .iter documents and the curated catalogue.
        .target(name: "IterStore", dependencies: ["IterModel"], resources: [.process("Resources")], swiftSettings: strict),
        // Provider protocols, registry, cache, HTTP, rate limiting and the Keychain key vault. No concrete adapters.
        .target(name: "IterSources", dependencies: ["IterModel"], swiftSettings: strict),
        // Concrete adapters (MapKit and the confirmed feeds), each with a pure Mapping.
        .target(name: "IterSourcesLive", dependencies: ["IterModel", "IterSources"], swiftSettings: strict),
        // Foundation Models behind a fakeable protocol, weak-linked in one place.
        .target(name: "IterAI", dependencies: ["IterModel"], swiftSettings: strict),
        // The Find pipeline: query plan, area, fan-out, extraction, verification, merge, rank, citations.
        .target(name: "IterDiscovery", dependencies: ["IterModel", "IterSources", "IterAI"], swiftSettings: strict),
        // Composite forecasts with per-field provenance, observations, nowcast, sky inputs, offline packs.
        .target(name: "IterConditions", dependencies: ["IterModel", "IterSources", "IterSky", "IterAstro"], swiftSettings: strict),
        // The trip-mode engine: run state machine, live location, ETA refresh, notification plan, Go snapshot.
        .target(name: "IterGo", dependencies: ["IterModel", "IterPlan", "IterConditions", "IterSources"], swiftSettings: strict),
        // ActivityKit attributes and content state shared by the iOS app and the widget extension. iOS only in effect.
        .target(name: "IterGoActivity", dependencies: ["IterModel"], swiftSettings: strict),
        // .iter v2 merge and Bonjour peer sync.
        .target(name: "IterSync", dependencies: ["IterModel", "IterStore"], swiftSettings: strict),
        // Tokens, colours, fonts, the score ramp and the Figma components. SwiftUI.
        .target(name: "IterUI", dependencies: ["IterModel"], swiftSettings: strict),
        // One @MainActor @Observable model per stage, plus the composition root. Not IterUI.
        .target(name: "IterFeatures", dependencies: [
            "IterModel", "IterAstro", "IterSky", "IterPlan", "IterStore", "IterSources", "IterSourcesLive",
            "IterAI", "IterDiscovery", "IterConditions", "IterGo", "IterSync",
        ], swiftSettings: strict),
        // Shared SwiftUI screens and sections the platform shells compose.
        .target(name: "IterScreens", dependencies: ["IterFeatures", "IterUI"], swiftSettings: strict),
        // Exports and imports Design/tokens.json and the asset-catalogue colours.
        .executableTarget(name: "IterTokensTool", dependencies: ["IterUI"], swiftSettings: strict),

        .testTarget(name: "IterModelTests", dependencies: ["IterModel"], swiftSettings: strict),
        .testTarget(name: "IterAstroTests", dependencies: ["IterAstro"], swiftSettings: strict),
        .testTarget(name: "IterSkyTests", dependencies: ["IterSky"], swiftSettings: strict),
        .testTarget(name: "IterPlanTests", dependencies: ["IterPlan"], swiftSettings: strict),
        .testTarget(name: "IterStoreTests", dependencies: ["IterStore", "IterModel"], resources: [.copy("Fixtures")],
                    swiftSettings: strict),
        .testTarget(name: "IterSourcesTests", dependencies: ["IterSources", "IterModel"], swiftSettings: strict),
        .testTarget(name: "IterSourcesLiveTests", dependencies: ["IterSourcesLive"], resources: [.copy("Fixtures")],
                    swiftSettings: strict),
        .testTarget(name: "IterAITests", dependencies: ["IterAI"], swiftSettings: strict),
        .testTarget(name: "IterDiscoveryTests", dependencies: ["IterDiscovery"], swiftSettings: strict),
        .testTarget(name: "IterConditionsTests", dependencies: ["IterConditions"], swiftSettings: strict),
        .testTarget(name: "IterGoTests", dependencies: ["IterGo"], swiftSettings: strict),
        .testTarget(name: "IterGoActivityTests", dependencies: ["IterGoActivity"], swiftSettings: strict),
        .testTarget(name: "IterSyncTests", dependencies: ["IterSync"], swiftSettings: strict),
        .testTarget(name: "IterUITests", dependencies: ["IterUI"], swiftSettings: strict),
        .testTarget(name: "IterFeaturesTests", dependencies: ["IterFeatures"], swiftSettings: strict),
        .testTarget(name: "IterScreensTests", dependencies: ["IterScreens"], swiftSettings: strict),
    ]
)
