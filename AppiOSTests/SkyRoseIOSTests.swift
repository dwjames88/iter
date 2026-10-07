import Testing
import Foundation
import SwiftUI
import UIKit
import IterCore
import IterData
import IterDesign
import IterServices
import IterFeatures
@testable import Iter

// MARK: - A minimal in-memory model

private struct RoseNoWeather: WeatherProviding {
    var source: ForecastSource { .appleWeather }
    func forecast(for coordinate: Coordinate) async throws -> Forecast { throw WeatherError.notEnabled }
    func attribution() async -> WeatherAttributionInfo? { nil }
}

private struct RoseNoSearch: PlaceSearching {
    func search(_ query: String, near region: GeoRegion?) async throws -> [PlaceResult] { [] }
    func pointsOfInterest(near center: Coordinate, radiusMeters: Double, categories: [String]) async throws -> [PlaceResult] { [] }
}

private struct RoseNoGeocoder: Geocoding {
    func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult {
        PlaceResult(id: "stub", name: "Dropped pin", locality: "Moab, UT", coordinate: coordinate,
                    timeZoneIdentifier: "America/Denver", pointOfInterestCategory: nil)
    }
    func geocode(_ query: String) async throws -> [PlaceResult] { [] }
}

private struct RoseEstimateDrives: DriveTimeProviding {
    func drive(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg { DriveLeg.estimate(from: a, to: b) }
}

private let denver = TimeZone(identifier: "America/Denver")!
private let testDay = LocalDay(year: 2026, month: 10, day: 6)
private let fixedNow = testDay.at(hour: 10, in: denver)

@MainActor private func makeModel() -> AppModel {
    let store = IterStore(container: try! IterSchema.makeContainer(inMemory: true))
    let defaults = UserDefaults(suiteName: "IterSkyRoseIOSTests-\(UUID().uuidString)")!
    return AppModel(store: store, weather: RoseNoWeather(), search: RoseNoSearch(), geocoder: RoseNoGeocoder(),
                    drives: RoseEstimateDrives(), scout: nil, location: UserLocationModel(), defaults: defaults, now: { fixedNow })
}

@MainActor private func makePage(facing: Double?, model: AppModel) async -> SpotModel {
    var spot = CuratedSpots.spot(id: "mesa-arch")!
    spot.facing = facing
    let page = SpotModel(app: model, spot: spot, initialDay: testDay)
    await page.start()
    return page
}

private func at(_ hour: Int, _ minute: Int = 0) -> Date { testDay.at(hour: hour, minute: minute, in: denver) }

// MARK: - The classic-view label is always placed

@MainActor @Suite struct SkyRoseWedgeLabelTests {
    @Test(arguments: [0.0, 90, 180, 263, 270, 359], [CGSize(width: 361, height: 400), CGSize(width: 330, height: 330), CGSize(width: 288, height: 288)])
    func wedgeLabelIsAlwaysPlaced(facing: Double, size: CGSize) {
        var placed: CGRect?
        var cardinalHit = false
        let content = Canvas { ctx, canvasSize in
            let proj = RoseRenderer.projection(size: canvasSize, rotation: 0)
            let rings = RoseRenderer.ringLabelRects(ctx, proj: proj)
            placed = RoseRenderer.wedgeLabel(ctx, proj: proj, size: canvasSize, facing: facing, ringTexts: rings)?.rect
            if let r = placed { cardinalHit = rings.contains { $0.cardinal && $0.rect.intersects(r) } }
        }.frame(width: size.width, height: size.height)
        let renderer = ImageRenderer(content: content)
        _ = renderer.uiImage
        #expect(placed != nil)
        #expect(!cardinalHit)
        if let placed { #expect(CGRect(origin: .zero, size: size).contains(placed)) }
    }
}

// MARK: - Shared time between the rose, the scrubber and the timeline

@MainActor @Suite struct SkyRoseIOSTests {
    private let size = CGSize(width: 360, height: 360)

    @Test func roseToTimeline() async {
        let model = makeModel()
        let page = await makePage(facing: 263, model: model)
        let projection = RoseRenderer.projection(size: size, rotation: 0)
        let sun = model.ephemeris.sunPosition(at: at(17, 30), coordinate: page.spot.coordinate)
        let point = projection.point(azimuth: sun.azimuth, altitude: sun.altitude)
        let hit = page.rose.nearestTime(to: point, projection: projection, maxDistance: SpotLayout.roseHitDistance)
        #expect(hit?.body == .sun)
        page.setTime(hit!.date)

        let data = LightTimelineSection.data(page)
        #expect(abs(data.marker.timeIntervalSince(at(17, 30))) < 60)
        let width: CGFloat = 320
        let x = TimelineRenderer.x(for: data.marker, width: width, data: data)
        let back = TimelineRenderer.date(atX: x, width: width, data: data)
        #expect(abs(back.timeIntervalSince(data.marker)) < 60)
    }

    @Test func timelineToRose() async {
        let model = makeModel()
        let page = await makePage(facing: 263, model: model)
        let data = LightTimelineSection.data(page)
        let width: CGFloat = 320
        let dragged = TimelineRenderer.date(atX: 211, width: width, data: data)
        page.scrub = dragged
        page.commitScrub()
        #expect(page.scrub == nil)
        #expect(page.hasChosenTime)
        #expect(page.markerTime == dragged)

        let projection = RoseRenderer.projection(size: size, rotation: 0)
        let sun = page.readout(at: page.markerTime).sun
        #expect(sun.altitude > 0)
        let marker = projection.point(azimuth: sun.azimuth, altitude: sun.altitude)
        let polyline = page.rose.sunArcs.flatMap { arc in
            zip(arc, arc.dropFirst()).map { a, b in
                (projection.point(azimuth: a.position.azimuth, altitude: a.position.altitude),
                 projection.point(azimuth: b.position.azimuth, altitude: b.position.altitude))
            }
        }
        let nearest = polyline.map { distance(from: marker, toSegment: $0) }.min() ?? .infinity
        #expect(nearest < 2)
    }

    @Test func keyboardStepsMoveTheMarker() async {
        let model = makeModel()
        let page = await makePage(facing: 263, model: model)
        page.setTime(at(12, 0))
        page.stepTime(minutes: SpotLayout.scrubberKeyStep)
        #expect(page.markerTime == at(12, 15))
        page.stepTime(minutes: -SpotLayout.scrubberKeyStepLarge)
        #expect(page.markerTime == at(11, 15))
    }

    @Test func scrubberMapsXToTimeAcrossTheDay() async {
        let model = makeModel()
        let page = await makePage(facing: nil, model: model)
        let (start, end) = page.dayInterval
        let span = end.timeIntervalSince(start)
        let inset: CGFloat = 14
        let left = TimeScrubber.date(atX: -50, width: 300, inset: inset, start: start, span: span)
        let mid = TimeScrubber.date(atX: 150, width: 300, inset: inset, start: start, span: span)
        let right = TimeScrubber.date(atX: 999, width: 300, inset: inset, start: start, span: span)
        #expect(left == start && right == end)
        #expect(abs(mid.timeIntervalSince(start.addingTimeInterval(span / 2))) < 1)
    }

    @Test func windowSymbolsExistAndMatchTheMapping() {
        let names = ["sunrise.fill", "sunset.fill", "sun.haze.fill", "moon.haze.fill", "moon.stars.fill"]
        for name in names { #expect(UIImage(systemName: name) != nil, "\(name) is missing on this OS") }
        #expect(LightText.symbol(LightWindowKind.goldenMorning) == "sunrise.fill")
        #expect(LightText.symbol(LightWindowKind.goldenEvening) == "sunset.fill")
        #expect(LightText.symbol(LightWindowKind.blueMorning) == "sun.haze.fill")
        #expect(LightText.symbol(LightWindowKind.blueEvening) == "moon.haze.fill")
        #expect(LightText.symbol(LightWindowKind.night) == "moon.stars.fill")
        for kind in SkyRose.EventKind.allCases { #expect(UIImage(systemName: LightText.roseSymbol(kind)) != nil) }
    }

    private func distance(from p: CGPoint, toSegment s: (CGPoint, CGPoint)) -> CGFloat {
        let vx = s.1.x - s.0.x, vy = s.1.y - s.0.y
        let len2 = vx * vx + vy * vy
        let t = len2 == 0 ? 0 : min(max(((p.x - s.0.x) * vx + (p.y - s.0.y) * vy) / len2, 0), 1)
        return hypot(s.0.x + vx * t - p.x, s.0.y + vy * t - p.y)
    }
}

// MARK: - Snapshots (iPhone 17 Pro, 402 pt wide, 3x), offscreen

private let roseSnapshotsEnabled = ProcessInfo.processInfo.environment["ITER_SNAPSHOTS"] == "1"

/// The module as the iPhone spot page lays it out: panel density, window background, inside a scrolling column with
/// the page's horizontal structure. Only runs with `ITER_SNAPSHOTS=1`; files go to `ITER_SNAPSHOT_DIR`.
@MainActor @Suite(.serialized) struct SkyRoseIOSSnapshotTests {
    private static let width: CGFloat = 402
    private static let maxHeight: CGFloat = 1400

    private static var outputDirectory: URL {
        if let dir = ProcessInfo.processInfo.environment["ITER_SNAPSHOT_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory.appendingPathComponent("IterSnapshots-iOS", isDirectory: true)
    }

    private func render(_ state: String, facing: Double?, hour: Int, minute: Int) async throws {
        let model = makeModel()
        let page = await makePage(facing: facing, model: model)
        page.setTime(at(hour, minute))
        try FileManager.default.createDirectory(at: Self.outputDirectory, withIntermediateDirectories: true)
        for (scheme, style) in [("light", UIUserInterfaceStyle.light), ("dark", .dark)] {
            let view = VStack(alignment: .leading, spacing: IterSpace.xl) {
                LightTimelineSection(page: page, viewUp: false)
                    .environment(\.spotDensity, .panel)
            }
            .padding(.vertical, IterSpace.lg)
            .frame(width: Self.width, alignment: .top)
            .background(IterColor.backgroundWindow)
            .ignoresSafeArea()
            .environment(model)
            .environment(\.colorScheme, style == .dark ? .dark : .light)
            let host = UIHostingController(rootView: view)
            host.safeAreaRegions = []
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
            window.frame = CGRect(x: 0, y: 0, width: Self.width, height: Self.maxHeight)
            window.overrideUserInterfaceStyle = style
            window.rootViewController = host
            window.isHidden = false
            try await Task.sleep(for: .milliseconds(500))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            // The module's fitting height: the window is cropped to it.
            let fit = host.sizeThatFits(in: CGSize(width: Self.width, height: Self.maxHeight))
            let size = CGSize(width: Self.width, height: min(Self.maxHeight, fit.height.rounded(.up)))
            window.frame = CGRect(origin: .zero, size: size)
            host.view.frame = CGRect(origin: .zero, size: size)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(200))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 3
            let image = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                host.view.drawHierarchy(in: CGRect(origin: .zero, size: size), afterScreenUpdates: true)
            }
            window.isHidden = true
            guard let png = image.pngData() else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: Self.outputDirectory.appendingPathComponent("ios-skyrose-\(state)-\(scheme).png"))
        }
    }

    @Test(.enabled(if: roseSnapshotsEnabled)) func sunriseInView() async throws {
        try await render("sunrise-in-view", facing: 100, hour: 8, minute: 0)
    }

    @Test(.enabled(if: roseSnapshotsEnabled)) func sunsetInView() async throws {
        try await render("sunset-in-view", facing: 263, hour: 18, minute: 45)
    }

    @Test(.enabled(if: roseSnapshotsEnabled)) func sunsetMissed() async throws {
        try await render("sunset-missed", facing: 190, hour: 18, minute: 45)
    }
}
