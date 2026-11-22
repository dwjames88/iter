import Foundation
import Testing
import IterCore
@testable import IterData

@Suite struct TimeZoneEstimateTests {
    @Test func offsetFromLongitudeRoundTrips() throws {
        let iceland = TimeZoneEstimate.identifier(for: Coordinate(latitude: 64.1, longitude: -19.0))
        #expect(iceland == "GMT-0100")
        #expect(TimeZone(identifier: iceland)?.secondsFromGMT() == -3600)
        let tokyo = TimeZoneEstimate.identifier(for: Coordinate(latitude: 35.0, longitude: 139.7))
        #expect(tokyo == "GMT+0900")
        #expect(TimeZone(identifier: tokyo)?.secondsFromGMT() == 9 * 3600)
        for lon in stride(from: -180.0, through: 180.0, by: 7.5) {
            let id = TimeZoneEstimate.identifier(for: Coordinate(latitude: 0, longitude: lon))
            #expect(TimeZone(identifier: id) != nil, "\(lon) -> \(id)")
        }
    }

    @Test func nearACuratedSpotItsZoneWins() throws {
        let mesa = try #require(CuratedSpots.spot(id: "mesa-arch"))
        let near = Coordinate(latitude: mesa.coordinate.latitude + 0.2, longitude: mesa.coordinate.longitude + 0.2)
        #expect(TimeZoneEstimate.identifier(for: near) == mesa.timeZoneIdentifier)
        #expect(TimeZoneEstimate.identifier(for: mesa.coordinate) == mesa.timeZoneIdentifier)
    }
}
