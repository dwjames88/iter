import Testing
import Foundation
import SwiftUI
import UIKit
import TipKit
import IterCore
import IterData
import IterServices
import IterFeatures
@testable import Iter

private struct PDSearch: PlaceSearching {
    func search(_ query: String, near region: GeoRegion?) async throws -> [PlaceResult] { [] }
    func pointsOfInterest(near center: Coordinate, radiusMeters: Double, categories: [String]) async throws -> [PlaceResult] { [] }
}

private struct PDGeocoder: Geocoding {
    func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult {
        PlaceResult(id: "stub", name: "Dropped pin", locality: "Near Bishop, CA", coordinate: coordinate,
                    timeZoneIdentifier: "America/Los_Angeles", pointOfInterestCategory: nil)
    }
    func geocode(_ query: String) async throws -> [PlaceResult] { [] }
}

private struct PDDrives: DriveTimeProviding {
    func drive(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg { DriveLeg.estimate(from: a, to: b) }
}

private let pdNow = LocalDay(year: 2026, month: 10, day: 6).at(hour: 10, in: TimeZone(identifier: "America/Los_Angeles")!)
private let pdEnabled = ProcessInfo.processInfo.environment["ITER_SNAPSHOTS"] == "1"

/// Moving your own spot on the phone: the place card with its tip and Adjust tile, the Edit Location sheet with its pin map,
/// and a pin lifted mid-drag on the map stand-in. Only with `ITER_SNAPSHOTS=1`; files go to `ITER_SNAPSHOT_DIR` as
/// `ios-spot-pin-drag-<name>-<light|dark>.png`.
@MainActor @Suite(.serialized) struct SpotPinDragIOSSnapshotTests {
    private static var outputDirectory: URL {
        if let dir = ProcessInfo.processInfo.environment["ITER_SNAPSHOT_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("IterSnapshots-iOS", isDirectory: true)
    }

    /// The tip only draws once TipKit is configured, and the app never configures under a test run. A snapshot that asks for
    /// the tip does it here, once, with a throwaway datastore and nothing else showing.
    private static let tipsConfigured: Bool = {
        let store = FileManager.default.temporaryDirectory.appendingPathComponent("IterSnapshotTips-\(UUID().uuidString)", isDirectory: true)
        try? Tips.resetDatastore()
        return (try? Tips.configure([.datastoreLocation(.url(store))])) != nil
    }()

    private func model() -> AppModel {
        let store = IterStore(container: try! IterSchema.makeContainer(inMemory: true))
        let defaults = UserDefaults(suiteName: "IterPinDragIOS-\(UUID().uuidString)")!
        defaults.set(true, forKey: AppModel.sampleDataKey)
        let clock: @Sendable () -> Date = { pdNow }
        let sample = CachedWeatherService(wrapping: SampleWeatherService(now: clock))
        return AppModel(store: store, weather: sample, search: PDSearch(), geocoder: PDGeocoder(), drives: PDDrives(),
                        scout: nil, discovery: StubDiscovery(), location: UserLocationModel(), sampleWeather: sample,
                        defaults: defaults, now: { pdNow })
    }

    private func ownSpot(_ model: AppModel) -> PlaceRecord {
        model.store.createUserSpot(name: "Secret Pond", locality: "Near Bishop, CA", coordinate: Coordinate(latitude: 37.3612, longitude: -118.3951),
                                   timeZoneIdentifier: "America/Los_Angeles", category: .landscape, bestLight: [.sunrise, .blueHour],
                                   notes: "Gate code on the sign.", walkInMinutes: 15)
    }

    private func render<Content: View>(_ name: String, height: CGFloat, settle: Duration = .seconds(3), @ViewBuilder content: () -> Content) async throws {
        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)
        let view = content()
        for (scheme, style) in [("light", UIUserInterfaceStyle.light), ("dark", .dark)] {
            let host = UIHostingController(rootView: AnyView(view.frame(width: 402, height: height)))
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
            window.frame = CGRect(x: 0, y: 0, width: 402, height: height)
            window.overrideUserInterfaceStyle = style
            window.rootViewController = host
            window.isHidden = false
            try await Task.sleep(for: settle)
            host.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
                host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            window.isHidden = true
            guard let png = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: Self.outputDirectory.appendingPathComponent("ios-spot-pin-drag-\(name)-\(scheme).png"))
        }
    }

    /// (a) The place card of your own spot: the tip, then the Adjust tile among the actions.
    @Test(.enabled(if: pdEnabled)) func placeDetailWithTip() async throws {
        _ = Self.tipsConfigured
        let model = model()
        let record = ownSpot(model)
        let explore = ExploreModel(app: model, searchDebounce: .zero, defaults: UserDefaults(suiteName: "IterPinDragIOSExplore-\(UUID().uuidString)")!)
        explore.didCreate(record.spot)
        let row = try #require(explore.row(id: record.spot.id))
        #expect(explore.canMove(record.spot.id))
        try await render("detail", height: 874) {
            NavigationStack { ExplorePlaceDetail(explore: explore, row: row, usesNavigationBar: true) }
                .environment(model)
                .environment(explore)
                .environment(AppNavigation())
                .environment(ShellState())
                .environment(\.renderMode, .snapshot)
                .environment(\.showsMoveSpotTip, true)
                .modelContainer(model.store.container)
        }
    }

    /// (b) Edit Location with the pin map (the static stand-in in a snapshot), the coordinate fields under it.
    @Test(.enabled(if: pdEnabled)) func editLocationPinMap() async throws {
        let model = model()
        let record = ownSpot(model)
        try await render("edit-location", height: 1100, settle: .seconds(2)) {
            PlaceEditorSheet(record: record)
                .environment(model)
                .environment(AppNavigation())
                .environment(\.renderMode, .snapshot)
                .modelContainer(model.store.container)
        }
    }

    /// (c) The pin lifted while it is carried, on the map stand-in: up a little, a shadow, and the tip dot at the coordinate.
    @Test(.enabled(if: pdEnabled)) func liftedPin() async throws {
        let model = model()
        let record = ownSpot(model)
        let explore = ExploreModel(app: model, searchDebounce: .zero, defaults: UserDefaults(suiteName: "IterPinDragIOSDrag-\(UUID().uuidString)")!)
        explore.didCreate(record.spot)
        #expect(explore.beginDrag(record.spot.id))
        explore.drag(to: Coordinate(latitude: 37.3640, longitude: -118.3920))
        try await render("lifted", height: 874, settle: .seconds(2)) {
            ExploreMapLayer(explore: explore)
                .environment(model)
                .environment(explore)
                .environment(AppNavigation())
                .environment(\.renderMode, .snapshot)
                .modelContainer(model.store.container)
        }
        explore.endDrag(commit: false)
    }
}
