import SwiftUI
import CoreGraphics
import Testing
import IterCore
import IterData
import IterDesign
import IterFeatures
import IterServices
@testable import Iter

/// Imagery for snapshots without a network: a generated gradient per source, drawn with the source's name so the
/// strip's paging and labels can be reviewed. FIXTURE ONLY; the app never invents images.
private struct FakeImagery: SpotImageryProviding {
    var sources: [SpotImageSource]

    func cachedImages(for request: SpotImageRequest) -> [SpotImage]? { make(request) }
    func images(for request: SpotImageRequest) async -> [SpotImage] { make(request) }
    func hasLookAround(spotID: String, coordinate: Coordinate) async -> Bool { sources.contains(.lookAround) }

    private func make(_ request: SpotImageRequest) -> [SpotImage] {
        sources.compactMap { source in
            let key = request.key(source)
            guard let image = Self.gradient(width: key.pixelWidth, height: key.pixelHeight, source: source) else { return nil }
            return SpotImage(key: key, image: image)
        }
    }

    private static func gradient(width: Int, height: Int, source: SpotImageSource) -> CGImage? {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let colors: [CGColor] = source == .lookAround
            ? [CGColor(red: 0.95, green: 0.62, blue: 0.35, alpha: 1), CGColor(red: 0.25, green: 0.35, blue: 0.55, alpha: 1)]
            : [CGColor(red: 0.30, green: 0.45, blue: 0.30, alpha: 1), CGColor(red: 0.75, green: 0.70, blue: 0.55, alpha: 1)]
        let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: width, y: height), options: [])
        return ctx.makeImage()
    }
}

@MainActor
@Suite(.serialized) struct PlaceCardSnapshotTests {
    private static let cardSize = Snapshot.Size(name: "420x720", width: 420, height: 720)

    /// The card alone, on a flat stand-in for the map, at the size the map pane gives it.
    private func card(_ model: AppModel, spotID: String = "mesa-arch", imagery: any SpotImageryProviding,
                      scrolled: Bool = false) -> some View {
        let spot = CuratedSpots.spot(id: spotID)!
        let row = ExploreModel(app: model).rows.first { $0.spot.id == spotID }!
        return Fixtures.host(
            ZStack(alignment: .bottomTrailing) {
                IterColor.backgroundControl
                ExplorePlaceCard(row: row, size: CGSize(width: IterSize.placeCardWidth, height: 680),
                                 startsScrolled: scrolled) {}
                    .padding(IterSpace.md)
            }
            .environment(\.spotImagery, imagery)
            .environment(\.displayScale, Snapshot.scale),
            model: model)
            .id(spot.id)
    }

    @Test(.enabled(if: Snapshot.enabled)) func withImages() async throws {
        let model = Fixtures.model(weather: .sample)
        _ = await model.forecasts.load(CuratedSpots.spot(id: "mesa-arch")!.coordinate)
        try await Snapshot.render(card(model, imagery: FakeImagery(sources: [.lookAround, .satellite])),
                                  screen: "placecard", state: "images", sizes: [Self.cardSize], settle: .seconds(2), chrome: .bare)
    }

    @Test(.enabled(if: Snapshot.enabled)) func placeholder() async throws {
        let model = Fixtures.model(weather: .sample)
        _ = await model.forecasts.load(CuratedSpots.spot(id: "mesa-arch")!.coordinate)
        try await Snapshot.render(card(model, imagery: FakeImagery(sources: [])),
                                  screen: "placecard", state: "placeholder", sizes: [Self.cardSize], settle: .seconds(2), chrome: .bare)
    }

    @Test(.enabled(if: Snapshot.enabled)) func scrolledToActions() async throws {
        let model = Fixtures.model(weather: .sample)
        _ = await model.forecasts.load(CuratedSpots.spot(id: "mesa-arch")!.coordinate)
        try await Snapshot.render(card(model, imagery: FakeImagery(sources: [.lookAround, .satellite]), scrolled: true),
                                  screen: "placecard", state: "scrolled", sizes: [Self.cardSize], settle: .seconds(3), chrome: .bare)
    }

    /// The card where it lives: over the Explore map pane.
    @Test(.enabled(if: Snapshot.enabled)) func inExplore() async throws {
        let model = Fixtures.model(weather: .sample)
        let screen = Fixtures.host(
            Fixtures.inDetailColumn(NavigationStack { ExploreView { $0.select("mesa-arch", from: .list) }.spotDestination() })
                .environment(\.spotImagery, FakeImagery(sources: [.lookAround, .satellite]))
                .environment(\.displayScale, Snapshot.scale),
            model: model)
        try await Snapshot.render(screen, screen: "placecard", state: "in-explore", sizes: [Snapshot.regular], settle: .seconds(3))
    }

    /// Real MapKit imagery, warmed before rendering. Skipped when MapKit gives nothing (offline test host).
    @Test(.enabled(if: Snapshot.enabled)) func realImagery() async throws {
        let spot = CuratedSpots.spot(id: "haystack-rock")!
        let request = SpotImageRequest(spotID: spot.id, coordinate: spot.coordinate,
                                       pointSize: CGSize(width: IterSize.placeCardWidth, height: IterSize.placeCardImageHeight),
                                       scale: Snapshot.scale)
        let warmed = await MapKitSpotImagery.shared.images(for: request)
        guard !warmed.isEmpty else { return }
        let model = Fixtures.model(weather: .sample)
        _ = await model.forecasts.load(CuratedSpots.spot(id: "mesa-arch")!.coordinate)
        try await Snapshot.render(card(model, spotID: spot.id, imagery: MapKitSpotImagery.shared),
                                  screen: "placecard", state: "real-images", sizes: [Self.cardSize], settle: .seconds(2), chrome: .bare)
    }
}
