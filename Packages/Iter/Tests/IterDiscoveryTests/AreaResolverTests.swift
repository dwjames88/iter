import Foundation
import IterModel
import IterSources
import Testing
@testable import IterDiscovery

@Suite("AreaResolver")
struct AreaResolverTests {
    static let triangle = GeoPolygon(rings: [[Coordinate(latitude: 37.90, longitude: -119.80), Coordinate(latitude: 37.90, longitude: -119.30),
                                              Coordinate(latitude: 37.50, longitude: -119.55)]])

    func resolver(geocoder: FakeGeocoder? = nil, boundary: FakeBoundary? = nil) -> AreaResolver {
        AreaResolver(providers: DiscoveryProviders(geocoders: geocoder.map { [$0] } ?? [], boundaries: boundary.map { [$0] } ?? []),
                     configuration: DiscoveryConfiguration(sourceTimeoutOverride: .milliseconds(300)))
    }

    func km(_ r: GeoRegion) -> Double { r.latitudeDelta / 2 * 111 }

    @Test func nearMeNeedsALocation() async {
        let plan = QueryPlan(areaMode: .nearMe)
        let r = resolver()
        let none = await r.resolve(plan: plan, request: DiscoveryRequest(text: "x"), nearPhrasing: true)
        #expect(none == .failure(.needsLocation))
        let some = await r.resolve(plan: plan, request: DiscoveryRequest(text: "x", currentLocation: Geo.lonePine), nearPhrasing: true)
        guard case .success(let area) = some else { Issue.record("no area"); return }
        #expect(area.centre == Geo.lonePine)
        #expect(area.area.contains(Geo.lonePine))
        #expect(abs(km(area.area.region) - AreaResolver.defaultNearMeRadiusKm) < 1)
    }

    @Test func driveTimeBecomesARadius() async {
        let r = resolver()
        let plan = QueryPlan(areaMode: .nearMe, maxDriveMinutes: 120)
        let result = await r.resolve(plan: plan, request: DiscoveryRequest(text: "x", currentLocation: Geo.lonePine), nearPhrasing: false)
        guard case .success(let area) = result else { Issue.record("no area"); return }
        #expect(abs(km(area.area.region) - 120) < 1)
        #expect(AreaResolver.radiusKm(forDriveMinutes: 10_000) == AreaResolver.maximumRadiusKm)
    }

    @Test func mapAreaUsesTheVisibleRegion() async {
        let region = GeoRegion(center: Geo.yosemite, latitudeDelta: 0.4, longitudeDelta: 0.5)
        let r = resolver()
        let plan = QueryPlan(areaMode: .mapArea)
        #expect(await r.resolve(plan: plan, request: DiscoveryRequest(text: "x"), nearPhrasing: false) == .failure(.needsMapRegion))
        guard case .success(let area) = await r.resolve(plan: plan, request: DiscoveryRequest(text: "x", mapRegion: region), nearPhrasing: false) else {
            Issue.record("no area"); return
        }
        #expect(area.area.region == region)
        #expect(area.basis == .visibleMap)
    }

    @Test func namedBoxesAreSizedByKindOfPlace() async {
        let geo = FakeGeocoder(answers: [
            "lone pine": [GeocodeResult(name: "Lone Pine", coordinate: Geo.lonePine)],
            "delicate arch": [GeocodeResult(name: "Delicate Arch", coordinate: Coordinate(latitude: 38.74, longitude: -109.5))],
        ])
        let r = resolver(geocoder: geo)
        func radius(_ text: String, near: Bool, drive: Int? = nil) async -> Double? {
            let plan = QueryPlan(areaText: text, areaMode: .named, maxDriveMinutes: drive)
            guard case .success(let a) = await r.resolve(plan: plan, request: DiscoveryRequest(text: text), nearPhrasing: near) else { return nil }
            return km(a.area.region)
        }
        #expect(abs((await radius("Lone Pine", near: false))! - 30) < 1)
        #expect(abs((await radius("Lone Pine", near: true))! - 40) < 1)
        #expect(abs((await radius("Delicate Arch", near: false))! - 10) < 1)
        #expect(abs((await radius("Lone Pine", near: true, drive: 90))! - 90) < 1)
    }

    @Test func aParkUsesItsRealOutline() async {
        let geo = FakeGeocoder(answers: ["yosemite national park": [GeocodeResult(name: "Yosemite National Park", coordinate: Geo.yosemite)]])
        let nb = NamedBoundary(name: "Yosemite National Park", polygon: Self.triangle, externalID: "relation/1", areaKind: "national_park",
                               citation: citation("fake.boundary", "Yosemite boundary"))
        let r = resolver(geocoder: geo, boundary: FakeBoundary(answer: nb))
        let plan = QueryPlan(areaText: "Yosemite National Park", areaMode: .named)
        guard case .success(let a) = await r.resolve(plan: plan, request: DiscoveryRequest(text: "x"), nearPhrasing: false) else { Issue.record("no area"); return }
        #expect(a.hasRealBoundary)
        #expect(a.basis == .boundary(name: "Yosemite National Park", externalID: "relation/1"))
        #expect(a.boundaryCitation?.title == "Yosemite boundary")
        #expect(a.area.contains(Coordinate(latitude: 37.8, longitude: -119.55)))
        #expect(!a.area.contains(Coordinate(latitude: 37.55, longitude: -119.78)))   // inside the box, outside the outline
    }

    @Test func aLargeGeocodedRegionAlsoTriesTheBoundary() async {
        let big = GeoRegion(center: Geo.yosemite, latitudeDelta: 0.6, longitudeDelta: 0.7)
        let geo = FakeGeocoder(answers: ["yosemite": [GeocodeResult(name: "Yosemite", coordinate: Geo.yosemite, region: big)]])
        let nb = NamedBoundary(name: "Yosemite National Park", polygon: Self.triangle, citation: citation("fake.boundary", "b"))
        let boundary = FakeBoundary(answer: nb)
        let r = resolver(geocoder: geo, boundary: boundary)
        guard case .success(let a) = await r.resolve(plan: QueryPlan(areaText: "Yosemite", areaMode: .named), request: DiscoveryRequest(text: "x"), nearPhrasing: false)
        else { Issue.record("no area"); return }
        #expect(a.hasRealBoundary)
        #expect(boundary.log.calls == ["boundary:Yosemite"])
    }

    @Test func noOutlineFallsBackToTheGeocodedRegionOrABox() async {
        let big = GeoRegion(center: Geo.yosemite, latitudeDelta: 1.5, longitudeDelta: 1.5)
        let geo = FakeGeocoder(answers: ["yosemite": [GeocodeResult(name: "Yosemite", coordinate: Geo.yosemite, region: big)]])
        let r = resolver(geocoder: geo, boundary: FakeBoundary(answer: nil))
        guard case .success(let a) = await r.resolve(plan: QueryPlan(areaText: "Yosemite", areaMode: .named), request: DiscoveryRequest(text: "x"), nearPhrasing: false)
        else { Issue.record("no area"); return }
        #expect(!a.hasRealBoundary)
        #expect(a.basis == .geocodedRegion)
        #expect(a.area.region == big)
    }

    @Test func failuresAreStatesNotCrashes() async {
        let plan = QueryPlan(areaText: "Nowhereville", areaMode: .named)
        let req = DiscoveryRequest(text: "x")
        #expect(await resolver().resolve(plan: plan, request: req, nearPhrasing: false) == .failure(.noGeocoder))
        #expect(await resolver(geocoder: FakeGeocoder()).resolve(plan: plan, request: req, nearPhrasing: false) == .failure(.notFound("Nowhereville")))
        var failing = FakeGeocoder()
        failing.script = Script(error: .offline)
        guard case .failure(.geocoderFailed) = await resolver(geocoder: failing).resolve(plan: plan, request: req, nearPhrasing: false)
        else { Issue.record("expected geocoderFailed"); return }
        var slow = FakeGeocoder()
        slow.script = Script(delay: .seconds(30))
        guard case .failure(.geocoderFailed) = await resolver(geocoder: slow).resolve(plan: plan, request: req, nearPhrasing: false)
        else { Issue.record("expected geocoderFailed on timeout"); return }
        #expect(slow.log.cancelledCount == 1)
        #expect(await resolver().resolve(plan: QueryPlan(areaMode: .named), request: req, nearPhrasing: false) == .failure(.noAreaText))
    }

    @Test func areaAndPointOfInterestWords() {
        #expect(AreaResolver.looksLikeArea("Yosemite National Park"))
        #expect(AreaResolver.looksLikeArea("Inyo National Forest"))
        #expect(AreaResolver.looksLikeArea("Ansel Adams Wilderness"))
        #expect(AreaResolver.looksLikeArea("Mojave National Preserve"))
        #expect(AreaResolver.looksLikeArea("Lake Mead National Recreation Area"))
        #expect(!AreaResolver.looksLikeArea("Lone Pine"))
        #expect(AreaResolver.looksLikePointOfInterest("Mesa Arch"))
        #expect(!AreaResolver.looksLikePointOfInterest("Mammoth"))
    }
}
