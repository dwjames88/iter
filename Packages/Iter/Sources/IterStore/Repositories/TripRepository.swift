import Foundation
import IterModel
import SwiftData

/// Trips and their stops. Invalid requests are silent no-ops. Every mutation is one named undo group.
@MainActor
public struct TripRepository {
    unowned let store: LibraryStore

    // MARK: Fetching

    /// Every trip, most recently changed first.
    public func all() -> [TripRecord] {
        store.allTrips().sorted { ($0.updatedAt, $0.id.uuidString) > ($1.updatedAt, $1.id.uuidString) }
    }

    public func trip(id: UUID) -> TripRecord? { store.tripRecord(id: id) }

    /// The value form (stops in order, a stop with no place left out).
    public func value(id: UUID) -> Trip? { store.tripRecord(id: id)?.value() }

    public func values() -> [Trip] { all().map { $0.value() } }

    /// The trips directly in `folder` (nil = unfiled), pinned ones included, ordered (sort order, newest edit, id).
    public func trips(in folder: FolderRecord?) -> [TripRecord] { store.tripsSorted(in: folder) }

    /// Pinned trips in the order they were pinned.
    public func pinned() -> [TripRecord] {
        let pinned = (try? store.context.fetch(FetchDescriptor<TripRecord>(predicate: #Predicate { $0.isPinned }))) ?? []
        return pinned.sorted {
            ($0.pinnedAt ?? .distantFuture, $0.id.uuidString) < ($1.pinnedAt ?? .distantFuture, $1.id.uuidString)
        }
    }

    // MARK: Trips

    @discardableResult
    public func create(name: String, startDay: LocalDay, dayCount: Int) -> TripRecord {
        store.perform(.createTrip) { store.makeTrip(name: name, startDay: startDay, dayCount: dayCount) }
    }

    @discardableResult
    public func create(from template: TripTemplate, startDay: LocalDay) -> TripRecord {
        store.perform(.createTripFromTemplate) {
            store.makeTrip(from: template, startDay: startDay, name: template.defaultName)
        }
    }

    public func rename(_ trip: TripRecord, to name: String) {
        guard trip.name != name else { return }
        store.perform(.renameTrip) {
            store.touch(trip)
            trip.name = name
            trip.updatedAt = store.clock()
        }
    }

    public func setNotes(_ trip: TripRecord, to notes: String) {
        guard trip.notes != notes else { return }
        store.perform(.setTripNotes) {
            store.touch(trip)
            trip.notes = notes
            trip.updatedAt = store.clock()
        }
    }

    /// Changes the dates. Stops beyond the new last day move to the last day, keeping their order.
    /// Returns how many stops moved.
    @discardableResult
    public func setDates(_ trip: TripRecord, startDay: LocalDay, dayCount: Int) -> Int {
        store.perform(.setDates) {
            store.touch(trip)
            let count = max(1, dayCount)
            let last = count - 1
            let ordered = trip.orderedStops
            let displaced = ordered.filter { $0.dayIndex > last }
            trip.startDay = startDay
            trip.dayCount = count
            trip.transferTimings = trip.transferTimings.filter { $0.key < count }
            if !displaced.isEmpty {
                let kept = ordered.filter { $0.dayIndex == last }
                for stop in displaced { stop.dayIndex = last }
                store.renumber(kept + displaced)
            }
            trip.updatedAt = store.clock()
            return displaced.count
        }
    }

    /// A copy with new ids that shares the same places. `name` defaults to the original's.
    @discardableResult
    public func duplicate(_ trip: TripRecord, name: String? = nil) -> TripRecord {
        store.perform(.duplicateTrip) {
            let copy = store.makeTrip(name: name ?? trip.name, startDay: trip.startDay, dayCount: trip.dayCount)
            copy.notes = trip.notes
            copy.transferTimingsRaw = trip.transferTimingsRaw
            copy.startPlaceID = trip.startPlaceID
            copy.timeZonePolicyRaw = trip.timeZonePolicyRaw
            for stop in trip.orderedStops {
                let new = StopRecord()
                store.context.insert(new)
                new.trip = copy
                new.place = stop.place
                new.dayIndex = stop.dayIndex
                new.sortOrder = stop.sortOrder
                new.sessionRaw = stop.sessionRaw
                new.setUpBufferMinutes = stop.setUpBufferMinutes
                new.note = stop.note
                new.driveNote = stop.driveNote
                new.dwellMinutes = stop.dwellMinutes
                new.fixedArrivalISO = stop.fixedArrivalISO
                new.kindRaw = stop.kindRaw
            }
            // Filed with the original, right after it.
            copy.folder = trip.folder
            var siblings = store.tripsSorted(in: trip.folder).filter { $0.id != copy.id }
            let at = siblings.firstIndex { $0.id == trip.id }.map { $0 + 1 } ?? siblings.count
            siblings.insert(copy, at: at)
            store.renumber(siblings)
            return copy
        }
    }

    /// Deletes the trip and its stops, and writes a tombstone. Places nothing else uses (not saved, not yours) go too.
    public func delete(_ trip: TripRecord) {
        store.perform(.deleteTrip) {
            store.touch(trip)
            let doomed = Set((trip.stops ?? []).map(\.id))
            let places = (trip.stops ?? []).compactMap(\.place)
            store.writeTombstone(.trip, id: trip.id)
            store.context.delete(trip)
            for place in places { store.pruneIfOrphaned(place, excludingStops: doomed) }
        }
    }

    /// Pins or unpins a trip. A pinned trip keeps its folder. Not a content change: `updatedAt` stays.
    public func setPinned(_ trip: TripRecord, _ pinned: Bool) {
        guard trip.isPinned != pinned else { return }
        store.perform(pinned ? .pinTrip : .unpinTrip) {
            store.touch(trip)
            trip.isPinned = pinned
            trip.pinnedAt = pinned ? store.clock() : nil
        }
    }

    /// Where day 1 starts, for the first stop's leave-by. nil clears it.
    public func setStartPlace(_ trip: TripRecord, to placeID: UUID?) {
        guard trip.startPlaceID != placeID else { return }
        store.perform(.setStartPlace) {
            store.touch(trip)
            trip.startPlaceID = placeID
            trip.updatedAt = store.clock()
        }
    }

    /// Chooses when the transfer into `day` (a day after the first) happens. Morning is the default.
    public func setTransferTiming(_ trip: TripRecord, intoDay day: Int, to timing: TransferTiming) {
        guard day > 0, day < trip.dayCount, trip.transferTiming(intoDay: day) != timing else { return }
        store.perform(.setTransferTiming) {
            store.touch(trip)
            var timings = trip.transferTimings
            timings[day] = timing == .morning ? nil : timing
            trip.transferTimings = timings
            trip.updatedAt = store.clock()
        }
    }

    // MARK: Stops

    @discardableResult
    public func addStop(_ place: Place, to trip: TripRecord, day: Int, session: LightWindowKind? = nil,
                        at index: Int? = nil) -> StopRecord {
        store.perform(.addStop) {
            store.touch(trip)
            let record = store.upsertPlace(for: place)
            return store.insertStop(place: record, in: trip, day: day, session: session ?? place.defaultSession, index: index)
        }
    }

    public func removeStop(_ stop: StopRecord) {
        guard let trip = stop.trip else { return }
        store.perform(.removeStop) {
            store.touch(trip)
            let day = stop.dayIndex
            let place = stop.place
            let id = stop.id
            store.deleteStop(stop)
            store.renumber(trip.orderedStops(onDay: day).filter { $0.id != id })
            trip.updatedAt = store.clock()
            if let place { store.pruneIfOrphaned(place, excludingStops: [id]) }
        }
    }

    /// Moves a stop within its day or to another day. `index` nil appends. Renumbers both days.
    public func moveStop(_ stop: StopRecord, toDay day: Int, index: Int?) {
        guard let trip = stop.trip else { return }
        store.perform(.moveStop) {
            store.touch(trip)
            let target = store.clampDay(day, in: trip)
            let sourceDay = stop.dayIndex
            let remainingSource = trip.orderedStops(onDay: sourceDay).filter { $0.id != stop.id }
            stop.dayIndex = target
            var targetList = sourceDay == target ? remainingSource : trip.orderedStops(onDay: target).filter { $0.id != stop.id }
            targetList.insert(stop, at: store.clampIndex(index, count: targetList.count))
            if sourceDay != target { store.renumber(remainingSource) }
            store.renumber(targetList)
            trip.updatedAt = store.clock()
        }
    }

    /// Applies an ordering to one day (used to accept an ordering suggestion). Stops not named keep their relative
    /// order after the named ones.
    public func reorder(day: Int, in trip: TripRecord, to ids: [UUID]) {
        store.perform(.reorderStops) {
            store.touch(trip)
            let current = trip.orderedStops(onDay: day)
            let byID = Dictionary(current.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var seen = Set<UUID>()
            var ordered: [StopRecord] = []
            for id in ids {
                if let stop = byID[id], seen.insert(id).inserted { ordered.append(stop) }
            }
            ordered += current.filter { !seen.contains($0.id) }
            store.renumber(ordered)
            trip.updatedAt = store.clock()
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

    /// Sets the note about the drive into `stop`. It stays with that stop when stops are reordered.
    public func setDriveNote(_ stop: StopRecord, to note: String) {
        guard stop.driveNote != note else { return }
        editStop(stop, .setDriveNote) { $0.driveNote = note }
    }

    public func setBuffer(_ stop: StopRecord, minutes: Int) {
        let minutes = max(0, minutes)
        guard stop.setUpBufferMinutes != minutes else { return }
        editStop(stop, .setBuffer) { $0.setUpBufferMinutes = minutes }
    }

    /// How long you stay, in minutes. 0 means "until the window ends".
    public func setDwell(_ stop: StopRecord, minutes: Int) {
        let minutes = max(0, minutes)
        guard stop.dwellMinutes != minutes else { return }
        editStop(stop, .setDwell) { $0.dwellMinutes = minutes }
    }

    public func setKind(_ stop: StopRecord, to kind: StopKind) {
        guard stop.kind != kind else { return }
        editStop(stop, .setStopKind) { $0.kind = kind }
    }

    /// A user-fixed arrival time for a stop not driven by light. nil clears it.
    public func setFixedArrival(_ stop: StopRecord, to time: LocalTime?) {
        guard stop.fixedArrival != time else { return }
        editStop(stop, .setFixedArrival) { $0.fixedArrival = time }
    }

    private func editStop(_ stop: StopRecord, _ action: StoreAction, _ edit: (StopRecord) -> Void) {
        guard let trip = stop.trip else { return }
        store.perform(action) {
            store.touch(trip)
            edit(stop)
            trip.updatedAt = store.clock()
        }
    }
}
