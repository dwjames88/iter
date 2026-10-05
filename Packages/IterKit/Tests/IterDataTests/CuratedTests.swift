import Foundation
import Testing
import IterCore
@testable import IterData

@Suite struct CuratedTests {
    /// The number of spots in the web prototype's src/data/spots.ts when ported.
    static let sourceCount = 45

    @Test func countMatchesSource() {
        #expect(CuratedSpots.all.count == Self.sourceCount)
    }

    @Test func idsAreUniqueAndLookupWorks() {
        let ids = CuratedSpots.all.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(CuratedSpots.spot(id: "mesa-arch")?.name == "Mesa Arch")
        #expect(CuratedSpots.spot(id: "nope") == nil)
    }

    @Test func fieldsAreValid() {
        for spot in CuratedSpots.all {
            #expect(TimeZone(identifier: spot.timeZoneIdentifier) != nil, "\(spot.id) time zone")
            #expect((-90...90).contains(spot.coordinate.latitude) && (-180...180).contains(spot.coordinate.longitude), "\(spot.id) coordinate")
            #expect(spot.origin == .curated)
            #expect(!spot.name.isEmpty && !spot.locality.isEmpty && !spot.blurb.isEmpty, "\(spot.id) text")
            #expect(!spot.bestLight.isEmpty, "\(spot.id) best light")
            #expect(!(spot.notes + spot.blurb).contains("Vantage"))
            if let facing = spot.facing { #expect((0..<360).contains(facing)) }
            if let walk = spot.walkInMinutes { #expect(walk > 0) }
        }
    }

    @Test func spotsAreDecodedWithExpectedMapping() throws {
        let tunnel = try #require(CuratedSpots.spot(id: "tunnel-view"))
        #expect(tunnel.bestLight == [.sunset, .sunrise])
        #expect(tunnel.facing == 75)
        #expect(tunnel.elevationMeters == 1300)
        #expect(tunnel.walkInMinutes == 5)
        #expect(tunnel.timeZoneIdentifier == "America/Los_Angeles")
        #expect(CuratedSpots.spot(id: "mesa-arch")?.walkInMinutes == 10)
        #expect(CuratedSpots.spot(id: "bodie")?.walkInMinutes == nil)
    }

    @Test func templatesReferenceExistingSpots() {
        #expect(TripTemplates.all.count == 3)
        #expect(Set(TripTemplates.all.map(\.id)).count == 3)
        for template in TripTemplates.all {
            #expect(!template.stops.isEmpty)
            for stop in template.stops {
                #expect(CuratedSpots.spot(id: stop.spotID) != nil, "\(template.id): \(stop.spotID)")
                #expect((0..<template.dayCount).contains(stop.dayIndex))
            }
        }
    }
}
