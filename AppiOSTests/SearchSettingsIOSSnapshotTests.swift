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

private struct SSSearch: PlaceSearching {
    func search(_ query: String, near region: GeoRegion?) async throws -> [PlaceResult] { [] }
    func pointsOfInterest(near center: Coordinate, radiusMeters: Double, categories: [String]) async throws -> [PlaceResult] { [] }
}

private struct SSGeocoder: Geocoding {
    func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult {
        PlaceResult(id: "stub", name: "Dropped pin", locality: "", coordinate: coordinate, timeZoneIdentifier: "America/Denver", pointOfInterestCategory: nil)
    }
    func geocode(_ query: String) async throws -> [PlaceResult] { [] }
}

private struct SSDrives: DriveTimeProviding {
    func drive(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg { DriveLeg.estimate(from: a, to: b) }
}

private let ssSnapshotsEnabled = ProcessInfo.processInfo.environment["ITER_SNAPSHOTS"] == "1"

/// Settings ▸ Search on iPhone, offscreen, light and dark, with a sample "what I like to shoot" filled in. In-memory
/// defaults and key store: nothing touches the real settings or the Keychain.
@MainActor @Suite(.serialized) struct SearchSettingsIOSSnapshotTests {
    private static var outputDirectory: URL {
        if let dir = ProcessInfo.processInfo.environment["ITER_SNAPSHOT_DIR"], !dir.isEmpty { return URL(fileURLWithPath: dir, isDirectory: true) }
        return FileManager.default.temporaryDirectory.appendingPathComponent("IterSnapshots-iOS", isDirectory: true)
    }

    private func makeModel() -> AppModel {
        let store = IterStore(container: try! IterSchema.makeContainer(inMemory: true))
        let defaults = UserDefaults(suiteName: "IterSearchSettingsIOS-\(UUID().uuidString)")!
        let now = Date()
        let clock: @Sendable () -> Date = { now }
        let sample = CachedWeatherService(wrapping: SampleWeatherService(now: clock))
        let model = AppModel(store: store, weather: sample, search: SSSearch(), geocoder: SSGeocoder(), drives: SSDrives(),
                             scout: nil, location: UserLocationModel(), sampleWeather: sample, defaults: defaults, now: { now })
        model.searchSettings.promptPrefix = "Quiet alpine lakes at sunrise, long-exposure waterfalls, no crowds"
        model.searchSettings.preference = .unique
        model.searchSettings.setEnabled(.reddit, false)
        return model
    }

    @Test func settingsModelDefaultsAreHonest() {
        let model = makeModel()
        #expect(model.searchSettings.isEnabled(.appleMaps))
        #expect(!model.searchSettings.hasGoogleKey)
        #expect(SearchSettingsText.freeSources == [.reddit, .wikipedia, .wikivoyage, .openStreetMap])
    }

    @Test(.enabled(if: ssSnapshotsEnabled)) func searchSettings() async throws {
        let model = makeModel()
        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)
        for (scheme, style) in [("light", UIUserInterfaceStyle.light), ("dark", .dark)] {
            let root = NavigationStack {
                SearchSettingsPane().navigationTitle("Search").navigationBarTitleDisplayMode(.inline)
            }
            .environment(model)
            .frame(width: 402)
            let host = UIHostingController(rootView: root)
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
            window.frame = CGRect(x: 0, y: 0, width: 402, height: 2400)
            window.overrideUserInterfaceStyle = style
            window.rootViewController = host
            window.isHidden = false
            try await Task.sleep(for: .seconds(2))
            host.view.layoutIfNeeded()
            var best: UIScrollView?
            func walk(_ v: UIView) {
                if let s = v as? UIScrollView, s.contentSize.height > (best?.contentSize.height ?? 0) { best = s }
                v.subviews.forEach(walk)
            }
            walk(host.view)
            if let scroll = best {
                let total = (scroll.adjustedContentInset.top + scroll.contentSize.height + scroll.adjustedContentInset.bottom).rounded(.up)
                if total < 2400 {
                    window.frame = CGRect(x: 0, y: 0, width: 402, height: max(total, 874))
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
            try png.write(to: Self.outputDirectory.appendingPathComponent("ios-settings-search-\(scheme).png"))
        }
    }
}
