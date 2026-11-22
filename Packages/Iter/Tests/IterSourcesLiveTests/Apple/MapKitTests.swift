import Testing
import Foundation
import MapKit
import CoreLocation
import IterModel
import IterSources
@testable import IterSourcesLive

private let moab = Coordinate(latitude: 38.5733, longitude: -109.5498)
private let box = GeoRegion(center: moab, latitudeDelta: 1, longitudeDelta: 1)
private let area = DiscoveryArea(name: "Moab", region: box)
private let epoch = Date(timeIntervalSince1970: 1_800_000_000)

/// Counts calls to a seam.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func hit() { lock.lock(); n += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return n }
}

private func mapItem(_ name: String, _ c: Coordinate, category: MKPointOfInterestCategory? = nil, url: URL? = nil) -> MKMapItem {
    let item = MKMapItem(location: CLLocation(latitude: c.latitude, longitude: c.longitude), address: nil)
    item.name = name
    item.pointOfInterestCategory = category
    item.url = url
    return item
}

@Suite("AppleMapKit POICategoryMapping")
struct AppleMapKitCategoryTests {
    @Test func everyKindHasADocumentedAnswer() {
        let mapped: Set<FeatureKind> = [.beach, .castle]
        for kind in FeatureKind.allCases {
            let cats = POICategoryMapping.categories(for: kind)
            if mapped.contains(kind) { #expect(!cats.isEmpty, "\(kind)") }
            else if kind == .viewpoint { #expect(cats.count <= 1) }
            else { #expect(cats.isEmpty, "\(kind) has no MapKit category") }
        }
    }

    @Test func forwardValues() {
        #expect(POICategoryMapping.categories(for: .beach) == [.beach])
        #expect(POICategoryMapping.categories(for: .castle) == [.castle, .fortress])
    }

    @Test func reverseMapping() {
        #expect(POICategoryMapping.featureKinds(forCategoryRaw: MKPointOfInterestCategory.beach.rawValue) == [.beach])
        #expect(POICategoryMapping.featureKinds(forCategoryRaw: MKPointOfInterestCategory.castle.rawValue) == [.castle])
        #expect(POICategoryMapping.featureKinds(forCategoryRaw: MKPointOfInterestCategory.fortress.rawValue) == [.castle])
        #expect(POICategoryMapping.featureKinds(forCategoryRaw: MKPointOfInterestCategory.park.rawValue).isEmpty)
        #expect(POICategoryMapping.featureKinds(forCategoryRaw: MKPointOfInterestCategory.restaurant.rawValue).isEmpty)
        #expect(POICategoryMapping.featureKinds(forCategoryRaw: nil).isEmpty)
    }

    @Test func roundTrip() {
        for kind in FeatureKind.allCases {
            for c in POICategoryMapping.categories(for: kind) {
                #expect(POICategoryMapping.featureKinds(forCategoryRaw: c.rawValue).contains(kind), "\(kind)")
            }
        }
    }

    @Test func unionIsDeduplicated() {
        let cats = POICategoryMapping.categories(for: [.beach, .castle, .peak])
        #expect(cats.map(\.rawValue) == [MKPointOfInterestCategory.beach, .castle, .fortress].map(\.rawValue))
    }
}

@Suite("AppleMapKit Mapping")
struct AppleMapKitMappingTests {
    @Test func mapItemToCandidate() throws {
        let url = URL(string: "https://maps.apple.com/?auid=1")!
        let record = MapItemRecord(mapItem("Mesa Arch Beach", moab, category: .beach, url: url))
        #expect(record.name == "Mesa Arch Beach")
        #expect(record.categoryRaw == MKPointOfInterestCategory.beach.rawValue)
        #expect(abs(record.coordinate.latitude - 38.5733) < 1e-6)
        let c = try #require(MapKitPlaceMapping.candidate(from: record, source: .appleSearch, fetchedAt: epoch, licence: nil))
        #expect(c.name == "Mesa Arch Beach")
        #expect(c.featureKinds == [.beach])
        #expect(c.source == .appleSearch)
        #expect(c.citations.first?.url == url)
        #expect(c.citations.first?.retrievedAt == epoch)
    }

    @Test func noURLNoCitationNoCategoryNoKinds() throws {
        let c = try #require(MapKitPlaceMapping.candidate(from: MapItemRecord(mapItem("Cafe", moab)), source: .appleSearch,
                                                          fetchedAt: epoch, licence: nil))
        #expect(c.citations.isEmpty)
        #expect(c.featureKinds.isEmpty)
        #expect(c.externalID == nil)
    }

    @Test func unnamedItemIsDropped() {
        let r = MapItemRecord(name: "  ", coordinate: moab)
        #expect(MapKitPlaceMapping.candidate(from: r, source: .appleSearch, fetchedAt: epoch, licence: nil) == nil)
    }

    @Test func externalIDPassesThrough() throws {
        let r = MapItemRecord(name: "X", coordinate: moab, identifier: "I123")
        let c = try #require(MapKitPlaceMapping.candidate(from: r, source: .applePOI, fetchedAt: epoch, licence: nil))
        #expect(c.externalID == "I123")
    }

    @Test func geocodeResultMapping() {
        let r = MapItemRecord(name: "Moab", coordinate: moab, fullAddress: "Moab, UT, United States", countryCode: "US",
                              timeZoneIdentifier: "America/Denver")
        let g = MapKitPlaceMapping.geocodeResult(from: r)
        #expect(g.name == "Moab")
        #expect(g.formattedAddress == "Moab, UT, United States")
        #expect(g.countryCode == "US")
        #expect(g.timeZoneIdentifier == "America/Denver")
    }

    @Test func uniqueKeepsFirst() {
        let a = MapItemRecord(name: "A", coordinate: moab, identifier: "1")
        let b = MapItemRecord(name: "A again", coordinate: moab, identifier: "1")
        let c = MapItemRecord(name: "C", coordinate: moab)
        #expect(MapKitConversion.unique([a, b, c, c]).map(\.name) == ["A", "C"])
    }

    @Test func polylineCoordinates() {
        let pts = [CLLocationCoordinate2D(latitude: 1, longitude: 2), CLLocationCoordinate2D(latitude: 3, longitude: 4)]
        #expect(MapKitConversion.coordinates(pts) == [Coordinate(latitude: 1, longitude: 2), Coordinate(latitude: 3, longitude: 4)])
        let line = MKPolyline(coordinates: pts, count: pts.count)
        // MKPolyline stores projected map points, so the round trip is equal only within float error.
        let back = MapKitConversion.coordinates(of: line)
        #expect(back.count == 2)
        for (a, b) in zip(back, MapKitConversion.coordinates(pts)) {
            #expect(abs(a.latitude - b.latitude) < 1e-6 && abs(a.longitude - b.longitude) < 1e-6)
        }
        #expect(MapKitConversion.coordinates([]).isEmpty)
    }

    @Test func downsampleKeepsEnds() {
        let pts = (0..<1000).map { Coordinate(latitude: Double($0) / 100, longitude: 0) }
        let d = MapKitConversion.downsample(pts, maxPoints: 400)
        #expect(d.count == 400)
        #expect(d.first == pts.first)
        #expect(d.last == pts.last)
        #expect(MapKitConversion.downsample(Array(pts.prefix(10)), maxPoints: 400).count == 10)
    }

    @Test func regionIsClamped() {
        let r = MapKitConversion.region(GeoRegion(center: moab, latitudeDelta: 500, longitudeDelta: 900))
        #expect(r.span.latitudeDelta == 179)
        #expect(r.span.longitudeDelta == 359)
    }

    @Test func routeMapping() {
        let a = Coordinate(latitude: 1, longitude: 1), b = Coordinate(latitude: 2, longitude: 2)
        let timed = MapKitDirectionsMapping.route(path: [a, b], seconds: 600, meters: 9000, departing: epoch, from: a, to: b)
        #expect(timed.isTrafficAware && timed.departing == epoch && !timed.isEstimate)
        #expect(timed.seconds == 600 && timed.meters == 9000 && timed.path == [a, b])
        let untimed = MapKitDirectionsMapping.route(path: [], seconds: 1, meters: 2, departing: nil, from: a, to: b)
        #expect(!untimed.isTrafficAware)
        #expect(untimed.path == [a, b])
    }

    @Test func etaMapping() {
        let e = MapKitDirectionsMapping.eta(seconds: 3600, arrival: epoch.addingTimeInterval(4000), departing: epoch)
        #expect(e.arrival == epoch.addingTimeInterval(4000))
        let f = MapKitDirectionsMapping.eta(seconds: 3600, arrival: nil, departing: epoch)
        #expect(f.arrival == epoch.addingTimeInterval(3600) && f.seconds == 3600)
    }
}

@Suite("AppleMapKit Errors")
struct AppleMapKitErrorTests {
    private func mk(_ code: MKError.Code) -> NSError { NSError(domain: MKError.errorDomain, code: Int(code.rawValue)) }

    @Test func mapping() {
        #expect(MapKitErrors.map(mk(.loadingThrottled)) == .rateLimited(retryAfter: nil))
        #expect(MapKitErrors.map(mk(.placemarkNotFound)) == .http(status: 404, excerpt: "placemark not found"))
        #expect(MapKitErrors.map(mk(.directionsNotFound)) == .http(status: 404, excerpt: "directions not found"))
        #expect(MapKitErrors.map(mk(.serverFailure)) == .http(status: 503, excerpt: "MapKit server failure"))
        if case .decoding = MapKitErrors.map(mk(.decodingFailed)) {} else { Issue.record("decodingFailed") }
        #expect(MapKitErrors.map(URLError(.notConnectedToInternet)) == .offline)
        #expect(MapKitErrors.map(URLError(.timedOut)) == .timedOut)
        #expect(MapKitErrors.map(NSError(domain: kCLErrorDomain, code: CLError.network.rawValue)) == .offline)
        #expect(MapKitErrors.map(CancellationError()) == .cancelled)
        #expect(MapKitErrors.map(SourceError.noSource) == .noSource)
    }
}

@Suite("AppleMapKit Throttle")
struct AppleMapKitThrottleTests {
    @Test func spacesRequests() async throws {
        let clock = ManualSourceClock(now: epoch)
        let t = MapKitThrottle(policy: SourceCatalogue.appleSearch.policy, clock: clock)
        try await t.acquire()
        try await t.acquire()
        #expect(clock.sleeps.count == 1)
        #expect(clock.sleeps[0] == .milliseconds(250))
    }

    @Test func capsPerMinute() async throws {
        let clock = ManualSourceClock(now: epoch)
        let t = MapKitThrottle(policy: RequestPolicy(spacing: .zero, perMinute: 3), clock: clock)
        for _ in 0..<3 { try await t.acquire() }
        await #expect(throws: SourceError.rateLimited(retryAfter: epoch.addingTimeInterval(60))) { try await t.acquire() }
        clock.advance(by: .seconds(61))
        try await t.acquire()
    }
}

@Suite("AppleMapKit Providers")
struct AppleMapKitProviderTests {
    @Test func descriptors() {
        let clock = ManualSourceClock(now: epoch)
        #expect(MapKitPlaceSearch(clock: clock).descriptor.id == .appleSearch)
        #expect(MapKitPOIGazetteer(clock: clock).descriptor.id == .applePOI)
        #expect(MapKitGeocoder(clock: clock).descriptor.id == .appleGeocoder)
        #expect(MapKitDirections(clock: clock).descriptor.id == .appleDirections)
        #expect(MapKitLookAround(clock: clock).descriptor.id == .appleLookAround)
        for d in [SourceCatalogue.appleSearch, SourceCatalogue.applePOI, SourceCatalogue.appleGeocoder, SourceCatalogue.appleDirections, SourceCatalogue.appleLookAround] {
            #expect(d.coverage.contains(moab))
            #expect(d.policy.perMinute == 50)
            #expect(d.key == .none)
        }
    }

    @Test func gazetteerWithUnmappedKindsMakesNoRequest() async throws {
        let calls = Counter()
        let g = MapKitPOIGazetteer(clock: ManualSourceClock(now: epoch)) { _, _ in calls.hit(); return [] }
        let r = try await g.candidates(in: area, features: [.peak, .waterfall, .arch], limit: 10)
        #expect(r.isEmpty)
        #expect(try await g.candidates(in: area, features: [], limit: 10).isEmpty)
        #expect(calls.count == 0)
    }

    @Test func gazetteerFiltersToAreaKindAndLimit() async throws {
        let inside = (0..<5).map { MapItemRecord(name: "Beach \($0)", coordinate: Coordinate(latitude: moab.latitude + 0.01 * Double($0), longitude: moab.longitude),
                                                categoryRaw: MKPointOfInterestCategory.beach.rawValue, identifier: "b\($0)") }
        let outside = MapItemRecord(name: "Far Beach", coordinate: Coordinate(latitude: 10, longitude: 10),
                                    categoryRaw: MKPointOfInterestCategory.beach.rawValue, identifier: "far")
        let wrongKind = MapItemRecord(name: "Cafe", coordinate: moab, categoryRaw: MKPointOfInterestCategory.cafe.rawValue, identifier: "c")
        let seen = Mutex2()
        let g = MapKitPOIGazetteer(clock: ManualSourceClock(now: epoch)) { _, cats in
            seen.set(cats); return [outside, wrongKind] + inside
        }
        let r = try await g.candidates(in: area, features: [.beach, .peak], limit: 3)
        #expect(r.map(\.name) == ["Beach 0", "Beach 1", "Beach 2"])
        #expect(r.allSatisfy { $0.featureKinds == [.beach] && $0.source == .applePOI })
        #expect(seen.value == [MKPointOfInterestCategory.beach.rawValue])
    }

    @Test func searchMapsAndDedupes() async throws {
        let rec = MapItemRecord(name: "Delicate Arch", coordinate: moab, identifier: "id1", url: URL(string: "https://maps.apple.com/x"))
        let s = MapKitPlaceSearch(clock: ManualSourceClock(now: epoch)) { q, _ in #expect(q == "arch"); return [rec, rec] }
        let r = try await s.search("  arch ", near: box)
        #expect(r.count == 1)
        #expect(r[0].externalID == "id1")
        #expect(r[0].citations.count == 1)
        #expect(r[0].citations[0].retrievedAt == epoch)
    }

    @Test func emptySearchMakesNoRequest() async throws {
        let calls = Counter()
        let s = MapKitPlaceSearch(clock: ManualSourceClock(now: epoch)) { _, _ in calls.hit(); return [] }
        #expect(try await s.search("   ", near: box).isEmpty)
        #expect(calls.count == 0)
    }

    @Test func searchMapsErrors() async {
        let s = MapKitPlaceSearch(clock: ManualSourceClock(now: epoch)) { _, _ in
            throw NSError(domain: MKError.errorDomain, code: Int(MKError.Code.loadingThrottled.rawValue))
        }
        await #expect(throws: SourceError.rateLimited(retryAfter: nil)) { _ = try await s.search("x", near: box) }
    }

    @Test func geocoderBoundaryIsNilWithoutRequest() async throws {
        let calls = Counter()
        let g = MapKitGeocoder(clock: ManualSourceClock(now: epoch), forward: { _, _ in calls.hit(); return [] },
                               reverse: { _ in calls.hit(); return [] })
        #expect(try await g.boundary(of: "Arches National Park", near: moab) == nil)
        #expect(calls.count == 0)
    }

    @Test func geocoderForwardReverse() async throws {
        let rec = MapItemRecord(name: "Moab", coordinate: moab, fullAddress: "Moab, UT", countryCode: "US")
        let g = MapKitGeocoder(clock: ManualSourceClock(now: epoch), forward: { _, _ in [rec] }, reverse: { _ in [rec] })
        #expect(try await g.geocode("Moab", near: nil).map(\.name) == ["Moab"])
        #expect(try await g.reverse(moab).countryCode == "US")
        #expect(try await g.geocode("", near: nil).isEmpty)
        await #expect(throws: SourceError.invalidRequest("coordinate out of range")) { _ = try await g.reverse(Coordinate(latitude: 95, longitude: 0)) }
        let empty = MapKitGeocoder(clock: ManualSourceClock(now: epoch), forward: { _, _ in [] }, reverse: { _ in [] })
        await #expect(throws: SourceError.http(status: 404, excerpt: "no reverse geocode result")) { _ = try await empty.reverse(moab) }
    }

    @Test func directionsPassDepartureAndMark() async throws {
        let got = Mutex2Date()
        let d = MapKitDirections(clock: ManualSourceClock(now: epoch), fetchRoute: { _, _, dep in
            got.set(dep)
            return .init(path: [moab], seconds: 100, meters: 200)
        }, fetchETA: { _, _, dep in .init(seconds: 50, arrival: dep.addingTimeInterval(50)) })
        let to = Coordinate(latitude: 39, longitude: -109)
        let r = try await d.route(from: moab, to: to, departing: epoch)
        #expect(got.value == epoch)
        #expect(r.isTrafficAware && r.departing == epoch && r.seconds == 100)
        let none = try await d.route(from: moab, to: to, departing: nil)
        #expect(!none.isTrafficAware)
        #expect(try await d.eta(from: moab, to: to, departing: epoch).arrival == epoch.addingTimeInterval(50))
    }

    @Test func directionsNoRouteIs404() async {
        let d = MapKitDirections(clock: ManualSourceClock(now: epoch), fetchRoute: { _, _, _ in
            throw NSError(domain: MKError.errorDomain, code: Int(MKError.Code.directionsNotFound.rawValue))
        }, fetchETA: { _, _, _ in throw URLError(.notConnectedToInternet) })
        await #expect(throws: SourceError.http(status: 404, excerpt: "directions not found")) {
            _ = try await d.route(from: moab, to: Coordinate(latitude: 1, longitude: 1), departing: nil)
        }
        await #expect(throws: SourceError.offline) {
            _ = try await d.eta(from: moab, to: Coordinate(latitude: 1, longitude: 1), departing: epoch)
        }
    }

    @Test func lookAround() async throws {
        let yes = MapKitLookAround(clock: ManualSourceClock(now: epoch)) { _ in true }
        #expect(try await yes.isAvailable(at: moab))
        let no = MapKitLookAround(clock: ManualSourceClock(now: epoch)) { _ in false }
        #expect(try await no.isAvailable(at: moab) == false)
        await #expect(throws: SourceError.invalidRequest("coordinate out of range")) { _ = try await yes.isAvailable(at: Coordinate(latitude: 0, longitude: 200)) }
    }
}

private final class Mutex2: @unchecked Sendable {
    private let lock = NSLock()
    private var v: [String] = []
    func set(_ x: [String]) { lock.lock(); v = x; lock.unlock() }
    var value: [String] { lock.lock(); defer { lock.unlock() }; return v }
}

private final class Mutex2Date: @unchecked Sendable {
    private let lock = NSLock()
    private var v: Date?
    func set(_ x: Date?) { lock.lock(); v = x; lock.unlock() }
    var value: Date? { lock.lock(); defer { lock.unlock() }; return v }
}
