import Testing
import Foundation
import SwiftUI
import UIKit
import SwiftData
import IterCore
import IterData
import IterDesign
import IterServices
import IterFeatures
@testable import Iter

// Explore's Search Here and feature search on the iPhone: the button, the progress states, the In View section with its
// sources, and a typed "peaks in Glacier National Park". Everything is scripted (search, Ask, Discovery), so the renders
// are the same every run and need no network.

private let shNow = LocalDay(year: 2026, month: 10, day: 6).at(hour: 10, in: TimeZone(identifier: "America/Denver")!)
private let shSnapshotsEnabled = ProcessInfo.processInfo.environment["ITER_SNAPSHOTS"] == "1"
private let denver = "America/Denver"

/// The map as someone near Logan Pass would leave it.
private let shRegion = GeoRegion(center: Coordinate(latitude: 48.72, longitude: -113.74), latitudeDelta: 0.35, longitudeDelta: 0.45)

private func place(_ id: String, _ name: String, _ lat: Double, _ lon: Double, locality: String = "Glacier National Park, MT") -> PlaceResult {
    PlaceResult(id: id, name: name, locality: locality, coordinate: Coordinate(latitude: lat, longitude: lon),
                timeZoneIdentifier: denver, pointOfInterestCategory: nil)
}

private let avalanche = place("sh-avalanche", "Avalanche Lake", 48.6788, -113.8183)
private let cedars = place("sh-cedars", "Trail of the Cedars", 48.6800, -113.8400)
private let hiddenLake = place("sh-hidden", "Hidden Lake Overlook", 48.6955, -113.7180)
private let mcdonald = place("sh-mcdonald", "Lake McDonald", 48.5985, -113.9150)
private let birdWoman = place("sh-birdwoman", "Bird Woman Falls Overlook", 48.7080, -113.7600)
private let jackson = place("sh-jackson", "Jackson Glacier Overlook", 48.6870, -113.6700)
private let cleveland = place("sh-cleveland", "Mount Cleveland", 48.9297, -113.8478)
private let gould = place("sh-gould", "Mount Gould", 48.7664, -113.7177)

private struct SHSearch: PlaceSearching {
    enum Hang { case none, maps }
    var hang = Hang.none
    var known: [PlaceResult] = [avalanche, cedars, hiddenLake, mcdonald, birdWoman, jackson, cleveland, gould]

    func search(_ query: String, near region: GeoRegion?) async throws -> [PlaceResult] {
        if hang == .maps { try await Task.sleep(for: .seconds(120)) }
        let q = query.lowercased()
        if let exact = known.first(where: { $0.name.lowercased() == q }) { return [exact] }
        switch q {
        case "viewpoint": return [hiddenLake, jackson]
        case "lake": return [avalanche, mcdonald]
        case "waterfall": return []
        default: return q.contains(" in ") ? [cleveland, gould] : []
        }
    }

    func pointsOfInterest(near center: Coordinate, radiusMeters: Double, categories: [String]) async throws -> [PlaceResult] {
        if hang == .maps { try await Task.sleep(for: .seconds(120)) }
        return [cedars]
    }
}

private struct SHGeocoder: Geocoding {
    func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult {
        PlaceResult(id: "stub", name: "Dropped pin", locality: "West Glacier, MT", coordinate: coordinate,
                    timeZoneIdentifier: denver, pointOfInterestCategory: nil)
    }
    func geocode(_ query: String) async throws -> [PlaceResult] { [] }
}

private struct SHDrives: DriveTimeProviding {
    func drive(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg { DriveLeg.estimate(from: a, to: b) }
}

private struct SHScout: Scouting {
    var state: ScoutAvailability = .available
    var hangs = false

    func availability() -> ScoutAvailability { state }
    func scout(_ request: String, progress: @escaping @Sendable (ScoutProgress) -> Void) async throws -> [ScoutSuggestion] { [] }
    func proposePlaces(in region: GeoRegion, areaName: String?) async throws -> [RegionProposal] {
        if hangs { try await Task.sleep(for: .seconds(120)) }
        return [
            RegionProposal(name: "Bird Woman Falls Overlook", why: "A long fall seen across the valley, lit from the west at sunset."),
            RegionProposal(name: "Jackson Glacier Overlook", why: "Open view of the glacier with room for a long lens."),
            RegionProposal(name: "Hidden Lake Overlook", why: "A short boardwalk to a lake under the peaks."),
        ]
    }
}

@MainActor private func makeSearchHereModel(search: SHSearch = SHSearch(), scout: SHScout? = SHScout(), prefix: String? = nil) -> AppModel {
    let store = IterStore(container: try! IterSchema.makeContainer(inMemory: true))
    let defaults = UserDefaults(suiteName: "IterSearchHereIOS-\(UUID().uuidString)")!
    defaults.set(true, forKey: AppModel.sampleDataKey)
    if let prefix { defaults.set(prefix, forKey: SearchSettingsModel.promptPrefixKey) }
    let clock: @Sendable () -> Date = { shNow }
    let sample = CachedWeatherService(wrapping: SampleWeatherService(now: clock))
    return AppModel(store: store, weather: sample, search: search, geocoder: SHGeocoder(), drives: SHDrives(),
                    scout: scout, discovery: StubDiscovery(), location: UserLocationModel(), sampleWeather: sample,
                    defaults: defaults, now: { shNow })
}

/// The Explore sheet content on an iPhone 17 Pro (402 x 874 pt, 3x), offscreen, light and dark. Only with `ITER_SNAPSHOTS=1`; files
/// go to `ITER_SNAPSHOT_DIR` as `ios-explore-<name>-<light|dark>.png`.
@MainActor @Suite(.serialized) struct ExploreSearchHereIOSSnapshotTests {
    private static let width: CGFloat = 402
    private static let height: CGFloat = 874

    private static var outputDirectory: URL {
        if let dir = ProcessInfo.processInfo.environment["ITER_SNAPSHOT_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("IterSnapshots-iOS", isDirectory: true)
    }

    private func render(_ name: String, model: AppModel, explore: ExploreModel, settle: Duration = .seconds(3)) async throws {
        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)
        for (scheme, style) in [("light", UIUserInterfaceStyle.light), ("dark", .dark)] {
            let root = NavigationStack {
                ExploreBrowser(explore: explore, usesNavigationBar: true)
                    .navigationTitle(String(localized: "Explore", comment: "Explore sheet title"))
                    .navigationBarTitleDisplayMode(.large)
            }
            .environment(model)
            .environment(explore)
            .environment(AppNavigation())
            .environment(ShellState())
            .modelContainer(model.store.container)
            .frame(width: Self.width, height: Self.height)
            let host = UIHostingController(rootView: root)
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
            window.frame = CGRect(x: 0, y: 0, width: Self.width, height: Self.height)
            window.overrideUserInterfaceStyle = style
            window.rootViewController = host
            window.isHidden = false
            try await Task.sleep(for: settle)
            host.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 3
            let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
                host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            window.isHidden = true
            guard let png = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: Self.outputDirectory.appendingPathComponent("ios-\(name)-\(scheme).png"))
        }
    }

    /// The map has been moved by hand, so the list no longer describes it.
    private func movedExplore(_ model: AppModel) -> ExploreModel {
        let explore = ExploreModel(app: model, searchDebounce: .zero, defaults: UserDefaults(suiteName: "IterSearchHereIOSCamera-\(UUID().uuidString)")!)
        explore.cameraDidChange(to: shRegion, byUser: true)
        return explore
    }

    private func wait(until condition: () -> Bool) async throws {
        for _ in 0..<200 where !condition() { try await Task.sleep(for: .milliseconds(50)) }
    }

    @Test(.enabled(if: shSnapshotsEnabled)) func buttonVisible() async throws {
        let model = makeSearchHereModel()
        let explore = movedExplore(model)
        #expect(explore.showsSearchHere)
        try await render("explore-search-here-visible", model: model, explore: explore)
    }

    @Test(.enabled(if: shSnapshotsEnabled)) func searchingMaps() async throws {
        let model = makeSearchHereModel(search: SHSearch(hang: .maps))
        let explore = movedExplore(model)
        explore.searchHere()
        try await Task.sleep(for: .milliseconds(300))
        #expect(explore.searchHereStatus.phase == .searchingMaps)
        try await render("explore-search-here-loading", model: model, explore: explore)
        explore.cancelSearchHere()
    }

    @Test(.enabled(if: shSnapshotsEnabled)) func asking() async throws {
        let model = makeSearchHereModel(scout: SHScout(hangs: true))
        let explore = movedExplore(model)
        explore.searchHere()
        try await wait { explore.searchHereStatus.phase == .asking && !explore.searchHereResults.isEmpty }
        #expect(explore.searchHereStatus.phase == .asking)
        try await render("explore-search-here-asking", model: model, explore: explore)
        explore.cancelSearchHere()
    }

    @Test(.enabled(if: shSnapshotsEnabled)) func results() async throws {
        let model = makeSearchHereModel()
        let explore = movedExplore(model)
        explore.searchHere()
        try await wait { explore.searchHereStatus.phase == .finished }
        #expect(explore.searchHereStatus.phase == .finished)
        #expect(explore.sections.first?.kind == .inView)
        try await render("explore-search-here-results", model: model, explore: explore)
    }

    /// Ask cannot run on this device: the section says so quietly, and Maps and the web sources still answer.
    @Test(.enabled(if: shSnapshotsEnabled)) func askUnavailable() async throws {
        let model = makeSearchHereModel(scout: SHScout(state: .appleIntelligenceNotEnabled))
        let explore = movedExplore(model)
        explore.searchHere()
        try await wait { explore.searchHereStatus.phase == .finished }
        try await render("explore-search-here-ask-off", model: model, explore: explore)
    }

    @Test(.enabled(if: shSnapshotsEnabled)) func featureResults() async throws {
        let model = makeSearchHereModel()
        let explore = movedExplore(model)
        explore.query = "peaks in Glacier National Park"
        explore.searchAppleMaps()
        await explore.searchTask?.value
        #expect(explore.sections.contains { $0.kind == .feature })
        try await render("explore-feature-results", model: model, explore: explore)
    }

    /// The Ask suggestion says the person's shooting notes are applied.
    @Test(.enabled(if: shSnapshotsEnabled)) func promptPrefixNote() async throws {
        let model = makeSearchHereModel(prefix: "I shoot landscapes at first light with a 70-200 and like quiet places")
        let explore = movedExplore(model)
        explore.query = "foggy forest for sunrise"
        try await render("explore-search-prefix", model: model, explore: explore, settle: .seconds(2))
    }
}
