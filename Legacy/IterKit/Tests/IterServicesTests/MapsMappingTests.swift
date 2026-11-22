import Testing
import MapKit
import IterCore
@testable import IterServices

@Suite struct MapsMappingTests {
    @Test func downsampleKeepsEndsAndCap() {
        let points = (0..<5000).map { Coordinate(latitude: Double($0) * 0.001, longitude: 0) }
        let thin = MapKitMapping.downsample(points, maxPoints: 400)
        #expect(thin.count == 400)
        #expect(thin.first == points.first)
        #expect(thin.last == points.last)
        // Monotonic along the route.
        #expect(zip(thin, thin.dropFirst()).allSatisfy { $0.latitude < $1.latitude })
    }

    @Test func downsampleLeavesShortPathsAlone() {
        let points = (0..<10).map { Coordinate(latitude: Double($0), longitude: 0) }
        #expect(MapKitMapping.downsample(points, maxPoints: 400) == points)
        #expect(MapKitMapping.downsample([], maxPoints: 400).isEmpty)
    }

    @Test func categoryMapping() {
        #expect(POICategoryMapping.spotCategory(for: MKPointOfInterestCategory.nationalPark.rawValue) == .landscape)
        #expect(POICategoryMapping.spotCategory(for: MKPointOfInterestCategory.park.rawValue) == .landscape)
        #expect(POICategoryMapping.spotCategory(for: MKPointOfInterestCategory.beach.rawValue) == .coast)
        #expect(POICategoryMapping.spotCategory(for: MKPointOfInterestCategory.marina.rawValue) == .coast)
        #expect(POICategoryMapping.spotCategory(for: MKPointOfInterestCategory.zoo.rawValue) == .wildlife)
        #expect(POICategoryMapping.spotCategory(for: MKPointOfInterestCategory.landmark.rawValue) == .architecture)
        #expect(POICategoryMapping.spotCategory(for: MKPointOfInterestCategory.planetarium.rawValue) == .astro)
        #expect(POICategoryMapping.spotCategory(for: MKPointOfInterestCategory.nightlife.rawValue) == .urban)
        #expect(POICategoryMapping.spotCategory(for: nil) == .landscape)
        #expect(POICategoryMapping.spotCategory(for: "not a category") == .landscape)
    }

    @Test func scenicCategoriesAreValidAndUnique() {
        let cats = POICategoryMapping.scenicCategories
        #expect(cats.contains(MKPointOfInterestCategory.nationalPark.rawValue))
        #expect(cats.contains(MKPointOfInterestCategory.beach.rawValue))
        #expect(cats.contains(MKPointOfInterestCategory.campground.rawValue))
        #expect(cats.contains(MKPointOfInterestCategory.landmark.rawValue))
        #expect(Set(cats).count == cats.count)
    }

    @Test func mapItemMapping() {
        let item = MKMapItem(location: CLLocation(latitude: 38.5733, longitude: -109.5498),
                             address: MKAddress(fullAddress: "Moab, UT, United States", shortAddress: "Moab, UT"))
        item.name = "Moab"
        item.pointOfInterestCategory = .park
        item.timeZone = TimeZone(identifier: "America/Denver")
        let place = MapKitMapping.placeResult(from: item)
        #expect(place.name == "Moab")
        #expect(place.coordinate.latitude == 38.5733)
        #expect(place.timeZoneIdentifier == "America/Denver")
        #expect(place.pointOfInterestCategory == MKPointOfInterestCategory.park.rawValue)
        #expect(!place.id.isEmpty)
        #expect(place.locality.contains("Moab"))
    }

    @Test func uniqueKeepsFirst() {
        let a = PlaceResult(id: "1", name: "A", locality: "", coordinate: .init(latitude: 0, longitude: 0), timeZoneIdentifier: nil, pointOfInterestCategory: nil)
        var b = a; b.name = "B"
        #expect(MapKitMapping.unique([a, b]).map(\.name) == ["A"])
    }
}
