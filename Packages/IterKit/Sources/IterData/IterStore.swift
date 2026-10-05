import Foundation
import Observation
import OSLog
import SwiftData
import IterCore

/// Every mutation the store performs; each registers one undo group named by `IterStore.actionName`.
public enum StoreAction: String, Sendable, CaseIterable {
    case createTrip, createTripFromTemplate, renameTrip, setTripNotes, setDates, duplicateTrip, deleteTrip, importTrip
    case addStop, removeStop, moveStop, reorderStops, setSession, setNote, setBuffer
    case setSaved, createUserSpot, updatePlace, deletePlace
}

/// The only way the app changes data. Main-actor, small-data (hundreds of rows), saves after every edit.
///
/// Undo: each mutation snapshots the trips and places it touches before and after, and registers an undo on
/// `undoManager` that restores the "before" snapshots (recreating deleted records with the same IDs and
/// relationships). The undo registers the redo the same way. The SwiftData container must be attached to the UI
/// with model-context undo disabled, otherwise undo would be applied twice.
@MainActor @Observable
public final class IterStore {
    @ObservationIgnored public let container: ModelContainer
    @ObservationIgnored public var context: ModelContext
    /// The window's undo manager. Held weakly; when nil, edits are simply not undoable.
    @ObservationIgnored public weak var undoManager: UndoManager?
    /// Localized undo menu names. The app injects the real ones.
    @ObservationIgnored public var actionName: @MainActor (StoreAction) -> String = { $0.rawValue }

    /// Incremented after every change (including undo and redo) so view models can observe the store.
    public private(set) var revision = 0
    /// The most recent save failure, if any.
    @ObservationIgnored public private(set) var lastSaveError: (any Error)?

    @ObservationIgnored private var pending: StoreState?
    @ObservationIgnored private let log = Logger(subsystem: "com.dwjames.iter", category: "IterStore")

    public init(container: ModelContainer) {
        self.container = container
        self.context = container.mainContext
        context.undoManager = nil
    }

    // MARK: - Fetching

    public func trips() -> [TripRecord] {
        let all = (try? context.fetch(FetchDescriptor<TripRecord>())) ?? []
        return all.sorted { ($0.updatedAt, $0.id.uuidString) > ($1.updatedAt, $1.id.uuidString) }
    }

    public func trip(id: UUID) -> TripRecord? {
        var descriptor = FetchDescriptor<TripRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    public func place(id: UUID) -> PlaceRecord? {
        var descriptor = FetchDescriptor<PlaceRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: - Trips

    @discardableResult
    public func createTrip(name: String, startDay: LocalDay, dayCount: Int) -> TripRecord {
        perform(.createTrip) { makeTrip(name: name, startDay: startDay, dayCount: dayCount) }
    }

    @discardableResult
    public func createTrip(from template: TripTemplate, startDay: LocalDay) -> TripRecord {
        perform(.createTripFromTemplate) { makeTrip(from: template, startDay: startDay, name: template.defaultName) }
    }

    public func renameTrip(_ trip: TripRecord, to name: String) {
        guard trip.name != name else { return }
        perform(.renameTrip) {
            touch(trip)
            trip.name = name
            trip.updatedAt = .now
        }
    }

    public func setNotes(_ trip: TripRecord, to notes: String) {
        guard trip.notes != notes else { return }
        perform(.setTripNotes) {
            touch(trip)
            trip.notes = notes
            trip.updatedAt = .now
        }
    }

    /// Changes the dates. Stops beyond the new last day move to the last day, keeping their order.
    /// Returns how many stops moved.
    @discardableResult
    public func setDates(_ trip: TripRecord, startDay: LocalDay, dayCount: Int) -> Int {
        perform(.setDates) {
            touch(trip)
            let count = max(1, dayCount)
            let last = count - 1
            let ordered = trip.orderedStops
            let displaced = ordered.filter { $0.dayIndex > last }
            trip.startDay = startDay
            trip.dayCount = count
            if !displaced.isEmpty {
                let kept = ordered.filter { $0.dayIndex == last }
                for stop in displaced { stop.dayIndex = last }
                renumber(kept + displaced)
            }
            trip.updatedAt = .now
            return displaced.count
        }
    }

    /// A copy with new IDs that shares the same places. `name` defaults to the original's.
    @discardableResult
    public func duplicateTrip(_ trip: TripRecord, name: String? = nil) -> TripRecord {
        perform(.duplicateTrip) {
            let copy = makeTrip(name: name ?? trip.name, startDay: trip.startDay, dayCount: trip.dayCount)
            copy.notes = trip.notes
            for stop in trip.orderedStops {
                let new = StopRecord()
                context.insert(new)
                new.trip = copy
                new.place = stop.place
                new.dayIndex = stop.dayIndex
                new.sortOrder = stop.sortOrder
                new.sessionRaw = stop.sessionRaw
                new.setUpBufferMinutes = stop.setUpBufferMinutes
                new.note = stop.note
            }
            return copy
        }
    }

    public func deleteTrip(_ trip: TripRecord) {
        perform(.deleteTrip) {
            touch(trip)
            let doomed = Set((trip.stops ?? []).map(\.id))
            let places = (trip.stops ?? []).compactMap(\.place)
            context.delete(trip)
            for place in places { pruneIfOrphaned(place, excludingStops: doomed) }
        }
    }

    // MARK: - Stops

    @discardableResult
    public func addStop(_ spot: Spot, to trip: TripRecord, day: Int, session: LightWindowKind? = nil, at index: Int? = nil) -> StopRecord {
        perform(.addStop) {
            touch(trip)
            let place = upsertPlace(for: spot)
            return insertStop(place: place, in: trip, day: day, session: session ?? spot.defaultSession, index: index)
        }
    }

    public func removeStop(_ stop: StopRecord) {
        guard let trip = stop.trip else { return }
        perform(.removeStop) {
            touch(trip)
            let day = stop.dayIndex
            let place = stop.place
            let id = stop.id
            context.delete(stop)
            renumber(trip.orderedStops(onDay: day).filter { $0.id != id })
            trip.updatedAt = .now
            if let place { pruneIfOrphaned(place, excludingStops: [id]) }
        }
    }

    /// Moves a stop within its day or to another day. `index` nil appends. Renumbers both days.
    public func moveStop(_ stop: StopRecord, toDay day: Int, index: Int?) {
        guard let trip = stop.trip else { return }
        perform(.moveStop) {
            touch(trip)
            let target = clampDay(day, in: trip)
            let sourceDay = stop.dayIndex
            let remainingSource = trip.orderedStops(onDay: sourceDay).filter { $0.id != stop.id }
            stop.dayIndex = target
            var targetList = sourceDay == target ? remainingSource : trip.orderedStops(onDay: target).filter { $0.id != stop.id }
            targetList.insert(stop, at: clampIndex(index, count: targetList.count))
            if sourceDay != target { renumber(remainingSource) }
            renumber(targetList)
            trip.updatedAt = .now
        }
    }

    /// Applies an ordering to one day (used to accept an ordering suggestion). Stops not named keep their relative order after the named ones.
    public func reorder(day: Int, in trip: TripRecord, to ids: [UUID]) {
        perform(.reorderStops) {
            touch(trip)
            let current = trip.orderedStops(onDay: day)
            let byID = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var seen = Set<UUID>()
            var ordered: [StopRecord] = []
            for id in ids {
                if let stop = byID[id], seen.insert(id).inserted { ordered.append(stop) }
            }
            ordered += current.filter { !seen.contains($0.id) }
            renumber(ordered)
            trip.updatedAt = .now
        }
    }

    public func setSession(_ stop: StopRecord, to session: LightWindowKind) {
        guard stop.session != session else { return }
        editStop(stop, .setSession) { $0.session = session }
    }

    public func setNote(_ stop: StopRecord, to note: String) {
        guard stop.note != note else { return }
        editStop(stop, .setNote) { $0.note = note }
    }

    public func setBuffer(_ stop: StopRecord, minutes: Int) {
        let minutes = max(0, minutes)
        guard stop.setUpBufferMinutes != minutes else { return }
        editStop(stop, .setBuffer) { $0.setUpBufferMinutes = minutes }
    }

    private func editStop(_ stop: StopRecord, _ action: StoreAction, _ edit: (StopRecord) -> Void) {
        guard let trip = stop.trip else { return }
        perform(action) {
            touch(trip)
            edit(stop)
            trip.updatedAt = .now
        }
    }

    // MARK: - Spots

    /// Saved curated and Apple Maps spots plus every user spot, one list, most recently changed first.
    public func savedPlaces() -> [PlaceRecord] {
        let all = (try? context.fetch(FetchDescriptor<PlaceRecord>())) ?? []
        return all.filter { $0.isSaved || $0.origin == .user }
            .sorted { ($0.updatedAt, $0.id.uuidString) > ($1.updatedAt, $1.id.uuidString) }
    }

    public func isSaved(spotID: String) -> Bool {
        guard let place = findPlace(spotID: spotID, curated: CuratedSpots.spot(id: spotID) != nil) else { return false }
        return place.isSaved || place.origin == .user
    }

    public func setSaved(_ spot: Spot, _ saved: Bool) {
        let existing = findPlace(for: spot)
        if saved, existing?.isSaved == true { return }
        if !saved, existing == nil || existing?.isSaved == false { return }
        perform(.setSaved) {
            if saved {
                let place = upsertPlace(for: spot)
                place.isSaved = true
                place.updatedAt = .now
            } else if let place = existing {
                touch(place)
                place.isSaved = false
                place.updatedAt = .now
                pruneIfOrphaned(place, excludingStops: [])
            }
        }
    }

    @discardableResult
    public func createUserSpot(name: String, locality: String = "", coordinate: Coordinate, timeZoneIdentifier: String,
                               category: SpotCategory = .landscape, bestLight: [BestLight] = [],
                               notes: String = "", walkInMinutes: Int? = nil) -> PlaceRecord {
        perform(.createUserSpot) {
            let place = PlaceRecord()
            context.insert(place)
            touchNew(place: place.id)
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
            return place
        }
    }

    /// Edits a place. Only the arguments you pass change; pass `.some(nil)` for `walkInMinutes` to clear it (unknown).
    public func updatePlace(_ place: PlaceRecord, name: String? = nil, locality: String? = nil, coordinate: Coordinate? = nil,
                            timeZoneIdentifier: String? = nil, category: SpotCategory? = nil, bestLight: [BestLight]? = nil,
                            blurb: String? = nil, notes: String? = nil, walkInMinutes: Int?? = nil) {
        perform(.updatePlace) {
            touch(place)
            if let name { place.name = name }
            if let locality { place.locality = locality }
            if let coordinate { place.coordinate = coordinate }
            if let timeZoneIdentifier { place.timeZoneIdentifier = timeZoneIdentifier }
            if let category { place.category = category }
            if let bestLight { place.bestLight = bestLight }
            if let blurb { place.blurb = blurb }
            if let notes { place.notes = notes }
            if let walkInMinutes { place.walkInMinutes = walkInMinutes }
            place.updatedAt = .now
        }
    }

    /// Deletes a place and every stop that used it; undo brings all of it back.
    public func deletePlace(_ place: PlaceRecord) {
        perform(.deletePlace) {
            touch(place)
            for stop in place.stops ?? [] {
                if let trip = stop.trip {
                    touch(trip)
                    trip.updatedAt = .now
                }
                context.delete(stop)
            }
            context.delete(place)
        }
    }

    // MARK: - Documents

    public func document(for trip: TripRecord, exportedAt: Date = .now) -> TripDocument {
        TripDocument(trip: trip.plan, exportedAt: exportedAt)
    }

    /// Creates a new trip (new IDs) from a document; importing the same document twice gives two trips.
    @discardableResult
    public func importTrip(_ document: TripDocument) -> TripRecord {
        perform(.importTrip) {
            let plan = document.trip
            let trip = makeTrip(name: plan.name, startDay: plan.startDay, dayCount: plan.dayCount)
            trip.notes = plan.notes
            for stop in plan.stops {
                let place = upsertPlace(for: stop.spot)
                let record = insertStop(place: place, in: trip, day: stop.dayIndex, session: stop.session, index: nil)
                record.setUpBufferMinutes = stop.setUpBufferMinutes
                record.note = stop.note
            }
            return trip
        }
    }

    // MARK: - Debug

    /// Deletes everything. Not undoable; clears the undo stack.
    public func resetAllData() {
        undoManager?.removeAllActions(withTarget: self)
        for trip in (try? context.fetch(FetchDescriptor<TripRecord>())) ?? [] { context.delete(trip) }
        for place in (try? context.fetch(FetchDescriptor<PlaceRecord>())) ?? [] { context.delete(place) }
        save()
        revision += 1
    }

    /// A ready-made trip for demos and screenshots (the first template). Not undoable.
    @discardableResult
    public func seedSampleTrip(startDay: LocalDay) -> TripRecord {
        let template = TripTemplates.all[0]
        return perform(.createTripFromTemplate, undoable: false) {
            makeTrip(from: template, startDay: startDay, name: template.defaultName)
        }
    }

    // MARK: - Transaction and undo

    @discardableResult
    private func perform<T>(_ action: StoreAction, undoable: Bool = true, _ body: () -> T) -> T {
        precondition(pending == nil, "IterStore mutations do not nest")
        pending = StoreState()
        let result = body()
        let before = pending ?? StoreState()
        pending = nil
        save()
        revision += 1
        if undoable, undoManager != nil {
            var after = StoreState(tripIDs: before.tripIDs, placeIDs: before.placeIDs)
            for id in before.tripIDs { if let trip = trip(id: id) { after.trips[id] = TripSnapshot(trip) } }
            for id in before.placeIDs { if let place = place(id: id) { after.places[id] = PlaceSnapshot(place) } }
            register(StoreChange(before: before, after: after), action)
        }
        return result
    }

    private func touch(_ trip: TripRecord) {
        guard pending?.tripIDs.insert(trip.id).inserted == true else { return }
        pending?.trips[trip.id] = TripSnapshot(trip)
    }

    private func touch(_ place: PlaceRecord) {
        guard pending?.placeIDs.insert(place.id).inserted == true else { return }
        pending?.places[place.id] = PlaceSnapshot(place)
    }

    private func touchNew(trip id: UUID) { pending?.tripIDs.insert(id) }
    private func touchNew(place id: UUID) { pending?.placeIDs.insert(id) }

    private func register(_ change: StoreChange, _ action: StoreAction) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { store in
            store.restore(change.before)
            store.save()
            store.revision += 1
            store.register(change.reversed, action)
        }
        undoManager.setActionName(actionName(action))
    }

    /// Makes the records in `state` exactly as snapshotted: recreates, updates or deletes them.
    private func restore(_ state: StoreState) {
        for id in state.placeIDs {
            guard let snapshot = state.places[id] else { continue }
            let record = place(id: id) ?? {
                let new = PlaceRecord(id: id)
                context.insert(new)
                return new
            }()
            snapshot.write(to: record)
        }
        for id in state.tripIDs {
            guard let snapshot = state.trips[id] else {
                if let trip = trip(id: id) { context.delete(trip) }
                continue
            }
            let trip = trip(id: id) ?? {
                let new = TripRecord(id: id)
                context.insert(new)
                return new
            }()
            snapshot.write(to: trip)
            var existing = Dictionary((trip.stops ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for stopSnapshot in snapshot.stops {
                let record = existing.removeValue(forKey: stopSnapshot.id) ?? {
                    let new = StopRecord(id: stopSnapshot.id)
                    context.insert(new)
                    return new
                }()
                stopSnapshot.write(to: record)
                record.trip = trip
                record.place = stopSnapshot.placeID.flatMap { place(id: $0) }
            }
            for leftover in existing.values { context.delete(leftover) }
        }
        for id in state.placeIDs where state.places[id] == nil {
            if let place = place(id: id) { context.delete(place) }
        }
    }

    private func save() {
        do {
            try context.save()
            lastSaveError = nil
        } catch {
            lastSaveError = error
            log.error("save failed: \(String(describing: error))")
        }
    }

    // MARK: - Helpers (call only inside `perform`)

    private func makeTrip(name: String, startDay: LocalDay, dayCount: Int) -> TripRecord {
        let trip = TripRecord()
        context.insert(trip)
        touchNew(trip: trip.id)
        trip.name = name
        trip.startDay = startDay
        trip.dayCount = max(1, dayCount)
        return trip
    }

    private func makeTrip(from template: TripTemplate, startDay: LocalDay, name: String) -> TripRecord {
        let trip = makeTrip(name: name, startDay: startDay, dayCount: template.dayCount)
        for entry in template.stops {
            guard let spot = CuratedSpots.spot(id: entry.spotID) else { continue }
            let place = upsertPlace(for: spot)
            insertStop(place: place, in: trip, day: entry.dayIndex, session: entry.session, index: nil)
        }
        return trip
    }

    @discardableResult
    private func insertStop(place: PlaceRecord, in trip: TripRecord, day: Int, session: LightWindowKind, index: Int?) -> StopRecord {
        let stop = StopRecord()
        context.insert(stop)
        stop.trip = trip
        stop.place = place
        stop.dayIndex = clampDay(day, in: trip)
        stop.session = session
        var list = trip.orderedStops(onDay: stop.dayIndex).filter { $0.id != stop.id }
        list.insert(stop, at: clampIndex(index, count: list.count))
        renumber(list)
        trip.updatedAt = .now
        return stop
    }

    private func renumber(_ stops: [StopRecord]) {
        for (i, stop) in stops.enumerated() where stop.sortOrder != Double(i) { stop.sortOrder = Double(i) }
    }

    private func clampDay(_ day: Int, in trip: TripRecord) -> Int { min(max(0, day), max(0, trip.dayCount - 1)) }
    private func clampIndex(_ index: Int?, count: Int) -> Int { min(max(0, index ?? count), count) }

    /// Deletes a place nothing refers to: not saved, not a user spot, no stops other than those being deleted.
    private func pruneIfOrphaned(_ place: PlaceRecord, excludingStops excluded: Set<UUID>) {
        guard !place.isSaved, place.origin != .user else { return }
        guard (place.stops ?? []).allSatisfy({ excluded.contains($0.id) }) else { return }
        touch(place)
        context.delete(place)
    }

    private func findPlace(for spot: Spot) -> PlaceRecord? {
        findPlace(spotID: spot.id, curated: spot.origin == .curated)
    }

    private func findPlace(spotID: String, curated: Bool) -> PlaceRecord? {
        if curated {
            var descriptor = FetchDescriptor<PlaceRecord>(predicate: #Predicate { $0.curatedID == spotID })
            descriptor.fetchLimit = 1
            return try? context.fetch(descriptor).first
        }
        if let uuid = UUID(uuidString: spotID), let found = place(id: uuid) { return found }
        var descriptor = FetchDescriptor<PlaceRecord>(predicate: #Predicate { $0.externalID == spotID })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Finds the record for a spot or creates it. Curated records are keyed by slug; others by UUID, then MapKit identifier.
    private func upsertPlace(for spot: Spot) -> PlaceRecord {
        if let existing = findPlace(for: spot) {
            touch(existing)
            if spot.origin == .curated { existing.apply(spot) }
            return existing
        }
        let uuid = UUID(uuidString: spot.id)
        let place = PlaceRecord(id: spot.origin == .curated ? UUID() : (uuid ?? UUID()))
        context.insert(place)
        touchNew(place: place.id)
        place.apply(spot)
        if spot.origin == .curated {
            place.curatedID = spot.id
        } else if uuid == nil {
            place.externalID = spot.id
        }
        place.isSaved = spot.origin == .user
        return place
    }
}
