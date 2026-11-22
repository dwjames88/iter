import Testing
import Foundation
import IterCore
@testable import IterServices

/// Live checks against Apple's services. Run with `ITER_LIVE=1 swift test --filter Live`.
private let live = ProcessInfo.processInfo.environment["ITER_LIVE"] == "1"

@Suite(.enabled(if: live, "set ITER_LIVE=1")) struct LiveTests {
    private let mesaArch = Coordinate(latitude: 38.389, longitude: -109.868)
    private let moab = Coordinate(latitude: 38.5733, longitude: -109.5498)

    @Test func searchMesaArch() async throws {
        let region = GeoRegion(center: moab, latitudeDelta: 1, longitudeDelta: 1)
        let results = try await MapKitPlaceSearch().search("Mesa Arch", near: region)
        print("LIVE search:", results.map { "\($0.name) | \($0.locality) | \($0.coordinate.cacheKey) | \($0.timeZoneIdentifier ?? "-") | \($0.pointOfInterestCategory ?? "-")" })
        #expect(results.contains { $0.coordinate.distance(to: mesaArch) < 2000 })
    }

    @Test func pointsOfInterestNearMesaArch() async throws {
        let results = try await MapKitPlaceSearch().pointsOfInterest(near: mesaArch, radiusMeters: 20_000, categories: POICategoryMapping.scenicCategories)
        print("LIVE poi:", results.prefix(8).map { "\($0.name) [\($0.pointOfInterestCategory ?? "-")]" })
        #expect(!results.isEmpty)
    }

    @Test func directionsMoabToMesaArch() async throws {
        let leg = try await MapKitDriveTimes().drive(from: moab, to: mesaArch)
        print("LIVE drive: \(leg.seconds / 60) min, \(leg.meters / 1000) km, path points \(leg.path.count)")
        #expect(!leg.isEstimate)
        #expect((35 * 60...70 * 60).contains(leg.seconds))
        #expect(leg.path.count > 2 && leg.path.count <= 400)
    }

    @Test func reverseGeocodeTunnelView() async throws {
        let tunnelView = Coordinate(latitude: 37.7155, longitude: -119.6770)
        let place = try await MapKitGeocoder().reverseGeocode(tunnelView)
        print("LIVE reverse:", place)
        #expect(place.timeZoneIdentifier == "America/Los_Angeles")
    }

    @Test func forwardGeocode() async throws {
        let results = try await MapKitGeocoder().geocode("Portland, Oregon")
        print("LIVE geocode:", results.map { "\($0.name) | \($0.locality) | \($0.timeZoneIdentifier ?? "-")" })
        #expect(!results.isEmpty)
    }

    @Test func weatherKitIsNotEnabledOrReturnsForecast() async throws {
        let service = AppleWeatherService()
        do {
            let f = try await service.forecast(for: moab)
            print("LIVE weather: forecast with \(f.hours.count) hours, \(f.days.count) days")
            #expect(f.hours.count > 100)
        } catch let e as WeatherError {
            print("LIVE weather error:", e)
            #expect(e == .notEnabled)
        }
        let a = await service.attribution()
        print("LIVE attribution:", a as Any)
    }
}
