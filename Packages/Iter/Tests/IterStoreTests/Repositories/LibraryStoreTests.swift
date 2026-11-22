import Foundation
import IterModel
import SwiftData
import Testing
@testable import IterStore

@MainActor
@Suite struct CoalescedSaveTests {
    @Test func aBurstOfEditsSavesOnceOnTheNextTurn() async throws {
        let f = try StoreFixture()
        let before = f.store.saveCount
        let trip = f.store.trips.create(name: "T", startDay: f.day, dayCount: 3)
        for i in 0..<20 { f.store.trips.rename(trip, to: "T\(i)") }
        f.store.trips.addStop(f.spot("mesa-arch"), to: trip, day: 0)
        #expect(f.store.saveCount == before)   // nothing saved inside the burst
        #expect(f.store.context.hasChanges)
        await Task.yield()
        #expect(f.store.saveCount == before + 1)
        #expect(!f.store.context.hasChanges && f.store.lastSaveError == nil)
        // Nothing pending: a flush is not a save.
        f.store.flush()
        #expect(f.store.saveCount == before + 1)
    }

    @Test func undoAndRedoScheduleASaveToo() async throws {
        let f = try StoreFixture(undoable: true)
        let trip = f.act { f.store.trips.create(name: "T", startDay: f.day, dayCount: 1) }
        f.store.flush()
        let saved = f.store.saveCount
        f.undo.undo()
        #expect(f.store.context.hasChanges)
        await Task.yield()
        #expect(f.store.saveCount == saved + 1)
        f.undo.redo()
        await Task.yield()
        #expect(f.store.saveCount == saved + 2)
        _ = trip
    }

    @Test func flushPersistsAndIsVisibleToASecondContext() throws {
        let dir = try TestSupport.makeTempDirectory("iter-coalesce")
        defer { try? FileManager.default.removeItem(at: dir) }
        let container = try IterStoreSchema.makeContainer(url: dir.appendingPathComponent("iter.store"))
        let store = LibraryStore(container: container)
        let other = ModelContext(container)
        func tripCount() -> Int { (try? other.fetch(FetchDescriptor<TripRecord>()).count) ?? -1 }

        let trip = store.trips.create(name: "A", startDay: LocalDay(year: 2026, month: 1, day: 1), dayCount: 2)
        store.trips.addStop(CuratedSpots.spot(id: "mesa-arch")!, to: trip, day: 1)
        store.trips.rename(trip, to: "B")
        #expect(tripCount() == 0)   // still only in the main context
        store.flush()
        #expect(store.saveCount == 1)
        #expect(tripCount() == 1)
        let stored = try #require(try other.fetch(FetchDescriptor<TripRecord>()).first)
        #expect(stored.name == "B" && stored.orderedStops.count == 1 && stored.orderedStops[0].dayIndex == 1)
        #expect((try other.fetch(FetchDescriptor<PlaceRecord>())).map(\.curatedID) == ["mesa-arch"])
    }
}

@MainActor
@Suite struct DocumentStoreTests {
    @Test func exportV1OfAStoredTripIsTheTrip() throws {
        let f = try StoreFixture()
        let trip = f.trip3()
        f.store.trips.setNote(trip.orderedStops[0], to: "Arrive early")
        f.store.trips.setBuffer(trip.orderedStops[1], minutes: 45)
        f.store.trips.setTransferTiming(trip, intoDay: 1, to: .eveningBefore)
        let value = try #require(f.store.trips.value(id: trip.id))
        let file = try #require(f.store.exportV1(tripID: trip.id))
        #expect(file.plan.id == trip.id && file.plan.name == value.name && file.plan.dayCount == 3)
        #expect(file.plan.transferTimings == [1: .eveningBefore])
        #expect(file.plan.stops.map(\.id) == value.stops.map(\.id))
        #expect(file.plan.stops.map(\.spot.id) == ["mesa-arch", "delicate-arch", "horseshoe-bend", "monument-valley"])
        #expect(file.plan.stops[0].note == "Arrive early" && file.plan.stops[1].setUpBufferMinutes == 45)
        #expect(file.exportedAt == Date(timeIntervalSince1970: file.exportedAt.timeIntervalSince1970.rounded(.down)))
        // Through the bytes and back.
        guard case .v1(let read) = try ITERFile.read(try file.encoded()) else { Issue.record("expected v1"); return }
        #expect(read == file)
        #expect(f.store.exportV1(tripID: UUID()) == nil && f.store.exportV2(tripID: UUID()) == nil)
    }

    @Test func exportV2CarriesTheV5Fields() throws {
        let f = try StoreFixture()
        let trip = f.trip3()
        let home = f.ownPlace("Home")
        f.store.trips.setDwell(trip.orderedStops[0], minutes: 30)
        f.store.trips.setKind(trip.orderedStops[0], to: .lodging)
        f.store.trips.setFixedArrival(trip.orderedStops[0], to: LocalTime(hour: 21, minute: 0))
        f.store.trips.setStartPlace(trip, to: home.id)
        let file = try #require(f.store.exportV2(tripID: trip.id))
        #expect(file.kind == .trip)
        let read = try ITERFileV2.decode(try file.encoded())
        #expect(read.trips == [try #require(f.store.trips.value(id: trip.id))])
        #expect(read.trips[0].startPlaceID == home.id && read.trips[0].stops[0].dwellMinutes == 30)
    }

    @Test func importAsCopyTwiceGivesTwoTrips() throws {
        let f = try StoreFixture(undoable: true)
        f.store.actionName = { $0.rawValue }
        let source = f.act { f.trip3() }
        let file = try #require(f.store.exportV1(tripID: source.id))
        let a = try #require(f.act { f.store.importAsCopy(.v1(file)) }.first)
        #expect(f.undo.undoActionName == "importTrip")
        let b = try #require(f.act { f.store.importAsCopy(.v1(file)) }.first)
        #expect(f.store.trips.all().count == 3)
        #expect(Set([source.id, a.id, b.id]).count == 3)
        #expect(a.value().stops.map(\.place.name) == source.value().stops.map(\.place.name))
        #expect(a.value().stops.map(\.session) == source.value().stops.map(\.session))
        #expect(Set(a.value().stops.map(\.id)).isDisjoint(with: b.value().stops.map(\.id)))
        #expect(f.count(PlaceRecord.self) == 4)
        f.undo.undo()
        #expect(f.store.trips.all().count == 2 && f.count(PlaceRecord.self) == 4)
    }

    @Test func importAsCopyOfAV2FileAlsoGivesNewTrips() throws {
        let f = try StoreFixture()
        let source = f.trip3()
        let file = try #require(f.store.exportV2(tripID: source.id))
        let a = try #require(f.store.importAsCopy(.v2(file)).first)
        let b = try #require(f.store.importAsCopy(.v2(file)).first)
        #expect(Set([source.id, a.id, b.id]).count == 3)
        #expect(f.store.trips.all().count == 3)
        #expect(a.value().stops.map(\.place.id) == source.value().stops.map(\.place.id))
        #expect(f.count(PlaceRecord.self) == 4 && f.count(StopRecord.self) == 12)
        #expect(!a.isPinned && a.createdAt >= source.createdAt)
    }

    @Test func importInFreshStoreCreatesPlaces() throws {
        let f = try StoreFixture()
        let mine = f.ownPlace("Pond")
        let trip = f.ownTrip("T")
        f.store.trips.addStop(mine.value(), to: trip, day: 0)
        f.store.trips.addStop(f.spot("bodie"), to: trip, day: 0)
        let file = try #require(f.store.exportV1(tripID: trip.id))
        let other = try StoreFixture()
        let imported = try #require(other.store.importAsCopy(.v1(file)).first)
        #expect(imported.value().stops.map(\.place.name) == ["Pond", CuratedSpots.spot(id: "bodie")!.name])
        other.store.importAsCopy(.v1(file))
        #expect(other.count(PlaceRecord.self) == 2)
    }
}

@MainActor
@Suite struct MergeStoreTests {
    /// A library with folders, pins, sort orders, own and curated places, and trips using the V5 fields.
    private func makeLibrary(_ f: StoreFixture) throws {
        let tripFolder = f.store.folders.create(name: "Autumn", kind: .trips)
        let placeFolder = f.store.folders.create(name: "Secret", kind: .locations)
        let pond = f.store.places.createUserSpot(name: "Pond", coordinate: Coordinate(latitude: 37, longitude: -118),
                                                 timeZoneIdentifier: "America/Los_Angeles", bestLight: [.sunrise])
        f.store.places.setSaved(f.spot("bodie"), true)
        f.store.folders.movePlaces([pond], to: placeFolder, index: nil)
        f.store.places.setPinned(pond, true)
        f.store.places.setSources(pond, to: ["osm"])
        f.store.places.setVerification(pond, to: .userPlaced)
        let one = f.trip3()
        f.store.trips.addStop(pond.value(), to: one, day: 1, at: 0)
        f.store.trips.setDwell(one.orderedStops(onDay: 1)[0], minutes: 40)
        f.store.trips.setKind(one.orderedStops(onDay: 2)[0], to: .waypoint)
        f.store.trips.setFixedArrival(one.orderedStops(onDay: 0)[1], to: LocalTime(hour: 19, minute: 30))
        f.store.trips.setStartPlace(one, to: pond.id)
        f.store.trips.setTransferTiming(one, intoDay: 2, to: .eveningBefore)
        let two = f.ownTrip("Two")
        let three = f.store.trips.create(from: TripTemplates.all[2], startDay: f.day)
        f.store.folders.moveTrips([two, three], to: tripFolder, index: nil)
        f.store.trips.setPinned(three, true)
        f.store.folders.setPinned(tripFolder, true)
    }

    private func normalised(_ file: ITERFileV2) -> (trips: [Trip], places: [Place], folders: [Folder], tombstones: [LibraryTombstone]) {
        (file.trips.sorted { $0.id.uuidString < $1.id.uuidString }, file.places.sorted { $0.id.uuidString < $1.id.uuidString },
         file.folders.sorted { $0.id.uuidString < $1.id.uuidString },
         file.tombstones.sorted { $0.id.uuidString < $1.id.uuidString })
    }

    @Test func mergingALibraryIntoAnEmptyStoreReproducesIt() throws {
        let a = try StoreFixture()
        try makeLibrary(a)
        let exported = try ITERFileV2.decode(a.store.exportLibrary().encoded())

        let b = try StoreFixture(undoable: true)
        b.store.actionName = { $0.rawValue }
        let plan = b.act { b.store.importMerging(exported) }
        #expect(plan.trips.inserts.count == 3 && plan.folders.inserts.count == 2)
        #expect(b.undo.undoActionName == "importTrip")

        let original = normalised(try ITERFileV2.decode(a.store.exportLibrary().encoded()))
        let copy = normalised(try ITERFileV2.decode(b.store.exportLibrary().encoded()))
        #expect(copy.trips == original.trips)
        #expect(copy.places == original.places)
        #expect(copy.folders == original.folders)
        #expect(copy.tombstones == original.tombstones)
        #expect(original.trips.count == 3 && original.folders.count == 2)
        // Pins, sort orders and links survive.
        #expect(b.store.trips.pinned().map(\.name) == ["Yosemite"])
        #expect(b.store.folders.pinned(kind: .trips).map(\.name) == ["Autumn"])
        #expect(b.store.places.pinned().map(\.name) == ["Pond"])
        #expect(b.store.trips.trips(in: try #require(b.store.folders.list(kind: .trips).first)).map(\.name) == ["Two", "Yosemite"])
        #expect(b.store.trips.all().flatMap { $0.orderedStops.map(\.sortOrder) }.sorted() == a.store.trips.all().flatMap { $0.orderedStops.map(\.sortOrder) }.sorted())

        // Undo takes all of it away again.
        b.undo.undo()
        #expect(b.count(TripRecord.self) == 0 && b.count(PlaceRecord.self) == 0 && b.count(FolderRecord.self) == 0 && b.count(StopRecord.self) == 0)
        b.undo.redo()
        #expect(normalised(b.store.exportLibrary()).trips == original.trips)
    }

    @Test func importingTheSameLibraryAgainChangesNothing() throws {
        let a = try StoreFixture()
        try makeLibrary(a)
        let exported = a.store.exportLibrary()
        let b = try StoreFixture(undoable: true)
        _ = b.act { b.store.importMerging(exported) }
        b.undo.removeAllActions()
        let revision = b.store.revision
        let plan = b.store.importMerging(exported)
        #expect(plan.isEmpty)
        #expect(b.store.revision == revision && !b.undo.canUndo)
        #expect(b.count(TripRecord.self) == 3 && b.count(PlaceRecord.self) == a.count(PlaceRecord.self))
    }

    @Test func anIncomingTombstoneDeletesAndUndoBringsItBack() throws {
        let a = try StoreFixture()
        let doomed = a.trip3()
        let kept = a.ownTrip("Kept")
        let b = try StoreFixture(undoable: true)
        _ = b.act { b.store.importMerging(a.store.exportLibrary()) }
        #expect(b.count(TripRecord.self) == 2)
        let before = normalised(b.store.exportLibrary())

        a.clock.advance(by: 100)
        a.store.trips.delete(doomed)
        let file = a.store.exportLibrary()
        #expect(file.tombstones.map(\.id) == [doomed.id])
        let plan = b.act { b.store.importMerging(file) }
        #expect(plan.trips.deletes == [doomed.id])
        #expect(b.store.trips.trip(id: doomed.id) == nil)
        #expect(b.store.trips.trip(id: kept.id) != nil)
        #expect(b.store.deletions.tombstone(.trip, id: doomed.id) != nil)
        #expect(b.count(StopRecord.self) == 0)

        // The deletion is not re-recorded or re-applied.
        #expect(b.store.importMerging(file).isEmpty)

        b.undo.undo()
        #expect(b.store.trips.trip(id: doomed.id) != nil && b.store.deletions.all().isEmpty)
        #expect(normalised(b.store.exportLibrary()).trips == before.trips)
    }

    @Test func anIncomingTombstoneDeletesAPlaceAndAFolder() throws {
        let a = try StoreFixture()
        try makeLibrary(a)
        let b = try StoreFixture()
        b.store.importMerging(a.store.exportLibrary())
        let pond = try #require(a.store.places.savedPlaces().first { $0.name == "Pond" })
        let folder = try #require(a.store.folders.list(kind: .locations).first)
        a.clock.advance(by: 100)
        a.store.places.deletePlace(pond)
        a.store.folders.delete(folder)
        b.store.importMerging(a.store.exportLibrary())
        #expect(b.store.places.place(id: pond.id) == nil && b.store.folders.folder(id: folder.id) == nil)
        #expect(b.store.deletions.all().count == 2)
        // No stop is left pointing at the deleted place.
        #expect(b.store.trips.all().allSatisfy { trip in trip.orderedStops.allSatisfy { $0.place != nil } })
        #expect(b.store.trips.all().flatMap(\.orderedStops).allSatisfy { $0.place?.id != pond.id })
    }

    @Test func anOlderIncomingRecordDoesNotOverwrite() throws {
        let a = try StoreFixture()
        let trip = a.trip3()
        let older = a.store.exportLibrary()
        let b = try StoreFixture()
        b.store.importMerging(older)
        let bTrip = try #require(b.store.trips.trip(id: trip.id))
        b.clock.advance(by: 1000)
        b.store.trips.rename(bTrip, to: "Newer here")
        b.store.trips.setNote(bTrip.orderedStops[0], to: "mine")
        let plan = b.store.importMerging(older)
        #expect(plan.isEmpty)
        #expect(bTrip.name == "Newer here" && bTrip.orderedStops[0].note == "mine")

        // A newer incoming one does, stops included, and the stale stop goes.
        a.clock.advance(by: 5000)
        a.store.trips.rename(trip, to: "Newest")
        a.store.trips.removeStop(trip.orderedStops[3])
        b.store.importMerging(a.store.exportLibrary())
        let after = try #require(b.store.trips.trip(id: trip.id))
        #expect(after.name == "Newest" && after.orderedStops.count == 3 && after.orderedStops[0].note == "")
        #expect(after.value() == a.store.trips.value(id: trip.id))
    }

    @Test func aCuratedPlaceTheStoreAlreadyHoldsIsNotDuplicated() throws {
        let a = try StoreFixture()
        _ = a.trip3()
        let b = try StoreFixture()
        b.store.places.setSaved(b.spot("mesa-arch"), true)
        let local = try #require(b.store.places.savedPlaces().first)
        b.store.importMerging(a.store.exportLibrary())
        #expect(b.count(PlaceRecord.self) == 4)
        let imported = try #require(b.store.trips.all().first)
        #expect(imported.orderedStops.count == 4)
        #expect(imported.orderedStops[0].place?.id == local.id)
        #expect(b.store.places.savedPlaces().map(\.id) == [local.id])
        // And importing again is still a no-op for the planner's view of the store.
        let again = b.store.importMerging(a.store.exportLibrary())
        #expect(again.trips.isEmpty && b.count(PlaceRecord.self) == 4)
    }

    @Test func aV1FileOfferedToMergeIsImportedAsACopy() throws {
        let f = try StoreFixture()
        let trip = f.trip3()
        let file = try #require(f.store.exportV1(tripID: trip.id))
        f.store.importMerging(.v1(file))
        f.store.importMerging(.v1(file))
        #expect(f.store.trips.all().count == 3)
        #expect(Set(f.store.trips.all().map(\.id)).count == 3)
    }
}
