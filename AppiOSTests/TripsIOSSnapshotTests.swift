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

private struct TSSearch: PlaceSearching {
    func search(_ query: String, near region: GeoRegion?) async throws -> [PlaceResult] { [] }
    func pointsOfInterest(near center: Coordinate, radiusMeters: Double, categories: [String]) async throws -> [PlaceResult] { [] }
}

private struct TSGeocoder: Geocoding {
    func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult {
        PlaceResult(id: "stub", name: "Dropped pin", locality: "Moab, UT", coordinate: coordinate,
                    timeZoneIdentifier: "America/Denver", pointOfInterestCategory: nil)
    }
    func geocode(_ query: String) async throws -> [PlaceResult] { [] }
}

private struct TSDrives: DriveTimeProviding {
    func drive(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg { DriveLeg.estimate(from: a, to: b) }
}

private let tsNow = LocalDay(year: 2026, month: 10, day: 6).at(hour: 10, in: TimeZone(identifier: "America/Denver")!)
private let tripsSnapshotsEnabled = ProcessInfo.processInfo.environment["ITER_SNAPSHOTS"] == "1"

@MainActor private func makeTripsModel() -> AppModel {
    let store = IterStore(container: try! IterSchema.makeContainer(inMemory: true))
    let defaults = UserDefaults(suiteName: "IterTripsIOS-\(UUID().uuidString)")!
    defaults.set(true, forKey: AppModel.sampleDataKey)
    let clock: @Sendable () -> Date = { tsNow }
    let sample = CachedWeatherService(wrapping: SampleWeatherService(now: clock))
    return AppModel(store: store, weather: sample, search: TSSearch(), geocoder: TSGeocoder(), drives: TSDrives(),
                    scout: nil, location: UserLocationModel(), sampleWeather: sample, defaults: defaults, now: { tsNow })
}

/// The trips library: the sample trip (the hero), a folder with a trip in it, an empty folder, a pinned trip, an unfiled one.
@MainActor private func seedTrips(_ model: AppModel) {
    let store = model.store
    let tomorrow = model.today(in: .current).adding(days: 1)
    store.seedSampleTrip(startDay: tomorrow)
    let utah = store.createFolder(name: "Utah 2027", kind: .trips)
    store.createFolder(name: "Idea Box", kind: .trips)
    if let canyon = TripTemplates.template(id: "canyon-country") {
        let trip = store.createTrip(from: canyon, startDay: tomorrow.adding(days: 30))
        store.renameTrip(trip, to: "Canyon Country in Spring")
        store.moveTrips([trip], to: utah, index: nil)
    }
    let moab = store.createTrip(name: "Moab Recon", startDay: tomorrow.adding(days: 20), dayCount: 2)
    store.setPinned(moab, true)
    store.createTrip(name: "Weekend Away", startDay: tomorrow.adding(days: 9), dayCount: 2)
}

/// Saved spots in two folders (one pinned), one unfiled.
@MainActor private func seedLocations(_ model: AppModel) {
    let store = model.store
    let coast = store.createFolder(name: "Coast", kind: .locations)
    let desert = store.createFolder(name: "Desert", kind: .locations)
    func file(_ ids: [String], in folder: FolderRecord) {
        for id in ids { if let spot = CuratedSpots.spot(id: id) { store.setSaved(spot, true) } }
        store.movePlaces(store.savedPlaces().filter { $0.curatedID.map(ids.contains) ?? false }, to: folder, index: nil)
    }
    file(["haystack-rock", "bixby-bridge", "point-reyes-lighthouse"], in: coast)
    file(["mesa-arch", "delicate-arch"], in: desert)
    if let spot = CuratedSpots.spot(id: "tunnel-view") { store.setSaved(spot, true) }
    store.setPinned(desert, true)
}

/// All Trips and Locations on the device the suite runs on (iPhone 402 pt or iPad 834 pt wide, 3x), offscreen, light and dark.
/// Only with `ITER_SNAPSHOTS=1`; files go to `ITER_SNAPSHOT_DIR` as `ios-<name>-<iphone|ipad>-<scheme>.png`.
@MainActor @Suite(.serialized) struct TripsIOSSnapshotTests {
    private static var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private static var width: CGFloat { isPad ? 834 : 402 }
    private static var viewport: CGFloat { isPad ? 1194 : 874 }

    private static var outputDirectory: URL {
        if let dir = ProcessInfo.processInfo.environment["ITER_SNAPSHOT_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("IterSnapshots-iOS", isDirectory: true)
    }

    private static func tallestScroll(in view: UIView) -> UIScrollView? {
        var best: UIScrollView?
        func walk(_ v: UIView) {
            if let s = v as? UIScrollView, s.contentSize.height > (best?.contentSize.height ?? 0) { best = s }
            v.subviews.forEach(walk)
        }
        walk(view)
        return best
    }

    /// `fitContent`: the window is as tall as the page's scroll content (up to 2600 pt), else one screen.
    private func render<V: View>(_ name: String, model: AppModel, fitContent: Bool, settle: Duration = .seconds(3),
                                 @ViewBuilder _ content: () -> V) async throws {
        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)
        let device = Self.isPad ? "ipad" : "iphone"
        for (scheme, style) in [("light", UIUserInterfaceStyle.light), ("dark", .dark)] {
            let root = content()
                .environment(model)
                .environment(ExploreModel(app: model))
                .environment(AppNavigation())
                .environment(ShellState())
                .modelContainer(model.store.container)
                .frame(width: Self.width)
            let host = UIHostingController(rootView: root)
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
            window.frame = CGRect(x: 0, y: 0, width: Self.width, height: fitContent ? 2600 : Self.viewport)
            window.overrideUserInterfaceStyle = style
            window.rootViewController = host
            window.isHidden = false
            try await Task.sleep(for: settle)
            host.view.layoutIfNeeded()
            if fitContent, let scroll = Self.tallestScroll(in: host.view) {
                let top = scroll.convert(CGPoint.zero, to: host.view).y
                let total = (top + scroll.adjustedContentInset.top + scroll.contentSize.height + scroll.adjustedContentInset.bottom).rounded(.up)
                if total < 2600 {
                    window.frame = CGRect(x: 0, y: 0, width: Self.width, height: max(total, Self.viewport))
                    host.view.frame = window.bounds
                    host.view.layoutIfNeeded()
                    try await Task.sleep(for: .milliseconds(800))
                }
            }
            let format = UIGraphicsImageRendererFormat()
            format.scale = 3
            let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
                host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            window.isHidden = true
            guard let png = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: Self.outputDirectory.appendingPathComponent("ios-\(name)-\(device)-\(scheme).png"))
        }
    }

    @Test(.enabled(if: tripsSnapshotsEnabled)) func allTrips() async throws {
        let model = makeTripsModel()
        seedTrips(model)
        try await render("trips-all", model: model, fitContent: true) { NavigationStack { TripsListScreen() } }
    }

    @Test(.enabled(if: tripsSnapshotsEnabled)) func allTripsEmpty() async throws {
        try await render("trips-empty", model: makeTripsModel(), fitContent: false) { NavigationStack { TripsListScreen() } }
    }

    @Test(.enabled(if: tripsSnapshotsEnabled)) func locationsWithFolders() async throws {
        let model = makeTripsModel()
        seedLocations(model)
        // The map's tiles arrive at their own pace; hide it so the page is the same every run and shows more rows.
        UserDefaults.standard.set(false, forKey: "IterLocationsMapShown")
        defer { UserDefaults.standard.removeObject(forKey: "IterLocationsMapShown") }
        try await render("locations-folders", model: model, fitContent: false) { NavigationStack { LocationsScreen(folderID: nil) } }
    }

    @Test(.enabled(if: tripsSnapshotsEnabled)) func locationsInsideAFolder() async throws {
        let model = makeTripsModel()
        seedLocations(model)
        let desert = model.store.folders(kind: .locations).first { $0.name == "Desert" }
        try await render("locations-folder-desert", model: model, fitContent: false) { NavigationStack { LocationsScreen(folderID: desert?.id) } }
    }
}
