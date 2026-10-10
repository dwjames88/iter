import Testing
import Foundation
import SwiftUI
import UIKit
import IterCore
import IterData
import IterServices
import IterFeatures
@testable import Iter

private struct PLSearch: PlaceSearching {
    func search(_ query: String, near region: GeoRegion?) async throws -> [PlaceResult] { [] }
    func pointsOfInterest(near center: Coordinate, radiusMeters: Double, categories: [String]) async throws -> [PlaceResult] { [] }
}

private struct PLGeocoder: Geocoding {
    func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult {
        PlaceResult(id: "stub", name: "Dropped pin", locality: "Near Bishop, CA", coordinate: coordinate,
                    timeZoneIdentifier: "America/Los_Angeles", pointOfInterestCategory: nil)
    }
    func geocode(_ query: String) async throws -> [PlaceResult] { [] }
}

private struct PLDrives: DriveTimeProviding {
    func drive(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg { DriveLeg.estimate(from: a, to: b) }
}

private let plNow = LocalDay(year: 2026, month: 10, day: 6).at(hour: 10, in: TimeZone(identifier: "America/Los_Angeles")!)
private let plEnabled = ProcessInfo.processInfo.environment["ITER_SNAPSHOTS"] == "1"

/// The Locations map on the phone with one of your own pins lifted mid-drag (up, a shadow, the tip dot at the coordinate).
/// Only with `ITER_SNAPSHOTS=1`; files go to `ITER_SNAPSHOT_DIR` as `ios-locations-pin-drag-<light|dark>.png`.
@MainActor @Suite(.serialized) struct LocationsPinDragIOSSnapshotTests {
    private static var outputDirectory: URL {
        if let dir = ProcessInfo.processInfo.environment["ITER_SNAPSHOT_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("IterSnapshots-iOS", isDirectory: true)
    }

    private func model() -> AppModel {
        let store = IterStore(container: try! IterSchema.makeContainer(inMemory: true))
        let defaults = UserDefaults(suiteName: "IterLocationsPinDragIOS-\(UUID().uuidString)")!
        defaults.set(true, forKey: AppModel.sampleDataKey)
        let clock: @Sendable () -> Date = { plNow }
        let sample = CachedWeatherService(wrapping: SampleWeatherService(now: clock))
        return AppModel(store: store, weather: sample, search: PLSearch(), geocoder: PLGeocoder(), drives: PLDrives(),
                        scout: nil, discovery: StubDiscovery(), location: UserLocationModel(), sampleWeather: sample,
                        defaults: defaults, now: { plNow })
    }

    /// The touch rules are shared values, and a pin of yours stands on its tip like Explore's.
    @Test func theTouchRulesAndTheTipAnchor() {
        #expect(PinDrag.holdSeconds == 0.3)
        #expect(PinDrag.liftPoints == 5)
        #expect(MapPinAnchor.vertical(for: .chip) == 1, "an event unit's tip is the coordinate")
        #expect(MapPinAnchor.vertical(for: .dot) == 0.5, "a plain marker is centred")
    }

    @Test(.enabled(if: plEnabled)) func liftedPin() async throws {
        let model = model()
        let own = model.store.createUserSpot(name: "Secret Pond", locality: "Near Bishop, CA", coordinate: Coordinate(latitude: 37.3612, longitude: -118.3951),
                                             timeZoneIdentifier: "America/Los_Angeles", category: .landscape, bestLight: [.sunrise, .blueHour],
                                             notes: "", walkInMinutes: 15)
        let own2 = model.store.createUserSpot(name: "Gravel Pit", locality: "Near Bishop, CA", coordinate: Coordinate(latitude: 37.2800, longitude: -118.5200),
                                              timeZoneIdentifier: "America/Los_Angeles")
        let own3 = model.store.createUserSpot(name: "Lone Pine Gate", locality: "Near Lone Pine, CA", coordinate: Coordinate(latitude: 37.4300, longitude: -118.5000),
                                              timeZoneIdentifier: "America/Los_Angeles")
        for spot in [own.spot, own2.spot, own3.spot] { model.spotSaved(spot) }
        let items = model.store.savedPlaces().map { SavedItem(id: $0.id, spot: $0.spot, todayScore: nil) }
        let drag = OwnPinDragModel(app: model)
        #expect(drag.beginDrag(own.spot.id))
        drag.drag(to: Coordinate(latitude: 37.3550, longitude: -118.3300))
        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)
        let view = LocationsMapHeader(items: items, onOpen: { _ in }, preparedDrag: drag)
            .frame(width: 402, height: 520)
            .environment(model)
            .environment(\.renderMode, .snapshot)
            .modelContainer(model.store.container)
        for (scheme, style) in [("light", UIUserInterfaceStyle.light), ("dark", .dark)] {
            let host = UIHostingController(rootView: AnyView(view))
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
            window.frame = CGRect(x: 0, y: 0, width: 402, height: 520)
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
            try png.write(to: Self.outputDirectory.appendingPathComponent("ios-locations-pin-drag-\(scheme).png"))
        }
        drag.endDrag(commit: false)
    }
}
