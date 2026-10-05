import CoreLocation
import Foundation
import IterCore
import MapKit
import Testing
@testable import IterServices

// Live checks against the real on-device model and Apple Maps. Run with ITER_LIVE_AI=1.

private let liveEnabled = ProcessInfo.processInfo.environment["ITER_LIVE_AI"] == "1"

/// Minimal MapKit-backed fakes, local to this test file.
private struct LiveSearch: PlaceSearching {
    let log: ReturnedCoordinates

    func search(_ query: String, near region: GeoRegion?) async throws -> [PlaceResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let region {
            request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: region.center.latitude, longitude: region.center.longitude),
                                                span: MKCoordinateSpan(latitudeDelta: min(region.latitudeDelta, 170), longitudeDelta: min(region.longitudeDelta, 350)))
        }
        let response = try await MKLocalSearch(request: request).start()
        let out = response.mapItems.map(liveResult)
        await log.add(out)
        return out
    }

    func pointsOfInterest(near center: Coordinate, radiusMeters: Double, categories: [String]) async throws -> [PlaceResult] {
        let request = MKLocalPointsOfInterestRequest(center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude), radius: radiusMeters)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories.map { MKPointOfInterestCategory(rawValue: $0) })
        let response = try await MKLocalSearch(request: request).start()
        let out = response.mapItems.map(liveResult)
        await log.add(out)
        return out
    }
}

private struct LiveGeocoder: Geocoding {
    let log: ReturnedCoordinates

    func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location), let item = try await request.mapItems.first else {
            throw CancellationError()
        }
        return liveResult(item)
    }

    func geocode(_ query: String) async throws -> [PlaceResult] {
        guard let request = MKGeocodingRequest(addressString: query) else { return [] }
        let out = try await request.mapItems.map(liveResult)
        await log.add(out)
        return out
    }
}

private func liveResult(_ item: MKMapItem) -> PlaceResult {
    let c = item.location.coordinate
    return PlaceResult(id: item.identifier?.rawValue ?? "", name: item.name ?? "Unnamed",
                       locality: item.addressRepresentations?.cityWithContext ?? "",
                       coordinate: Coordinate(latitude: c.latitude, longitude: c.longitude),
                       timeZoneIdentifier: item.timeZone?.identifier,
                       pointOfInterestCategory: item.pointOfInterestCategory?.rawValue)
}

private actor ReturnedCoordinates {
    private(set) var coordinates: Set<Coordinate> = []
    func add(_ results: [PlaceResult]) { for r in results { coordinates.insert(r.coordinate) } }
}

private let liveCurated = [Fixture.curatedSpot, Fixture.curatedCoast,
    Spot(id: "latourell-falls", name: "Latourell Falls", locality: "Columbia River Gorge, OR", coordinate: Coordinate(latitude: 45.5393, longitude: -122.2156),
         timeZoneIdentifier: "America/Los_Angeles", category: .waterfall, bestLight: [.overcast], blurb: "Lichen-covered basalt and a 224 ft fall.", origin: .curated)]

@Suite("Scout live", .enabled(if: liveEnabled))
struct ScoutLiveTests {
    @Test(.timeLimit(.minutes(4))) func liveScout() async throws {
        let log = ReturnedCoordinates()
        let scout = AppleIntelligenceScout(search: LiveSearch(log: log), geocoder: LiveGeocoder(log: log), drives: nil, curated: liveCurated)
        guard scout.availability() == .available else { Issue.record("model unavailable: \(scout.availability())"); return }

        let stages = ProgressLog()
        let clock = ContinuousClock()
        let start = clock.now
        let suggestions = try await scout.scout("foggy forest spots within two hours of Portland for sunrise", progress: { stages.add($0) })
        let elapsed = clock.now - start

        print("LIVE SCOUT: \(suggestions.count) suggestions in \(elapsed)")
        print("LIVE SCOUT progress: \(stages.all)")
        let tool = await log.coordinates
        for s in suggestions {
            print("  - \(s.spot.name) [\(s.provenance)] (\(s.spot.coordinate.latitude), \(s.spot.coordinate.longitude)) tz=\(s.spot.timeZoneIdentifier) cat=\(s.spot.category) window=\(String(describing: s.suggestedWindow)) :: \(s.why)")
        }
        #expect(!suggestions.isEmpty)
        let curatedCoords = Set(liveCurated.map(\.coordinate))
        for s in suggestions {
            #expect(tool.contains(s.spot.coordinate) || curatedCoords.contains(s.spot.coordinate), "\(s.spot.name) coordinate was not returned by any tool")
        }
        #expect(stages.all.first == .understanding)
        #expect(Set(suggestions.map(\.id)).count == suggestions.count)
    }

    @Test(.timeLimit(.minutes(2))) func liveExplainer() async throws {
        let explainer = LightExplainer()
        guard explainer.isAvailable() else { Issue.record("model unavailable"); return }
        let clock = ContinuousClock()
        let start = clock.now
        let text = try await explainer.explain(spotName: "Mesa Arch", window: ExplainerFixture.window(), intentName: "Sunset")
        print("LIVE EXPLAINER (\(clock.now - start)): \(text)")
        #expect(!text.isEmpty)
    }
}
