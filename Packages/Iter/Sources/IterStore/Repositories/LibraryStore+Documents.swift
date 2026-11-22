import Foundation
import IterModel
import SwiftData

// `.iter` import and export through the store. Reading a file into a value is `Documents/`; deciding what a merge does
// is `MergePlan`; this applies the result to the records, as one undo group.

extension LibraryStore {
    // MARK: Export

    /// One trip as a v1 file (the format every older Iter reads). nil when there is no such trip.
    public func exportV1(tripID: UUID) -> ITERFileV1? {
        flush()
        return trips.value(id: tripID).map { ITERFileV1(trip: $0, exportedAt: clock()) }
    }

    /// One trip as a v2 file, with the places its stops use. nil when there is no such trip.
    public func exportV2(tripID: UUID) -> ITERFileV2? {
        flush()
        return trips.value(id: tripID).map { ITERFileV2.trip($0, exportedAt: clock()) }
    }

    /// Everything: all trips, the saved and own places (and every place a trip uses), folders and tombstones.
    public func exportLibrary() -> ITERFileV2 {
        flush()
        let snapshot = librarySnapshot()
        return ITERFileV2.library(trips: snapshot.trips, places: savedAndUserPlaces().map { $0.value() },
                                  folders: snapshot.folders, tombstones: snapshot.tombstones, exportedAt: clock())
    }

    /// What the store holds, as values: the input to the merge planner.
    public func librarySnapshot() -> LibrarySnapshot {
        LibrarySnapshot(trips: allTrips().map { $0.value() }, places: allPlaces().map { $0.value() },
                        folders: allFolders().map { $0.value() }, tombstones: deletions.all())
    }

    // MARK: Import

    /// Imports every trip in the file as a NEW trip (new ids), as one undo group "importTrip". Importing the same file
    /// twice gives two trips. Places are matched by catalogue slug, then id, then MapKit identifier, and created when
    /// there is no match. Returns the new trips.
    @discardableResult
    public func importAsCopy(_ file: ITERFile) -> [TripRecord] {
        switch file {
        case .v1(let v1):
            let trip = v1.trip(stamp: clock())
            return perform(.importTrip) {
                let record = makeTrip(name: trip.name, startDay: trip.startDay, dayCount: trip.dayCount)
                record.notes = trip.notes
                record.transferTimings = trip.transferTimings.filter { $0.key < record.dayCount }
                for stop in trip.stops {
                    let place = upsertPlace(for: stop.place)
                    let new = insertStop(place: place, in: record, day: stop.dayIndex, session: stop.session, index: nil)
                    new.setUpBufferMinutes = stop.setUpBufferMinutes
                    new.note = stop.note
                    new.driveNote = stop.driveNote
                }
                return [record]
            }
        case .v2(let v2):
            let plan = MergePlan.asCopy(of: v2, into: librarySnapshot())
            guard !plan.isEmpty else { return [] }
            return perform(.importTrip) { apply(plan, asCopy: true) }
        }
    }

    /// Merges a v2 file into the store by id (newer `updatedAt` wins, tombstones delete), as one undo group
    /// "importTrip". A trip and its stops are one unit. Returns the plan that was applied; an empty plan changes nothing
    /// and is not an undo step.
    @discardableResult
    public func importMerging(_ file: ITERFileV2) -> MergePlan {
        let plan = MergePlan.plan(merging: file, into: librarySnapshot())
        guard !plan.isEmpty else { return plan }
        perform(.importTrip) { apply(plan, asCopy: false) }
        return plan
    }

    /// A v2 file merges; a v1 file (one trip, no ids to merge by) is imported as a copy.
    @discardableResult
    public func importMerging(_ file: ITERFile) -> MergePlan {
        switch file {
        case .v2(let v2): return importMerging(v2)
        case .v1:
            importAsCopy(file)
            return MergePlan()
        }
    }

    // MARK: Applying a plan (call only inside `perform`)

    private func apply(_ plan: MergePlan, asCopy: Bool) -> [TripRecord] {
        // Folders first, so places and trips can link to them.
        for folder in plan.folders.inserts + plan.folders.updates {
            let record: FolderRecord
            if let existing = folderRecord(id: folder.id) {
                touch(existing)
                record = existing
            } else {
                record = FolderRecord(id: folder.id)
                context.insert(record)
                touchNew(folder: folder.id)
            }
            record.apply(folder)
        }

        // Places. A catalogue place the store already holds under another id is the same place: stops use that record.
        var alias: [UUID: PlaceRecord] = [:]
        for place in plan.places.inserts + plan.places.updates {
            let record: PlaceRecord
            if let existing = placeRecord(id: place.id) {
                touch(existing)
                record = existing
            } else if place.origin == .curated, let slug = place.curatedID, let local = findPlace(curatedID: slug) {
                alias[place.id] = local
                continue
            } else {
                record = PlaceRecord(id: place.id)
                context.insert(record)
                touchNew(place: place.id)
            }
            record.apply(place)
            record.folder = place.folderID.flatMap { folderRecord(id: $0) }
        }
        let resolve: (Place) -> PlaceRecord? = { alias[$0.id] ?? self.placeRecord(id: $0.id) }

        // Trips, each with its stops as one unit.
        var written: [TripRecord] = []
        for trip in plan.trips.inserts + plan.trips.updates {
            written.append(writeTrip(trip, resolving: resolve, asCopy: asCopy))
        }

        // Deletions.
        for id in plan.trips.deletes {
            guard let trip = tripRecord(id: id) else { continue }
            touch(trip)
            let doomed = Set((trip.stops ?? []).map(\.id))
            let places = (trip.stops ?? []).compactMap(\.place)
            context.delete(trip)
            for place in places { pruneIfOrphaned(place, excludingStops: doomed) }
        }
        for id in plan.places.deletes {
            guard let place = placeRecord(id: id) else { continue }
            touch(place)
            for stop in place.stops ?? [] {
                if let trip = stop.trip { touch(trip) }
                deleteStop(stop)
            }
            context.delete(place)
        }
        for id in plan.folders.deletes {
            guard let folder = folderRecord(id: id) else { continue }
            touch(folder)
            for trip in folder.trips ?? [] {
                touch(trip)
                trip.folder = nil
            }
            for place in folder.places ?? [] {
                touch(place)
                place.folder = nil
            }
            context.delete(folder)
        }

        // Tombstones.
        for tombstone in plan.tombstonesToClear {
            let key = TombstoneKey(entityRaw: tombstone.entity.rawValue, entityID: tombstone.id)
            touch(tombstone: key)
            if let record = tombstoneRecord(key) { context.delete(record) }
        }
        for tombstone in plan.tombstonesToRecord {
            let key = TombstoneKey(entityRaw: tombstone.entity.rawValue, entityID: tombstone.id)
            touch(tombstone: key)
            setTombstone(key, deletedAt: tombstone.deletedAt)
        }
        return written
    }

    /// Inserts or replaces one trip and all its stops from a value. A stop whose place cannot be found is left out.
    private func writeTrip(_ trip: Trip, resolving resolve: (Place) -> PlaceRecord?, asCopy: Bool) -> TripRecord {
        let record: TripRecord
        if let existing = tripRecord(id: trip.id) {
            touch(existing)
            record = existing
        } else {
            record = TripRecord(id: trip.id)
            context.insert(record)
            touchNew(trip: trip.id)
        }
        record.apply(trip)
        record.folder = trip.folderID.flatMap { folderRecord(id: $0) }
        var existingStops = Dictionary((record.stops ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var perDay: [Int: Int] = [:]
        for stop in trip.stops {
            guard let place = resolve(stop.place) else { continue }
            let index = perDay[stop.dayIndex, default: 0]
            perDay[stop.dayIndex] = index + 1
            let stopRecord = existingStops.removeValue(forKey: stop.id) ?? {
                let new = StopRecord(id: stop.id)
                context.insert(new)
                return new
            }()
            stopRecord.apply(stop, sortOrder: Double(index))
            stopRecord.trip = record
            stopRecord.place = place
        }
        for leftover in existingStops.values { deleteStop(leftover) }
        if asCopy {
            let now = clock()
            record.createdAt = now
            record.updatedAt = now
            record.isPinned = false
            record.pinnedAt = nil
            record.sortOrder = record.folder.map { _ in nextTripSortOrder(in: record.folder) }
                ?? firstSortOrder(unfiledTripsExcluding: record.id)
        }
        return record
    }
}
