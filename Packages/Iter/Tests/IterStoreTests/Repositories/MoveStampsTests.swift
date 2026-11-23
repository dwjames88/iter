import Foundation
import IterModel
import Testing
@testable import IterStore

/// A `.iter` v2 merge keeps the newer `updatedAt` per record, so every move, reorder and pin must advance it, on the
/// records that changed and on no others.
@MainActor
@Suite struct MoveStampsTests {
    @Test func movingTripsStampsOnlyTheOnesThatChange() throws {
        let f = try StoreFixture()
        let folder = f.store.folders.create(name: "F", kind: .trips)
        let a = f.ownTrip("a"), b = f.ownTrip("b"), c = f.ownTrip("c")
        let before = (a.updatedAt, b.updatedAt, c.updatedAt)
        f.store.folders.moveTrips([a], to: folder, index: nil)
        #expect(a.updatedAt > before.0)
        // b and c are unfiled siblings of a; the move did not renumber them.
        #expect(b.updatedAt == before.1 && c.updatedAt == before.2)
        let afterMove = a.updatedAt
        // Reordering inside the folder.
        f.store.folders.moveTrips([b, c], to: folder, index: nil)
        let bc = (b.updatedAt, c.updatedAt)
        f.store.folders.moveTrips([c], to: folder, index: 0)
        #expect(c.updatedAt > bc.1)
        #expect(a.updatedAt > afterMove)
        // Moving to the same place stamps nothing.
        let stamps = [a.updatedAt, b.updatedAt, c.updatedAt]
        f.store.folders.moveTrips([c], to: folder, index: 0)
        #expect([a.updatedAt, b.updatedAt, c.updatedAt] == stamps)
    }

    @Test func movingAndReorderingPlacesStamps() throws {
        let f = try StoreFixture()
        let r = f.store.folders.create(name: "R", kind: .locations)
        let p1 = f.ownPlace("a"), p2 = f.ownPlace("b")
        let t1 = p1.updatedAt
        f.store.folders.movePlaces([p1, p2], to: r, index: nil)
        #expect(p1.updatedAt > t1 && p2.updatedAt > t1)
        let t2 = (p1.updatedAt, p2.updatedAt)
        f.store.folders.movePlaces([p2], to: r, index: 0)
        #expect(p2.updatedAt > t2.1 && p1.updatedAt > t2.0)
        let t3 = p1.updatedAt
        f.store.folders.movePlaces([p1], to: nil, index: nil)
        #expect(p1.updatedAt > t3)
    }

    @Test func reorderingFoldersStamps() throws {
        let f = try StoreFixture()
        let a = f.store.folders.create(name: "A", kind: .trips)
        let b = f.store.folders.create(name: "B", kind: .trips)
        let other = f.store.folders.create(name: "L", kind: .locations)
        let stamps = (a.updatedAt, b.updatedAt, other.updatedAt)
        f.store.folders.move(b, index: 0)
        #expect(a.updatedAt > stamps.0 && b.updatedAt > stamps.1)
        #expect(other.updatedAt == stamps.2)
    }

    @Test func pinningStamps() throws {
        let f = try StoreFixture()
        let trip = f.ownTrip("t"), place = f.ownPlace("p")
        let folder = f.store.folders.create(name: "F", kind: .trips)
        let t = trip.updatedAt, p = place.updatedAt, g = folder.updatedAt
        f.store.trips.setPinned(trip, true)
        f.store.places.setPinned(place, true)
        f.store.folders.setPinned(folder, true)
        #expect(trip.updatedAt > t && place.updatedAt > p && folder.updatedAt > g)
        let t2 = trip.updatedAt
        f.store.trips.setPinned(trip, false)
        #expect(trip.updatedAt > t2)
        // No change, no stamp.
        let t3 = trip.updatedAt
        f.store.trips.setPinned(trip, false)
        #expect(trip.updatedAt == t3)
    }

    @Test func deletingAFolderStampsTheContentsItUnfiles() throws {
        let f = try StoreFixture()
        let tf = f.store.folders.create(name: "T", kind: .trips)
        let lf = f.store.folders.create(name: "L", kind: .locations)
        let trip = f.ownTrip("t"), place = f.ownPlace("p")
        f.store.folders.moveTrips([trip], to: tf, index: nil)
        f.store.folders.movePlaces([place], to: lf, index: nil)
        let stamps = (trip.updatedAt, place.updatedAt)
        f.store.folders.delete(tf)
        f.store.folders.delete(lf)
        #expect(trip.updatedAt > stamps.0 && place.updatedAt > stamps.1)
    }

    @Test func movingAndReorderingStopsStampsTheTrip() throws {
        let f = try StoreFixture()
        let trip = f.trip3()
        let day0 = trip.orderedStops(onDay: 0)
        var last = trip.updatedAt
        f.store.trips.moveStop(day0[0], toDay: 1, index: 0)
        #expect(trip.updatedAt > last)
        last = trip.updatedAt
        f.store.trips.reorder(day: 1, in: trip, to: trip.orderedStops(onDay: 1).reversed().map(\.id))
        #expect(trip.updatedAt > last)
        last = trip.updatedAt
        f.store.trips.removeStop(trip.orderedStops(onDay: 2)[0])
        #expect(trip.updatedAt > last)
    }
}
