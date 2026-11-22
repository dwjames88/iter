import Foundation
import IterModel
import SwiftData

/// Saved places, your own places and the provenance a discovered place carries. Every mutation is one named undo group.
@MainActor
public struct PlaceRepository {
    unowned let store: LibraryStore

    // MARK: Fetching

    public func place(id: UUID) -> PlaceRecord? { store.placeRecord(id: id) }

    public func value(id: UUID) -> Place? { store.placeRecord(id: id)?.value() }

    /// Saved places plus every own place, one list, most recently changed first.
    public func savedPlaces() -> [PlaceRecord] {
        store.savedAndUserPlaces()
            .sorted { ($0.updatedAt, $0.id.uuidString) > ($1.updatedAt, $1.id.uuidString) }
    }

    public func savedValues() -> [Place] { savedPlaces().map { $0.value() } }

    /// Saved and own places filed in `folder`, ordered.
    public func savedPlaces(in folder: FolderRecord) -> [PlaceRecord] {
        store.savedAndUserPlaces().filter { $0.folder?.id == folder.id }.sorted(by: LibraryStore.placeOrder)
    }

    /// Pinned places that are still saved (or your own), in the order they were pinned.
    public func pinned() -> [PlaceRecord] {
        let pinned = (try? store.context.fetch(FetchDescriptor<PlaceRecord>(predicate: #Predicate { $0.isPinned }))) ?? []
        return pinned.filter { $0.isSaved || $0.origin == .user }.sorted {
            ($0.pinnedAt ?? .distantFuture, $0.id.uuidString) < ($1.pinnedAt ?? .distantFuture, $1.id.uuidString)
        }
    }

    /// Whether the place with this old-style id (a catalogue slug, a UUID string or a MapKit identifier) is saved or
    /// your own.
    public func isSaved(spotID: String) -> Bool {
        guard let record = store.findPlace(spotID: spotID, curated: CuratedSpots.spot(id: spotID) != nil) else { return false }
        return record.isSaved || record.origin == .user
    }

    public func isSaved(_ place: Place) -> Bool { editableRecord(for: place) != nil }

    /// The record behind a place the user can edit: one they added, or any place saved to Locations. nil for a place
    /// that is only a search result or a catalogue entry.
    public func editableRecord(for place: Place) -> PlaceRecord? {
        guard let record = store.findPlace(for: place), record.isSaved || record.origin == .user else { return nil }
        return record
    }

    /// The place as the store has it now, so a page or card opened before an edit shows the edit. Unsaved places are
    /// as given.
    public func current(_ place: Place) -> Place {
        editableRecord(for: place)?.value() ?? place
    }

    // MARK: Saving and creating

    public func setSaved(_ place: Place, _ saved: Bool) {
        let existing = store.findPlace(for: place)
        if saved, existing?.isSaved == true { return }
        if !saved, existing == nil || existing?.isSaved == false { return }
        store.perform(.setSaved) {
            if saved {
                let record = store.upsertPlace(for: place)
                record.isSaved = true
                record.updatedAt = store.clock()
            } else if let record = existing {
                store.touch(record)
                record.isSaved = false
                record.folder = nil
                record.updatedAt = store.clock()
                store.pruneIfOrphaned(record, excludingStops: [])
            }
        }
    }

    @discardableResult
    public func createUserSpot(name: String, locality: String = "", coordinate: Coordinate, timeZoneIdentifier: String,
                               category: PlaceCategory = .landscape, bestLight: [BestLight] = [],
                               notes: String = "", walkInMinutes: Int? = nil) -> PlaceRecord {
        store.perform(.createUserSpot) {
            let place = PlaceRecord()
            store.context.insert(place)
            store.touchNew(place: place.id)
            let now = store.clock()
            place.origin = .user
            place.name = name
            place.locality = locality
            place.coordinate = coordinate
            place.timeZoneIdentifier = timeZoneIdentifier
            place.category = category
            place.bestLight = bestLight
            place.notes = notes
            place.walkInMinutes = walkInMinutes
            place.isSaved = true
            place.createdAt = now
            place.updatedAt = now
            return place
        }
    }

    // MARK: Editing

    /// Edits a place. Only the arguments you pass change; pass `.some(nil)` for `walkInMinutes` to clear it (unknown).
    public func updatePlace(_ place: PlaceRecord, name: String? = nil, locality: String? = nil, coordinate: Coordinate? = nil,
                            timeZoneIdentifier: String? = nil, category: PlaceCategory? = nil, bestLight: [BestLight]? = nil,
                            blurb: String? = nil, notes: String? = nil, walkInMinutes: Int?? = nil) {
        store.perform(.updatePlace) {
            store.touch(place)
            if let name { place.name = name }
            if let locality { place.locality = locality }
            if let coordinate { place.coordinate = coordinate }
            if let timeZoneIdentifier { place.timeZoneIdentifier = timeZoneIdentifier }
            if let category { place.category = category }
            if let bestLight { place.bestLight = bestLight }
            if let blurb { place.blurb = blurb }
            if let notes { place.notes = notes }
            if let walkInMinutes { place.walkInMinutes = walkInMinutes }
            place.updatedAt = store.clock()
        }
    }

    /// Moves one of your own places to `coordinate` and nothing else (drag, Adjust Location, typed or pasted
    /// coordinates). The coordinate is the caller's, exactly: no lookup result ever replaces it.
    public func moveSpot(_ place: PlaceRecord, to coordinate: Coordinate) {
        guard place.origin == .user, place.coordinate != coordinate else { return }
        store.perform(.moveSpot) {
            store.touch(place)
            place.coordinate = coordinate
            place.updatedAt = store.clock()
        }
    }

    /// The same by the record's UUID string. False when there is no such place of yours.
    @discardableResult
    public func moveSpot(id: String, to coordinate: Coordinate) -> Bool {
        guard let uuid = UUID(uuidString: id), let place = store.placeRecord(id: uuid), place.origin == .user else { return false }
        moveSpot(place, to: coordinate)
        return true
    }

    /// Applies an edit from the place editor as ONE undo step. Fields that are the catalogue's (see
    /// `PlaceEdit.editsFacts`) are left alone for a curated place. Returns whether anything changed; an edit that
    /// changes nothing is not an undo step.
    @discardableResult
    public func editPlace(_ place: PlaceRecord, _ edit: PlaceEdit) -> Bool {
        let facts = PlaceEdit.editsFacts(of: place.origin)
        let target = edit.folderID.flatMap { id in store.folderRecord(id: id).flatMap { $0.kind == .locations ? $0 : nil } }
        let current = PlaceEdit(place)
        var wanted = edit
        if !facts {
            wanted.category = current.category
            wanted.bestLight = current.bestLight
            wanted.tags = current.tags
            wanted.walkInMinutes = current.walkInMinutes
            wanted.coordinate = current.coordinate
            wanted.timeZoneIdentifier = current.timeZoneIdentifier
        }
        wanted.folderID = target?.id
        guard wanted != current else { return false }
        store.perform(.updatePlace) {
            store.touch(place)
            let contentChanged = wanted.name != current.name || wanted.locality != current.locality || wanted.notes != current.notes
                || wanted.category != current.category || wanted.bestLight != current.bestLight || wanted.tags != current.tags
                || wanted.walkInMinutes != current.walkInMinutes || wanted.coordinate != current.coordinate
                || wanted.timeZoneIdentifier != current.timeZoneIdentifier
            place.name = wanted.name
            place.locality = wanted.locality
            place.notes = wanted.notes
            place.category = wanted.category
            place.bestLight = wanted.bestLight
            place.tags = wanted.tags
            place.walkInMinutes = wanted.walkInMinutes
            place.coordinate = wanted.coordinate
            place.timeZoneIdentifier = wanted.timeZoneIdentifier
            if wanted.folderID != current.folderID {
                place.folder = target
                place.sortOrder = target.map { store.nextPlaceSortOrder(in: $0) } ?? 0
            }
            if wanted.isPinned != current.isPinned {
                place.isPinned = wanted.isPinned
                place.pinnedAt = wanted.isPinned ? store.clock() : nil
            }
            if contentChanged { place.updatedAt = store.clock() }
        }
        return true
    }

    /// Deletes a place and every stop that used it, and writes a tombstone; undo brings all of it back.
    public func deletePlace(_ place: PlaceRecord) {
        store.perform(.deletePlace) {
            store.touch(place)
            for stop in place.stops ?? [] {
                if let trip = stop.trip {
                    store.touch(trip)
                    trip.updatedAt = store.clock()
                }
                store.deleteStop(stop)
            }
            store.writeTombstone(.place, id: place.id)
            store.context.delete(place)
        }
    }

    /// Pins or unpins a place to the sidebar's Locations section.
    public func setPinned(_ place: PlaceRecord, _ pinned: Bool) {
        guard place.isPinned != pinned else { return }
        store.perform(pinned ? .pinPlace : .unpinPlace) {
            store.touch(place)
            place.isPinned = pinned
            place.pinnedAt = pinned ? store.clock() : nil
        }
    }

    // MARK: Provenance

    public func setSources(_ place: PlaceRecord, to sources: [SourceID]) {
        let raw = sources.map(\.rawValue).joined(separator: ",")
        guard place.sourcesRaw != raw else { return }
        editProvenance(place) { $0.sourcesRaw = raw }
    }

    public func setCitations(_ place: PlaceRecord, to citations: [Citation]) {
        let json = citations.isEmpty ? "" : RecordJSON.string(citations)
        guard place.citationsJSON != json else { return }
        editProvenance(place) { $0.citationsJSON = json }
    }

    /// How well the place is established; nil = not recorded. `discoveredAt` is set with it when given.
    public func setVerification(_ place: PlaceRecord, to verification: Verification?, discoveredAt: Date? = nil) {
        let raw = verification?.rawValue ?? ""
        guard place.verificationRaw != raw || (discoveredAt != nil && place.discoveredAt != discoveredAt) else { return }
        editProvenance(place) {
            $0.verificationRaw = raw
            if let discoveredAt { $0.discoveredAt = discoveredAt }
        }
    }

    /// The cached horizon profile; nil clears it.
    public func setHorizon(_ place: PlaceRecord, to horizon: HorizonProfile?) {
        let json = horizon.map { RecordJSON.string($0) } ?? ""
        guard place.horizonJSON != json else { return }
        editProvenance(place) { $0.horizonJSON = json }
    }

    private func editProvenance(_ place: PlaceRecord, _ edit: (PlaceRecord) -> Void) {
        store.perform(.setPlaceProvenance) {
            store.touch(place)
            edit(place)
            place.updatedAt = store.clock()
        }
    }
}
