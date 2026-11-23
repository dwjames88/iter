import Foundation
import IterModel
import Testing
@testable import IterStore

/// The reason moves stamp `updatedAt`: a v2 merge import must carry them.
@MainActor
@Suite struct MoveMergeTests {
    @Test func aMoveAndAReorderTravelThroughAMergeImport() throws {
        let a = try StoreFixture()
        let tripFolder = a.store.folders.create(name: "Trips", kind: .trips)
        let placeFolder = a.store.folders.create(name: "Spots", kind: .locations)
        let trip = a.ownTrip("Moab")
        let p1 = a.ownPlace("one"), p2 = a.ownPlace("two"), p3 = a.ownPlace("three")
        a.store.folders.movePlaces([p1, p2, p3], to: placeFolder, index: nil)
        let exportA = a.store.exportLibrary()

        // B is a second device that got A's library, then edited it later.
        let b = try StoreFixture()
        b.store.importMerging(exportA)
        b.clock.advance(by: 10_000)
        let bTrip = try #require(b.store.trips.trip(id: trip.id))
        let bFolder = try #require(b.store.folders.folder(id: tripFolder.id))
        b.store.folders.moveTrips([bTrip], to: bFolder, index: nil)
        let bPlaceFolder = try #require(b.store.folders.folder(id: placeFolder.id))
        let three = try #require(b.store.places.savedPlaces(in: bPlaceFolder).first { $0.name == "three" })
        b.store.folders.movePlaces([three], to: bPlaceFolder, index: 0)

        a.clock.advance(by: 20_000)
        a.store.importMerging(b.store.exportLibrary())

        #expect(trip.folder?.id == tripFolder.id)
        #expect(a.store.places.savedPlaces(in: placeFolder).map(\.name) == ["three", "one", "two"])
    }
}
