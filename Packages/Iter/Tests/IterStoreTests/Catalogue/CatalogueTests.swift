import Foundation
import IterModel
import Testing
@testable import IterStore

@Suite struct CuratedTests {
    /// The number of places in the web prototype's src/data/spots.ts when ported.
    static let sourceCount = 45

    @Test func countMatchesSource() {
        #expect(CuratedSpots.all.count == Self.sourceCount)
    }

    @Test func idsAreUniqueAndLookupWorks() {
        let slugs = CuratedSpots.all.compactMap(\.curatedID)
        #expect(slugs.count == CuratedSpots.all.count)
        #expect(Set(slugs).count == slugs.count)
        #expect(Set(CuratedSpots.all.map(\.id)).count == slugs.count)
        #expect(CuratedSpots.spot(id: "mesa-arch")?.name == "Mesa Arch")
        #expect(CuratedSpots.spot(id: "nope") == nil)
    }

    @Test func stableIDsDoNotChange() {
        #expect(CuratedSpots.spot(id: "mesa-arch")?.id == CuratedSpots.stableID(forSlug: "mesa-arch"))
        #expect(CuratedSpots.stableID(forSlug: "mesa-arch") != CuratedSpots.stableID(forSlug: "bodie"))
        let again = CuratedSpots.stableID(forSlug: "mesa-arch")
        #expect(again.uuidString.hasPrefix(String(again.uuidString.prefix(8))))
        #expect(CuratedSpots.stableID(forSlug: "mesa-arch") == again)
    }

    @Test func fieldsAreValid() {
        for spot in CuratedSpots.all {
            let slug = spot.curatedID ?? "?"
            #expect(TimeZone(identifier: spot.timeZoneIdentifier) != nil, "\(slug) time zone")
            #expect((-90...90).contains(spot.coordinate.latitude) && (-180...180).contains(spot.coordinate.longitude), "\(slug) coordinate")
            #expect(spot.origin == .curated)
            #expect(!spot.isSaved && spot.folderID == nil && !spot.isPinned)
            #expect(!spot.name.isEmpty && !spot.locality.isEmpty && !spot.blurb.isEmpty, "\(slug) text")
            #expect(!spot.bestLight.isEmpty, "\(slug) best light")
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
        #expect(TripTemplates.template(id: "yosemite")?.dayCount == 2)
        for template in TripTemplates.all {
            #expect(!template.stops.isEmpty)
            for stop in template.stops {
                #expect(CuratedSpots.spot(id: stop.spotID) != nil, "\(template.id): \(stop.spotID)")
                #expect((0..<template.dayCount).contains(stop.dayIndex))
            }
        }
    }
}

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
