import Foundation
import IterModel
import SwiftData

// Helpers the repositories share. Call only inside `perform`.

extension LibraryStore {
    func makeTrip(name: String, startDay: LocalDay, dayCount: Int) -> TripRecord {
        let trip = TripRecord()
        context.insert(trip)
        touchNew(trip: trip.id)
        let now = clock()
        trip.name = name
        trip.startDay = startDay
        trip.dayCount = max(1, dayCount)
        trip.createdAt = now
        trip.updatedAt = now
        trip.sortOrder = firstSortOrder(unfiledTripsExcluding: trip.id)
        return trip
    }

    func makeTrip(from template: TripTemplate, startDay: LocalDay, name: String) -> TripRecord {
        let trip = makeTrip(name: name, startDay: startDay, dayCount: template.dayCount)
        for entry in template.stops {
            guard let place = CuratedSpots.spot(id: entry.spotID) else { continue }
            insertStop(place: upsertPlace(for: place), in: trip, day: entry.dayIndex, session: entry.session, index: nil)
        }
        return trip
    }

    @discardableResult
    func insertStop(place: PlaceRecord, in trip: TripRecord, day: Int, session: LightWindowKind, index: Int?) -> StopRecord {
        let stop = StopRecord()
        context.insert(stop)
        stop.trip = trip
        stop.place = place
        stop.dayIndex = clampDay(day, in: trip)
        stop.session = session
        var list = trip.orderedStops(onDay: stop.dayIndex).filter { $0.id != stop.id }
        list.insert(stop, at: clampIndex(index, count: list.count))
        renumber(list)
        trip.updatedAt = clock()
        return stop
    }

    /// Deletes a stop and unlinks it first, so the trip's and the place's `stops` no longer list it before the next save.
    func deleteStop(_ stop: StopRecord) {
        stop.trip = nil
        stop.place = nil
        context.delete(stop)
    }

    /// Renumbers trips 0... in the given order, touching those that change.
    func renumber(_ trips: [TripRecord]) {
        for (i, trip) in trips.enumerated() where trip.sortOrder != Double(i) {
            touch(trip)
            trip.sortOrder = Double(i)
        }
    }

    func renumber(_ stops: [StopRecord]) {
        for (i, stop) in stops.enumerated() where stop.sortOrder != Double(i) { stop.sortOrder = Double(i) }
    }

    func clampDay(_ day: Int, in trip: TripRecord) -> Int { min(max(0, day), max(0, trip.dayCount - 1)) }
    func clampIndex(_ index: Int?, count: Int) -> Int { min(max(0, index ?? count), count) }

    /// Deletes a place nothing refers to: not saved, not a user place, no stops other than those being deleted.
    /// Not tombstoned: it is a cache of what a trip used, not something the user deleted.
    func pruneIfOrphaned(_ place: PlaceRecord, excludingStops excluded: Set<UUID>) {
        guard !place.isSaved, place.origin != .user else { return }
        guard (place.stops ?? []).allSatisfy({ excluded.contains($0.id) }) else { return }
        touch(place)
        context.delete(place)
    }

    // MARK: Finding and creating places

    /// The record for a place value: a curated place by its slug, any other by id, then by MapKit identifier.
    func findPlace(for place: Place) -> PlaceRecord? {
        if place.origin == .curated, let slug = place.curatedID { return findPlace(curatedID: slug) }
        if let found = placeRecord(id: place.id) { return found }
        if let external = place.externalID { return findPlace(externalID: external) }
        return nil
    }

    func findPlace(curatedID slug: String) -> PlaceRecord? {
        var descriptor = FetchDescriptor<PlaceRecord>(predicate: #Predicate { $0.curatedID == slug })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func findPlace(externalID external: String) -> PlaceRecord? {
        var descriptor = FetchDescriptor<PlaceRecord>(predicate: #Predicate { $0.externalID == external })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// The old id string a spot carried: the slug for a catalogue spot, else a UUID string or a MapKit identifier.
    func findPlace(spotID: String, curated: Bool) -> PlaceRecord? {
        if curated { return findPlace(curatedID: spotID) }
        if let uuid = UUID(uuidString: spotID), let found = placeRecord(id: uuid) { return found }
        return findPlace(externalID: spotID)
    }

    /// Finds the record for a place or creates it. A saved catalogue place keeps what the user typed (name, locality,
    /// notes) and the provenance it gathered; the catalogue's facts refresh.
    func upsertPlace(for place: Place) -> PlaceRecord {
        if let existing = findPlace(for: place) {
            touch(existing)
            if place.origin == .curated {
                let name = existing.name, locality = existing.locality, notes = existing.notes
                let sources = existing.sourcesRaw, citations = existing.citationsJSON
                let verification = existing.verificationRaw, discovered = existing.discoveredAt
                let horizon = existing.horizonJSON
                existing.applyContent(place)
                existing.name = name
                existing.locality = locality
                existing.notes = notes
                existing.sourcesRaw = sources
                existing.citationsJSON = citations
                existing.verificationRaw = verification
                existing.discoveredAt = discovered
                existing.horizonJSON = horizon
            }
            return existing
        }
        // A catalogue place gets its own record id; any other keeps the id it came with.
        let record = PlaceRecord(id: place.origin == .curated ? UUID() : place.id)
        context.insert(record)
        touchNew(place: record.id)
        record.applyContent(place)
        let now = clock()
        record.createdAt = now
        record.updatedAt = now
        record.isSaved = place.origin == .user
        return record
    }

    /// Saved places and every user place, unordered. Filtered in the store so a library of thousands of cached
    /// Apple Maps places (used by stops but not saved) is never materialised.
    func savedAndUserPlaces() -> [PlaceRecord] {
        let user = PlaceOrigin.user.rawValue
        let descriptor = FetchDescriptor<PlaceRecord>(predicate: #Predicate { $0.isSaved || $0.originRaw == user })
        return (try? context.fetch(descriptor)) ?? []
    }
}
