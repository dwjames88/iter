import Foundation
import Testing
import IterModel
@testable import IterSourcesLive

/// Metres per degree of arc on the sphere `HorizonComputer` uses; at the equator a due-east or due-north ray moves by exactly this.
private let metresPerDegree = Coordinate.earthRadiusMeters * .pi / 180

private func wall(distanceM: Double, heightM: Double, direction: String, halfWidthDegrees: Double = 0.003) -> (Coordinate) -> Double? {
    let d = distanceM / metresPerDegree
    return { c in
        switch direction {
        case "east": return c.longitude >= d && abs(c.latitude) < halfWidthDegrees ? heightM : 0
        case "west": return c.longitude <= -d && abs(c.latitude) < halfWidthDegrees ? heightM : 0
        case "north": return c.latitude >= d && abs(c.longitude) < halfWidthDegrees ? heightM : 0
        default: return nil
        }
    }
}

@Suite("HorizonComputer")
struct HorizonComputerTests {
    static let equator = Coordinate(latitude: 0, longitude: 0)

    @Test func azimuthCounts() {
        #expect(HorizonComputer(azimuthStepDegrees: 5).azimuthCount == 72)
        #expect(HorizonComputer(azimuthStepDegrees: 10).azimuthCount == 36)
        #expect(HorizonComputer(azimuthStepDegrees: 7).azimuthCount == nil)
        #expect(HorizonComputer(azimuthStepDegrees: 0).azimuthCount == nil)
        #expect(HorizonComputer(azimuthStepDegrees: 7).compute(from: Self.equator, groundElevationM: 0, sampler: { _ in 0 }) == nil)
    }

    @Test func spacingGrowsFromThirtyToTwoFiftyMetres() {
        #expect(HorizonComputer.step(atDistance: 0) == 30)
        #expect(HorizonComputer.step(atDistance: 1000) == 30)
        #expect(HorizonComputer.step(atDistance: 5000) == 150)
        #expect(HorizonComputer.step(atDistance: 30_000) == 250)
    }

    @Test func flatPlaneSitsSlightlyBelowLevelFromCurvature() throws {
        let c = HorizonComputer(azimuthStepDegrees: 5)
        let r = try #require(c.compute(from: Self.equator, groundElevationM: 0, sampler: { _ in 0 }))
        #expect(r.profile.elevationsDegrees.count == 72)
        #expect(r.profile.azimuthStepDegrees == 5)
        #expect(r.azimuthsWithoutData == 0)
        // Analytic dip for a 2 m eye with k = 0.13: -atan(2 sqrt(h (1-k) / (2R))) = about -0.0423 degrees.
        let expected = -atan(2 * (2 * 0.87 / (2 * 6_371_008.8)).squareRoot()) * 180 / .pi
        #expect(abs(expected + 0.0423) < 0.0005)
        for v in r.profile.elevationsDegrees { #expect(abs(v - expected) < 0.002) }
        #expect(abs(c.levelHorizonDegrees - expected) < 1e-12)
        #expect(r.reachedMetres.allSatisfy { $0 > 39_000 && $0 <= 40_000 })
    }

    @Test func groundHeightDoesNotMatterOnALevelPlane() throws {
        let c = HorizonComputer()
        let low = try #require(c.compute(from: Self.equator, groundElevationM: 0, sampler: { _ in 0 }))
        let high = try #require(c.compute(from: Self.equator, groundElevationM: 3000, sampler: { _ in 3000 }))
        #expect(low.profile == high.profile)
    }

    @Test func aThousandMetreWallDueEastAtTenKilometres() throws {
        let c = HorizonComputer(azimuthStepDegrees: 5)
        let r = try #require(c.compute(from: Self.equator, groundElevationM: 0, sampler: wall(distanceM: 10_000, heightM: 1000, direction: "east")))
        let v = r.profile.elevationsDegrees
        // atan(998/10000) = 5.70 degrees without curvature; the wall's first sample is at 10.0 to 10.25 km and curvature
        // (0.87 d^2 / 2R = 6.8 to 7.2 m) lowers it: between atan(991/10250)... and atan(991.2/10000) = 5.66.
        #expect(v[18] > 5.45 && v[18] < 5.70)
        // East is index 18 (90 / 5). The neighbours at 85 and 95 degrees miss the 330 m wide wall (their ray is 870 m off at 10 km).
        let flat = c.levelHorizonDegrees
        for i in 0..<72 where i != 18 { #expect(abs(v[i] - flat) < 0.002, "index \(i)") }
        // Reached distance on the east ray is the full 40 km (the wall keeps answering).
        #expect(r.reachedMetres[18] > 39_000)
    }

    @Test func indexZeroIsNorthAndAzimuthRunsClockwise() throws {
        let c = HorizonComputer(azimuthStepDegrees: 10)
        let north = try #require(c.compute(from: Self.equator, groundElevationM: 0, sampler: wall(distanceM: 8000, heightM: 800, direction: "north")))
        #expect(north.profile.elevationsDegrees.count == 36)
        #expect(north.profile.elevationsDegrees[0] > 5)
        #expect(north.profile.elevationsDegrees.enumerated().filter { $0.offset != 0 }.allSatisfy { $0.element < 0 })
        let west = try #require(c.compute(from: Self.equator, groundElevationM: 0, sampler: wall(distanceM: 8000, heightM: 800, direction: "west")))
        // West = 270 degrees = index 27 at 10 degree steps.
        #expect(west.profile.elevationsDegrees[27] > 5)
        #expect(west.profile.elevationsDegrees.enumerated().filter { $0.offset != 27 }.allSatisfy { $0.element < 0 })
        #expect(abs(north.profile.elevation(atAzimuth: 0) - north.profile.elevationsDegrees[0]) < 1e-12)
    }

    @Test func rayStopsWhereTheSamplerHasNoData() throws {
        let c = HorizonComputer(azimuthStepDegrees: 5)
        let limit = 5000 / metresPerDegree
        let r = try #require(c.compute(from: Self.equator, groundElevationM: 0, sampler: { $0.longitude > limit ? nil : 0 }))
        // East ray ends near 5 km; the others (which move away from the meridian slowly or not at all) go on.
        #expect(r.reachedMetres[18] > 4700 && r.reachedMetres[18] <= 5000)
        #expect(r.reachedMetres[54] > 39_000)
        #expect(r.azimuthsWithoutData == 0)
    }

    @Test func noDataAnywhereFillsTheLevelHorizonAndSaysSo() throws {
        let c = HorizonComputer(azimuthStepDegrees: 5)
        let r = try #require(c.compute(from: Self.equator, groundElevationM: 0, sampler: { _ in nil }))
        #expect(r.azimuthsWithoutData == 72)
        #expect(r.reachedMetres.allSatisfy { $0 == 0 })
        #expect(r.profile.elevationsDegrees.allSatisfy { $0 == c.levelHorizonDegrees })
    }

    @Test func aSummitSeesNothingAboveItself() throws {
        // A cone: height falls 0.5 m per metre from a 1000 m summit at the observer.
        let c = HorizonComputer(azimuthStepDegrees: 5, maxDistanceM: 10_000)
        let origin = Self.equator
        let cone: (Coordinate) -> Double? = { p in max(0, 1000 - 0.5 * origin.distance(to: p)) }
        let r = try #require(c.compute(from: origin, groundElevationM: 1000, sampler: cone))
        // Steepest view is straight down the 0.5 slope near the observer (-26.6 degrees, less the 2 m eye): the horizon is below level everywhere.
        for v in r.profile.elevationsDegrees { #expect(v < 0 && v > -27) }
    }
}
