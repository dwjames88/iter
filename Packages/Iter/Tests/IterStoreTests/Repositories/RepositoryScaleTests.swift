import Foundation
import IterModel
import SwiftData
import Testing
@testable import IterStore

/// A realistic library (about 200 places, 30 trips) and the hot-path fetches the UI calls from view bodies.
@MainActor
@Suite struct RepositoryScaleTests {
    /// Half the catalogue saved, 40 own places, the rest used by stops but unsaved; 30 trips, 5 pinned, 3 in a folder.
    func populated() throws -> (StoreFixture, [TripRecord]) {
        let f = try StoreFixture()
        let c = Coordinate(latitude: 40, longitude: -105)
        let curated = CuratedSpots.all
        // Save the first half of the catalogue; trips below also use the second half, which stays unsaved.
        for spot in curated.prefix(curated.count / 2) { f.store.places.setSaved(spot, true) }
        for i in 0..<40 { _ = f.store.places.createUserSpot(name: "User \(i)", coordinate: c, timeZoneIdentifier: "UTC") }
        var trips: [TripRecord] = []
        for i in 0..<30 {
            let trip = f.store.trips.create(name: "Trip \(i)", startDay: f.day, dayCount: 3)
            for j in 0..<4 { f.store.trips.addStop(curated[(i * 3 + j * 7) % curated.count], to: trip, day: j % 3) }
            trips.append(trip)
        }
        for t in trips.prefix(5) { f.store.trips.setPinned(t, true) }
        let folder = f.store.folders.create(name: "F", kind: .trips)
        f.store.folders.moveTrips(Array(trips[5..<8]), to: folder, index: nil)
        return (f, trips)
    }

    @Test func savedPlacesIncludesSavedAndUserOnly() throws {
        let (f, _) = try populated()
        // A used-but-unsaved curated place (a stop's place) must not be listed.
        let unsaved = f.store.trips.all().flatMap { $0.orderedStops.compactMap(\.place) }.filter { !$0.isSaved && $0.origin != .user }
        #expect(!unsaved.isEmpty)
        let listed = f.store.places.savedPlaces()
        #expect(listed.allSatisfy { $0.isSaved || $0.origin == .user })
        #expect(!listed.contains { p in unsaved.contains { $0.id == p.id } })
        #expect(listed.filter { $0.origin == .user }.count == 40)
        #expect(zip(listed, listed.dropFirst()).allSatisfy { ($0.updatedAt, $0.id.uuidString) >= ($1.updatedAt, $1.id.uuidString) })
    }

    @Test func pinnedTripsAreOnlyPinnedInPinOrder() throws {
        let (f, trips) = try populated()
        #expect(f.store.trips.pinned().map(\.id) == trips.prefix(5).map(\.id))
        f.store.trips.setPinned(trips[0], false)
        #expect(f.store.trips.pinned().map(\.id) == trips[1..<5].map(\.id))
    }

    @Test func hotFetchesStayFast() throws {
        let (f, trips) = try populated()
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for _ in 0..<50 {
                _ = f.store.trips.pinned()
                _ = f.store.places.savedPlaces()
                _ = f.store.places.isSaved(spotID: CuratedSpots.all[0].curatedID!)
                _ = f.store.trips.trip(id: trips[20].id)
                _ = f.store.trips.trips(in: nil)
            }
        }
        print("PERF store hot fetches x50 (200 places, 30 trips):", elapsed)
        #expect(elapsed < .seconds(5))
    }
}
