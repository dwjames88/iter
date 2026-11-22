import Foundation
import IterCore
@testable import IterServices

// Fakes and fixtures shared by the Scout tests.

struct FakeSearch: PlaceSearching {
    var results: [PlaceResult]
    var scenic: [PlaceResult] = []
    func search(_ query: String, near region: GeoRegion?) async throws -> [PlaceResult] { results }
    func pointsOfInterest(near center: Coordinate, radiusMeters: Double, categories: [String]) async throws -> [PlaceResult] { scenic }
}

struct FakeGeocoder: Geocoding {
    var centre: PlaceResult?
    var zone: String? = "America/Los_Angeles"
    func reverseGeocode(_ coordinate: Coordinate) async throws -> PlaceResult {
        PlaceResult(id: "rev", name: "Reversed", locality: "", coordinate: coordinate, timeZoneIdentifier: zone, pointOfInterestCategory: nil)
    }
    func geocode(_ query: String) async throws -> [PlaceResult] { centre.map { [$0] } ?? [] }
}

actor DriveCounter {
    var calls = 0
    func bump() { calls += 1 }
}

struct FakeDrives: DriveTimeProviding {
    var counter = DriveCounter()
    func drive(from a: Coordinate, to b: Coordinate) async throws -> DriveLeg {
        await counter.bump()
        return DriveLeg(from: a, to: b, seconds: 5400, meters: 90_000, isEstimate: false)
    }
}

enum Fixture {
    static let portland = PlaceResult(id: "portland", name: "Portland", locality: "Oregon", coordinate: Coordinate(latitude: 45.5152, longitude: -122.6784),
                                      timeZoneIdentifier: "America/Los_Angeles", pointOfInterestCategory: nil)

    static func place(_ id: String, _ name: String, lat: Double, lon: Double, poi: String? = nil, zone: String? = "America/Los_Angeles") -> PlaceResult {
        PlaceResult(id: id, name: name, locality: "Oregon", coordinate: Coordinate(latitude: lat, longitude: lon), timeZoneIdentifier: zone, pointOfInterestCategory: poi)
    }

    static let silverFalls = place("apple-1", "Silver Falls State Park", lat: 44.8788, lon: -122.6488, poi: "MKPOICategoryPark")
    static let cannonBeach = place("apple-2", "Cannon Beach", lat: 45.8918, lon: -123.9615, poi: "MKPOICategoryBeach")
    static let farAway = place("apple-3", "Yellowstone", lat: 44.4280, lon: -110.5885)

    static let curatedSpot = Spot(id: "Multnomah-Falls", name: "Multnomah Falls", locality: "Columbia River Gorge, OR",
                                  coordinate: Coordinate(latitude: 45.5762, longitude: -122.1158), timeZoneIdentifier: "America/Los_Angeles",
                                  category: .waterfall, bestLight: [.overcast, .sunrise], blurb: "Tall waterfall in mossy forest.", origin: .curated)
    static let curatedCoast = Spot(id: "haystack-rock", name: "Haystack Rock", locality: "Cannon Beach, OR",
                                   coordinate: Coordinate(latitude: 45.8847, longitude: -123.9689), timeZoneIdentifier: "America/Los_Angeles",
                                   category: .coast, bestLight: [.sunset], origin: .curated)

    static func context(search: FakeSearch = FakeSearch(results: []), drives: (any DriveTimeProviding)? = nil, curated: [Spot] = [],
                        registry: ScoutRegistry = ScoutRegistry(), progress: @escaping @Sendable (ScoutProgress) -> Void = { _ in }) -> ScoutToolContext {
        ScoutToolContext(search: search, geocoder: FakeGeocoder(centre: portland), drives: drives, curated: curated, registry: registry, progress: progress)
    }
}

final class ProgressLog: @unchecked Sendable { // test-only box; guarded by the lock
    private let lock = NSLock()
    private var items: [ScoutProgress] = []
    func add(_ p: ScoutProgress) { lock.lock(); items.append(p); lock.unlock() }
    var all: [ScoutProgress] { lock.lock(); defer { lock.unlock() }; return items }
}
