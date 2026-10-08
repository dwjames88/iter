import Foundation
import Testing
@testable import IterCore

@Suite struct GeoPinTests {
    let nyc = Coordinate(latitude: 40.7128, longitude: -74.0060)
    let london = Coordinate(latitude: 51.5074, longitude: -0.1278)

    @Test func distanceAndBearingMatchKnownValues() {
        // NYC to London is about 5,570 km, initial bearing about 51 degrees.
        #expect(abs(nyc.distance(to: london) / 1000 - 5570) < 15)
        #expect(abs(nyc.bearing(to: london) - 51.2) < 0.5)
        #expect(nyc.distance(to: nyc) == 0)
        #expect(abs(Coordinate(latitude: 0, longitude: 0).bearing(to: Coordinate(latitude: 0, longitude: 10)) - 90) < 1e-9)
        #expect(abs(Coordinate(latitude: 0, longitude: 0).bearing(to: Coordinate(latitude: 10, longitude: 0))) < 1e-9)
        #expect(abs(Coordinate(latitude: 0, longitude: 0).bearing(to: Coordinate(latitude: -10, longitude: 0)) - 180) < 1e-9)
        #expect(abs(Coordinate(latitude: 0, longitude: 0).bearing(to: Coordinate(latitude: 0, longitude: -10)) - 270) < 1e-9)
    }

    @Test func theDateLineIsNotADetour() {
        // 179.5 E to 179.5 W is one degree of longitude, not 359.
        let a = Coordinate(latitude: 0, longitude: 179.5), b = Coordinate(latitude: 0, longitude: -179.5)
        #expect(abs(a.distance(to: b) / 1000 - 111.2) < 1)
        #expect(abs(a.bearing(to: b) - 90) < 1e-6)
    }

    @Test func antipodesAreFiniteAndHalfTheEarth() {
        let a = Coordinate(latitude: 10, longitude: 20), b = Coordinate(latitude: -10, longitude: -160)
        let d = a.distance(to: b)
        #expect(d.isFinite && abs(d - Double.pi * Coordinate.earthRadiusMeters) < 1)
        #expect(a.bearing(to: b).isFinite)
    }

    @Test func compassPointsWrapAndRound() {
        #expect(compassPoint(for: 0) == "N" && compassPoint(for: 360) == "N" && compassPoint(for: 359) == "N")
        #expect(compassPoint(for: -90) == "W" && compassPoint(for: 450) == "E" && compassPoint(for: 100) == "E")
        #expect(compassPoint(for: 11.2) == "N" && compassPoint(for: 11.3) == "NNE")
        #expect(compassPoint(for: 348.7) == "NNW" && compassPoint(for: 348.8) == "N")
        #expect(compassPoint(for: 180) == "S" && compassPoint(for: 202.5) == "SSW")
    }

    @Test func cacheKeyIsStableAcrossNegativeZero() {
        // Just either side of the equator or the prime meridian is the same 100 m cell: one key, never "-0.000".
        let a = Coordinate(latitude: -0.0004, longitude: 0.0004), b = Coordinate(latitude: 0.0004, longitude: -0.0004)
        #expect(a.cacheKey == b.cacheKey)
        #expect(a.cacheKey == "0.000,0.000")
        #expect(Coordinate(latitude: 38.389, longitude: -109.8677).cacheKey == "38.389,-109.868")
        #expect(Coordinate(latitude: -0.0006, longitude: 0).cacheKey == "-0.001,0.000")
    }

    @Test func enclosingRegionPadsAndKeepsAMinimum() throws {
        #expect(GeoRegion.enclosing([]) == nil)
        let one = try #require(GeoRegion.enclosing([nyc]))
        #expect(one.center == nyc && one.latitudeDelta == 0.05 && one.longitudeDelta == 0.05)
        let two = try #require(GeoRegion.enclosing([nyc, london]))
        #expect(two.contains(nyc) && two.contains(london))
        #expect(abs(two.latitudeDelta - (london.latitude - nyc.latitude) * 1.2) < 1e-9)
        #expect(!two.contains(Coordinate(latitude: 0, longitude: 0)))
    }
}
