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

private struct FPSearch: PlaceSearching {
    func search(_ query: String, near region: GeoRegion?) async throws -> [PlaceResult] { [] }
    func pointsOfInterest(near center: Coordinate, radiusMeters: Double, categories: [String]) async throws -> [PlaceResult] { [] }
}

private struct FPGeocoder: Geocoding {
    func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult {
        PlaceResult(id: "stub", name: "Dropped pin", locality: "Moab, UT", coordinate: coordinate,
                    timeZoneIdentifier: "America/Denver", pointOfInterestCategory: nil)
    }
    func geocode(_ query: String) async throws -> [PlaceResult] { [] }
}

private struct FPDrives: DriveTimeProviding {
    func drive(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg { DriveLeg.estimate(from: a, to: b) }
}

private let fpNow = LocalDay(year: 2026, month: 10, day: 6).at(hour: 10, in: TimeZone(identifier: "America/Denver")!)
private let fullPageEnabled = ProcessInfo.processInfo.environment["ITER_SNAPSHOTS"] == "1"

@MainActor private func makeSampleModel() -> AppModel {
    let store = IterStore(container: try! IterSchema.makeContainer(inMemory: true))
    let defaults = UserDefaults(suiteName: "IterFullPageIOS-\(UUID().uuidString)")!
    defaults.set(true, forKey: AppModel.sampleDataKey)
    let clock: @Sendable () -> Date = { fpNow }
    let sample = CachedWeatherService(wrapping: SampleWeatherService(now: clock))
    return AppModel(store: store, weather: sample, search: FPSearch(), geocoder: FPGeocoder(), drives: FPDrives(),
                    scout: nil, location: UserLocationModel(), sampleWeather: sample, defaults: defaults, now: { fpNow })
}

/// Whole iPhone pages (402 pt wide, 3x), offscreen, light and dark. Only with `ITER_SNAPSHOTS=1`; files go to `ITER_SNAPSHOT_DIR`.
@MainActor @Suite(.serialized) struct FullPageIOSSnapshotTests {
    private static let width: CGFloat = 402

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

    /// `height` nil: fit the window to the tallest scroll content.
    private func render<V: View>(_ name: String, height: CGFloat?, settle: Duration = .seconds(2), @ViewBuilder _ content: () -> V) async throws {
        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)
        let model = makeSampleModel()
        for (scheme, style) in [("light", UIUserInterfaceStyle.light), ("dark", .dark)] {
            let root = content()
                .environment(model)
                .environment(AppNavigation())
                .environment(ShellState())
                .modelContainer(model.store.container)
                .frame(width: Self.width)
            let host = UIHostingController(rootView: root)
            host.safeAreaRegions = []
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
            // A window taller than ~2700 pt (8192 px at 3x) renders blank, so tall pages are stitched from tiles.
            let viewport: CGFloat = height ?? 2400
            window.frame = CGRect(x: 0, y: 0, width: Self.width, height: viewport)
            window.overrideUserInterfaceStyle = style
            window.rootViewController = host
            window.isHidden = false
            try await Task.sleep(for: settle)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            func tile() -> UIImage {
                let format = UIGraphicsImageRendererFormat()
                format.scale = 3
                return UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
                    host.view.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
            }
            var image: UIImage
            if height == nil, let scroll = Self.tallestScroll(in: host.view) {
                let top0 = scroll.convert(CGPoint.zero, to: host.view).y
                let inset = scroll.adjustedContentInset
                let total = (top0 + inset.top + scroll.contentSize.height + inset.bottom).rounded(.up)
                if total <= viewport {
                    window.frame = CGRect(x: 0, y: 0, width: Self.width, height: total)
                    host.view.frame = window.bounds
                    host.view.layoutIfNeeded()
                    try await Task.sleep(for: .milliseconds(500))
                    image = tile()
                } else {
                    let format = UIGraphicsImageRendererFormat()
                    format.scale = 3
                    var tiles: [(UIImage, CGFloat, CGFloat)] = [(tile(), 0, 0)]  // image, final y of tile top, first screen y used
                    var covered = viewport
                    let sTop = top0 + inset.top
                    while covered < total {
                        let c = covered - sTop
                        scroll.setContentOffset(CGPoint(x: 0, y: c - inset.top), animated: false)
                        host.view.layoutIfNeeded()
                        try await Task.sleep(for: .milliseconds(500))
                        let shift = scroll.contentOffset.y + inset.top
                        let first = max(sTop, covered - shift)
                        tiles.append((tile(), shift, first))
                        covered = first + shift + (viewport - first)
                    }
                    image = UIGraphicsImageRenderer(size: CGSize(width: Self.width, height: total), format: format).image { ctx in
                        for (i, t) in tiles.enumerated() {
                            let first = t.2
                            ctx.cgContext.saveGState()
                            ctx.cgContext.clip(to: CGRect(x: 0, y: first + t.1, width: Self.width, height: viewport - first))
                            t.0.draw(at: CGPoint(x: 0, y: t.1))
                            ctx.cgContext.restoreGState()
                            _ = i
                        }
                    }
                }
            } else {
                image = tile()
            }
            window.isHidden = true
            guard let png = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: Self.outputDirectory.appendingPathComponent("ios-\(name)-\(scheme).png"))
        }
    }

    @Test(.enabled(if: fullPageEnabled)) func spotPageMesaArch() async throws {
        try await render("spotpage-mesa-arch", height: nil, settle: .seconds(5)) {
            NavigationStack { SpotPageScreen(route: SpotRoute(spot: CuratedSpots.spot(id: "mesa-arch")!, day: nil)) }
        }
    }

    @Test(.enabled(if: fullPageEnabled)) func scoreLegend() async throws {
        try await render("scorelegend", height: nil) { NavigationStack { ScoreLegendPage() } }
    }

    @Test(.enabled(if: fullPageEnabled)) func settings() async throws {
        try await render("settings", height: nil) { NavigationStack { IOSSettingsScreen() } }
    }
}
