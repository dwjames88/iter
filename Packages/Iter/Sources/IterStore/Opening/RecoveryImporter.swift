import Foundation
import SwiftData
import IterModel

/// Builds the recovered store's content from a backup folder's `.iter` v1 files (blueprint §5.3 step 5).
///
/// Trips and stops keep the ids in the file (the recovered store is a new file, so there is nothing to clash with, and
/// the plans stay comparable). Places are upserted like the old import did: curated places by slug, other places by
/// UUID, then by `externalID`. Folders, pins, the saved flag and sort order are not in an `.iter` v1 file, so they are
/// not recovered (they are still in the untouched original store and the raw backup copy).
enum RecoveryImporter {
    struct Result {
        var tripCount: Int
        var skipped: [String]
    }

    static func importBackup(from folder: URL, into container: ModelContainer, files: any StoreFileOperations,
                             now: Date) throws -> Result {
        let names = try files.contentsOfDirectory(at: folder)
            .filter { $0.pathExtension == ITERFileInfo.fileExtension }
            .map(\.lastPathComponent)
            .sorted()
        let context = ModelContext(container)
        var usedTripIDs = Set<UUID>(), usedStopIDs = Set<UUID>()
        var skipped: [String] = []
        var imported = 0
        for name in names {
            guard let data = try? files.read(folder.appending(path: name)),
                  let file = try? ITERFileV1.decode(data) else {
                skipped.append(name)
                continue
            }
            let trip = file.trip(makeID: { UUID() }, stamp: now)
            let tripRecord = TripRecord(id: usedTripIDs.insert(trip.id).inserted ? trip.id : UUID())
            context.insert(tripRecord)
            var stamped = trip
            stamped.sortOrder = Double(imported)
            stamped.createdAt = now
            stamped.updatedAt = now
            tripRecord.apply(stamped)
            var perDay: [Int: Double] = [:]
            for stop in trip.stops {
                let place = try upsert(stop.place, in: context)
                let record = StopRecord(id: usedStopIDs.insert(stop.id).inserted ? stop.id : UUID())
                context.insert(record)
                let position = perDay[stop.dayIndex, default: 0]
                perDay[stop.dayIndex] = position + 1
                record.apply(stop, sortOrder: position)
                record.trip = tripRecord
                record.place = place
            }
            imported += 1
        }
        try context.save()
        return Result(tripCount: imported, skipped: skipped)
    }

    private static func find(_ place: Place, in context: ModelContext) throws -> PlaceRecord? {
        if place.origin == .curated, let slug = place.curatedID {
            var descriptor = FetchDescriptor<PlaceRecord>(predicate: #Predicate { $0.curatedID == slug })
            descriptor.fetchLimit = 1
            return try context.fetch(descriptor).first
        }
        let id = place.id
        var byID = FetchDescriptor<PlaceRecord>(predicate: #Predicate { $0.id == id })
        byID.fetchLimit = 1
        if let found = try context.fetch(byID).first { return found }
        if let external = place.externalID {
            var byExternal = FetchDescriptor<PlaceRecord>(predicate: #Predicate { $0.externalID == external })
            byExternal.fetchLimit = 1
            return try context.fetch(byExternal).first
        }
        return nil
    }

    private static func upsert(_ place: Place, in context: ModelContext) throws -> PlaceRecord {
        if let existing = try find(place, in: context) {
            if place.origin == .curated {
                // A catalogue spot keeps what the user typed (name, locality, notes); the catalogue's facts refresh.
                let name = existing.name, locality = existing.locality, notes = existing.notes
                existing.applyContent(place)
                existing.name = name
                existing.locality = locality
                existing.notes = notes
            }
            return existing
        }
        let record = PlaceRecord(id: place.id)
        context.insert(record)
        record.apply(place)
        return record
    }
}
