import Foundation
import Testing
import IterModel
@testable import IterStore

private func file(trips: [Trip] = [], places: [Place] = [], folders: [Folder] = [],
                  tombstones: [LibraryTombstone] = []) -> ITERFileV2 {
    ITERFileV2.library(trips: trips, places: places, folders: folders, tombstones: tombstones, exportedAt: at(0))
}

@Suite("Library merge")
struct LibraryMergeTests {
    @Test func unknownIDsAreInserted() {
        let p = samplePlace(1)
        let t = sampleTrip(1, places: [p])
        let f = Folder(id: uuid(5), name: "F", updatedAt: at(1))
        let plan = MergePlan.plan(merging: file(trips: [t], folders: [f]), into: LibrarySnapshot())
        #expect(plan.trips.inserts == [t])
        #expect(plan.places.inserts == [p])
        #expect(plan.folders.inserts == [f])
        #expect(plan.trips.updates.isEmpty && plan.trips.deletes.isEmpty)
        #expect(plan.tombstonesToRecord.isEmpty)
    }

    @Test func incomingNewerWins() {
        let local = sampleTrip(1, updated: 10, name: "Local")
        let incoming = sampleTrip(1, updated: 20, name: "Incoming")
        let plan = MergePlan.plan(merging: file(trips: [incoming]), into: LibrarySnapshot(trips: [local]))
        #expect(plan.trips.updates == [incoming])
        #expect(plan.trips.inserts.isEmpty)
    }

    @Test func localNewerWins() {
        let local = sampleTrip(1, updated: 30, name: "Local")
        let incoming = sampleTrip(1, updated: 20, name: "Incoming")
        let plan = MergePlan.plan(merging: file(trips: [incoming]), into: LibrarySnapshot(trips: [local]))
        #expect(plan.trips.isEmpty)
    }

    @Test func tieKeepsLocal() {
        let local = sampleTrip(1, updated: 20, name: "Local")
        let incoming = sampleTrip(1, updated: 20, name: "Incoming")
        let plan = MergePlan.plan(merging: file(trips: [incoming]), into: LibrarySnapshot(trips: [local]))
        #expect(plan.isEmpty)
    }

    @Test func comparesAtMillisecondResolution() {
        var local = sampleTrip(1, updated: 10)
        var incoming = local
        local.updatedAt = Date(timeIntervalSince1970: 1_800_000_010.1234)
        incoming.updatedAt = Date(timeIntervalSince1970: 1_800_000_010.1230004)
        #expect(MergePlan.plan(merging: file(trips: [incoming]), into: LibrarySnapshot(trips: [local])).isEmpty)
        incoming.updatedAt = Date(timeIntervalSince1970: 1_800_000_010.125)
        #expect(MergePlan.plan(merging: file(trips: [incoming]), into: LibrarySnapshot(trips: [local])).trips.updates.count == 1)
    }

    @Test func tripAndStopsMergeAsOneUnit() {
        let local = sampleTrip(1, updated: 10, places: [samplePlace(1)])
        var incoming = sampleTrip(1, updated: 20, places: [samplePlace(1), samplePlace(2)])
        incoming.notes = "changed"
        let plan = MergePlan.plan(merging: file(trips: [incoming]), into: LibrarySnapshot(trips: [local]))
        #expect(plan.trips.updates.count == 1)
        #expect(plan.trips.updates[0].stops.count == 2, "the whole trip, stops included, is replaced")
    }

    @Test func placesAndFoldersFollowTheSameRule() {
        let lp = samplePlace(1, updated: 5), ip = samplePlace(1, updated: 9)
        let lf = Folder(id: uuid(5), name: "old", updatedAt: at(5)), inf = Folder(id: uuid(5), name: "new", updatedAt: at(9))
        let plan = MergePlan.plan(merging: file(places: [ip], folders: [inf]),
                                  into: LibrarySnapshot(places: [lp], folders: [lf]))
        #expect(plan.places.updates == [ip])
        #expect(plan.folders.updates == [inf])
    }

    @Test func incomingTombstoneDeletesOlderLocalRecord() {
        let local = sampleTrip(1, updated: 10)
        let t = LibraryTombstone(entity: .trip, id: uuid(1), deletedAt: at(20))
        let plan = MergePlan.plan(merging: file(tombstones: [t]), into: LibrarySnapshot(trips: [local]))
        #expect(plan.trips.deletes == [uuid(1)])
        #expect(plan.tombstonesToRecord == [t])
    }

    @Test func localEditNewerThanTombstoneSurvives() {
        let local = sampleTrip(1, updated: 30)
        let t = LibraryTombstone(entity: .trip, id: uuid(1), deletedAt: at(20))
        let plan = MergePlan.plan(merging: file(tombstones: [t]), into: LibrarySnapshot(trips: [local]))
        #expect(plan.trips.deletes.isEmpty)
        #expect(plan.tombstonesToRecord.isEmpty)
    }

    @Test func tombstoneForUnknownRecordIsRecorded() {
        let t = LibraryTombstone(entity: .place, id: uuid(1), deletedAt: at(20))
        let plan = MergePlan.plan(merging: file(tombstones: [t]), into: LibrarySnapshot())
        #expect(plan.places.deletes.isEmpty)
        #expect(plan.tombstonesToRecord == [t])
    }

    @Test func tombstoneDoesNotTouchAnotherEntityKind() {
        let t = LibraryTombstone(entity: .place, id: uuid(1), deletedAt: at(20))
        let plan = MergePlan.plan(merging: file(tombstones: [t]), into: LibrarySnapshot(trips: [sampleTrip(1, updated: 1)]))
        #expect(plan.trips.deletes.isEmpty)
    }

    @Test func localTombstoneSuppressesReinsert() {
        let incoming = sampleTrip(1, updated: 10)
        let lt = LibraryTombstone(entity: .trip, id: uuid(1), deletedAt: at(20))
        let plan = MergePlan.plan(merging: file(trips: [incoming]), into: LibrarySnapshot(tombstones: [lt]))
        #expect(plan.isEmpty)
    }

    @Test func incomingRecordNewerThanLocalTombstoneIsInsertedAndClearsIt() {
        let incoming = sampleTrip(1, updated: 30)
        let lt = LibraryTombstone(entity: .trip, id: uuid(1), deletedAt: at(20))
        let plan = MergePlan.plan(merging: file(trips: [incoming]), into: LibrarySnapshot(tombstones: [lt]))
        #expect(plan.trips.inserts == [incoming])
        #expect(plan.tombstonesToClear == [lt])
    }

    @Test func tombstoneInTheSameFileSuppressesAnOlderRecord() {
        let old = sampleTrip(1, updated: 10)
        let t = LibraryTombstone(entity: .trip, id: uuid(1), deletedAt: at(20))
        let plan = MergePlan.plan(merging: file(trips: [old], tombstones: [t]), into: LibrarySnapshot())
        #expect(plan.trips.inserts.isEmpty)
        #expect(plan.tombstonesToRecord == [t])
    }

    @Test func alreadyHeldTombstoneIsNotRecordedAgain() {
        let t = LibraryTombstone(entity: .trip, id: uuid(1), deletedAt: at(20))
        let plan = MergePlan.plan(merging: file(tombstones: [t]), into: LibrarySnapshot(tombstones: [t]))
        #expect(plan.isEmpty)
    }

    @Test func asCopyGivesNewIDsAndTouchesNothingElse() {
        let p = samplePlace(1)
        let t = sampleTrip(1, updated: 50, places: [p, samplePlace(2)])
        let ids = IDSequence()
        let tomb = LibraryTombstone(entity: .trip, id: uuid(9), deletedAt: at(60))
        let snapshot = LibrarySnapshot(trips: [sampleTrip(1, updated: 10), sampleTrip(9, updated: 1)], places: [p])
        let plan = MergePlan.asCopy(of: file(trips: [t], tombstones: [tomb]), into: snapshot, makeID: ids.make)
        let copy = plan.trips.inserts[0]
        #expect(plan.trips.inserts.count == 1 && plan.trips.updates.isEmpty && plan.trips.deletes.isEmpty)
        #expect(copy.id != t.id && copy.stops.map(\.id) != t.stops.map(\.id))
        #expect(Set(copy.stops.map(\.id)).count == 2)
        #expect(copy.name == t.name && copy.stops.map(\.place.id) == t.stops.map(\.place.id))
        #expect(plan.places.inserts.map(\.id) == [uuid(2)], "known place is not duplicated; the new one is added")
        #expect(plan.tombstonesToRecord.isEmpty)
        #expect(copy.id == IDSequence(start: 1).make())
    }
}
