import Testing
import Foundation
import SwiftUI
import UIKit
import SwiftData
import IterCore
import IterData
import IterServices
import IterFeatures
@testable import Iter

private struct LESearch: PlaceSearching {
    func search(_ query: String, near region: GeoRegion?) async throws -> [PlaceResult] { [] }
    func pointsOfInterest(near center: Coordinate, radiusMeters: Double, categories: [String]) async throws -> [PlaceResult] { [] }
}

private struct LEGeocoder: Geocoding {
    func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult {
        PlaceResult(id: "stub", name: "Dropped pin", locality: "Moab, UT", coordinate: coordinate,
                    timeZoneIdentifier: "America/Denver", pointOfInterestCategory: nil)
    }
    func geocode(_ query: String) async throws -> [PlaceResult] { [] }
}

private struct LEDrives: DriveTimeProviding {
    func drive(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg { DriveLeg.estimate(from: a, to: b) }
}

private let leNow = LocalDay(year: 2026, month: 10, day: 6).at(hour: 10, in: TimeZone(identifier: "America/Denver")!)
private let leEnabled = ProcessInfo.processInfo.environment["ITER_SNAPSHOTS"] == "1"

/// The Edit Location sheet on the phone: an own spot (every field), a saved catalogue spot (facts read-only, with the
/// reason), and an own spot with a bad coordinate. Only with `ITER_SNAPSHOTS=1`; files go to `ITER_SNAPSHOT_DIR`.
@MainActor @Suite(.serialized) struct LocationEditIOSSnapshotTests {
    private static var outputDirectory: URL {
        if let dir = ProcessInfo.processInfo.environment["ITER_SNAPSHOT_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("IterSnapshots-iOS", isDirectory: true)
    }

    private func model() -> AppModel {
        let store = IterStore(container: try! IterSchema.makeContainer(inMemory: true))
        let defaults = UserDefaults(suiteName: "IterLocationEditIOS-\(UUID().uuidString)")!
        let clock: @Sendable () -> Date = { leNow }
        let sample = CachedWeatherService(wrapping: SampleWeatherService(now: clock))
        return AppModel(store: store, weather: sample, search: LESearch(), geocoder: LEGeocoder(), drives: LEDrives(),
                        scout: nil, location: UserLocationModel(), sampleWeather: sample, defaults: defaults, now: { leNow })
    }

    private func render(_ name: String, model: AppModel, record: PlaceRecord) async throws {
        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)
        for (scheme, style) in [("light", UIUserInterfaceStyle.light), ("dark", .dark)] {
            let root = PlaceEditorSheet(record: record)
                .environment(model)
                .environment(AppNavigation())
                .modelContainer(model.store.container)
                .frame(width: 402)
            let host = UIHostingController(rootView: root)
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
            window.frame = CGRect(x: 0, y: 0, width: 402, height: 1500)
            window.overrideUserInterfaceStyle = style
            window.rootViewController = host
            window.isHidden = false
            try await Task.sleep(for: .seconds(2))
            host.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat()
            format.scale = 2
            let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
                host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            window.isHidden = true
            guard let png = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: Self.outputDirectory.appendingPathComponent("ios-\(name)-\(scheme).png"))
        }
    }

    @Test(.enabled(if: leEnabled)) func ownSpot() async throws {
        let model = model()
        let folder = model.store.createFolder(name: "Eastern Sierra", kind: .locations)
        let place = model.store.createUserSpot(name: "Secret Pond", locality: "Near Bishop, CA", coordinate: Coordinate(latitude: 37.3612, longitude: -118.3951),
                                               timeZoneIdentifier: "America/Los_Angeles", category: .landscape, bestLight: [.sunrise, .blueHour],
                                               notes: "Gate code on the sign. Park at the second pullout.", walkInMinutes: 15)
        model.store.movePlaces([place], to: folder, index: nil)
        try await render("location-edit", model: model, record: place)
    }

    @Test(.enabled(if: leEnabled)) func savedCatalogueSpot() async throws {
        let model = model()
        let spot = try #require(CuratedSpots.spot(id: "mesa-arch"))
        model.store.setSaved(spot, true)
        let record = try #require(model.store.editableRecord(for: spot))
        try await render("location-edit-catalogue", model: model, record: record)
    }
}
