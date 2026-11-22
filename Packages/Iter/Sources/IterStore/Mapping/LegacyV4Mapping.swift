import Foundation
import IterModel

// The frozen V4 records to values, for the backup's `.iter` export. Same rules as `RecordMapping`, minus the V5 fields.

extension IterSchemaV4.PlaceRecord {
    func value() -> Place {
        Place(id: id, curatedID: curatedID, externalID: externalID, name: name, locality: locality,
              coordinate: Coordinate(latitude: latitude, longitude: longitude), timeZoneIdentifier: timeZoneIdentifier,
              category: PlaceCategory(rawValue: categoryRaw) ?? .landscape,
              bestLight: bestLightRaw.split(separator: ",").compactMap { BestLight(rawValue: String($0)) },
              facing: facing, blurb: blurb, notes: notes, walkInMinutes: walkInMinutes, elevationMeters: elevationMeters,
              popularity: popularity, tags: tagsRaw.split(separator: ",").map(String.init),
              origin: PlaceOrigin(rawValue: originRaw) ?? .user, isSaved: isSaved, folderID: folder?.id,
              sortOrder: sortOrder, isPinned: isPinned, pinnedAt: pinnedAt, createdAt: createdAt, updatedAt: updatedAt)
    }
}

extension IterSchemaV4.StopRecord {
    func value() -> Stop? {
        guard let place else { return nil }
        return Stop(id: id, place: place.value(), dayIndex: dayIndex,
                    session: LightWindowKind(rawValue: sessionRaw) ?? .goldenEvening,
                    setUpBufferMinutes: setUpBufferMinutes, note: note, driveNote: driveNote)
    }
}

extension IterSchemaV4.FolderRecord {
    func value() -> Folder {
        Folder(id: id, name: name, kind: FolderKind(rawValue: kindRaw) ?? .trips, sortOrder: sortOrder,
               createdAt: createdAt, updatedAt: updatedAt, isPinned: isPinned, pinnedAt: pinnedAt)
    }
}

extension IterSchemaV4.TripRecord {
    var orderedStops: [IterSchemaV4.StopRecord] {
        (stops ?? []).sorted {
            ($0.dayIndex, $0.sortOrder, $0.id.uuidString) < ($1.dayIndex, $1.sortOrder, $1.id.uuidString)
        }
    }

    func value() -> Trip {
        Trip(id: id, name: name, startDay: LocalDay(iso: startDayISO) ?? Fallback.startDay, dayCount: dayCount,
             stops: orderedStops.compactMap { $0.value() }, notes: notes,
             transferTimings: TransferTimingsCodec.parse(transferTimingsRaw, dayCount: dayCount), folderID: folder?.id,
             sortOrder: sortOrder, isPinned: isPinned, pinnedAt: pinnedAt, createdAt: createdAt, updatedAt: updatedAt)
    }
}
