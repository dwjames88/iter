import Foundation
import IterModel
import IterStore

// Every edit goes through `LibraryStore.trips` (one named undo group each) and then rebuilds the model's values at once.
// An edit to a stop or trip that no longer exists is a silent no-op, as in the repository.

extension BuildModel {
    // MARK: Plumbing

    private func record() -> TripRecord? { library.trips.trip(id: tripID) }

    private func stopRecord(_ id: UUID) -> StopRecord? { record()?.orderedStops.first { $0.id == id } }

    private func edited() {
        recompute()
        armObservation()
    }

    /// The edit on a stop, if it exists.
    private func editStop(_ id: UUID, _ body: (TripRepository, StopRecord) -> Void) {
        guard let stop = stopRecord(id) else { return }
        body(library.trips, stop)
        edited()
    }

    // MARK: Trip

    public func rename(_ name: String) {
        guard let record = record() else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        library.trips.rename(record, to: trimmed)
        edited()
    }

    public func setNotes(_ notes: String) {
        guard let record = record() else { return }
        library.trips.setNotes(record, to: notes)
        edited()
    }

    /// How many stops a new day count would move to the last day (the confirmation before `changeDates`).
    public func stopsAffected(byDayCount dayCount: Int) -> Int {
        guard let trip else { return 0 }
        return trip.stops.filter { $0.dayIndex > max(1, dayCount) - 1 }.count
    }

    /// Changes the dates. Stops beyond the new last day move to the last day, keeping their order. Returns how many moved.
    @discardableResult
    public func changeDates(startDay: LocalDay, dayCount: Int) -> Int {
        guard let record = record() else { return 0 }
        let moved = library.trips.setDates(record, startDay: startDay, dayCount: dayCount)
        requested = []
        edited()
        return moved
    }

    /// Pins or unpins the trip. Pinning builds its offline conditions pack; unpinning drops the pack state (the file is left).
    public func setPinned(_ pinned: Bool) {
        guard let record = record() else { return }
        library.trips.setPinned(record, pinned)
        if !pinned {
            packTask?.cancel()
            packTask = nil
            packDirty = false
            packSignatureBuilt = nil
        }
        edited()
        if isOpen { refreshPackIfNeeded(onOpen: false) }
    }

    /// Chooses when the drive into `day` happens: Morning, or Evening Before (after the previous stop's session).
    public func setTransferTiming(intoDay day: Int, to timing: TransferTiming) {
        guard let record = record() else { return }
        library.trips.setTransferTiming(record, intoDay: day, to: timing)
        edited()
    }

    /// Where day 1 starts (a place already in the library), or nil to clear it. The first stop's leave-by is worked from it.
    public func setStartPlace(_ placeID: UUID?) {
        guard let record = record() else { return }
        if let placeID, library.places.value(id: placeID) == nil { return }
        library.trips.setStartPlace(record, to: placeID)
        edited()
    }

    /// Places that can be the start: the trip's own lodging stops first, then its other stops, then saved places.
    public func startPlaceCandidates() -> [Place] {
        var seen = Set<UUID>()
        var out: [Place] = []
        let stops = trip.map { Self.ordered($0.stops) } ?? []
        for stop in stops.filter({ $0.kind == .lodging }) + stops.filter({ $0.kind != .lodging }) {
            if seen.insert(stop.place.id).inserted { out.append(stop.place) }
        }
        for place in library.places.savedValues() where seen.insert(place.id).inserted { out.append(place) }
        return out
    }

    // MARK: Stops

    /// Adds a stop for `place` to a day (appended unless `index` is given), with its best session unless one is given.
    /// Selects it. Returns its id.
    @discardableResult
    public func addStop(_ place: Place, day: Int, session: LightWindowKind? = nil, at index: Int? = nil) -> UUID? {
        guard let record = record() else { return nil }
        let stop = library.trips.addStop(place, to: record, day: day, session: session, at: index)
        let id = stop.id
        edited()
        selectStop(id)
        return id
    }

    /// Adds a lodging or waypoint (it has no light window): the stop is added, then given its kind (two undo steps).
    @discardableResult
    public func addStop(_ place: Place, day: Int, kind: StopKind, at index: Int? = nil) -> UUID? {
        guard let id = addStop(place, day: day, session: nil, at: index) else { return nil }
        if kind != .light { setKind(id, kind) }
        return id
    }

    public func removeStop(_ id: UUID) {
        guard let stop = stopRecord(id) else { return }
        if selectedStopID == id { selectedStopID = nil }
        library.trips.removeStop(stop)
        edited()
    }

    /// Drag and drop: moves a stop within its day or to another day, before the stop now at `index` (nil appends).
    public func moveStop(_ id: UUID, toDay day: Int, index: Int?) {
        editStop(id) { $0.moveStop($1, toDay: day, index: index) }
        if selectedStopID == id, let moved = trip?.stops.first(where: { $0.id == id }) { selectedDay = moved.dayIndex }
    }

    /// Puts one day's stops in the given order (stops not named follow in their current order).
    public func reorder(day: Int, to ids: [UUID]) {
        guard let record = record() else { return }
        library.trips.reorder(day: day, in: record, to: ids)
        edited()
    }

    public func setSession(_ id: UUID, to session: LightWindowKind) { editStop(id) { $0.setSession($1, to: session) } }
    public func setNote(_ id: UUID, to note: String) { editStop(id) { $0.setNote($1, to: note) } }
    /// The note about the drive into a stop. It stays with that stop when stops are reordered.
    public func setDriveNote(_ id: UUID, to note: String) { editStop(id) { $0.setDriveNote($1, to: note) } }
    public func setBuffer(_ id: UUID, minutes: Int) { editStop(id) { $0.setBuffer($1, minutes: minutes) } }
    /// How long you stay, in minutes. 0 means "until the window ends".
    public func setDwell(_ id: UUID, minutes: Int) { editStop(id) { $0.setDwell($1, minutes: minutes) } }
    public func setKind(_ id: UUID, _ kind: StopKind) { editStop(id) { $0.setKind($1, to: kind) } }
    /// A fixed arrival time for a stop not driven by light. nil clears it.
    public func setFixedArrival(_ id: UUID, to time: LocalTime?) { editStop(id) { $0.setFixedArrival($1, to: time) } }

    // MARK: Ordering suggestions

    /// Puts the day in the suggested light-first order (one undo step, "Reorder Stops").
    public func applySuggestion(day: Int) {
        guard let suggestion = suggestion(forDay: day), let record = record() else { return }
        library.trips.reorder(day: day, in: record, to: suggestion.order)
        edited()
    }

    /// Hides the suggestion for this order of the day for the rest of the session; a different order shows again.
    public func dismissSuggestion(day: Int) {
        guard let suggestion = suggestion(forDay: day) else { return }
        dismissed.insert(Dismissal(day: day, order: suggestion.order))
        recompute()
    }

    public func suggestion(forDay day: Int) -> BuildSuggestion? {
        for row in rows where row.day == day {
            if case .suggestion(let s) = row.kind { return s }
        }
        return nil
    }

    // MARK: Sharing

    /// The file name a shared trip is saved under ("Canyon Country.iter").
    public var suggestedFileName: String { ITERFileInfo.suggestedFileName(forTripNamed: trip?.name ?? "Trip") }

    /// The trip as an `.iter` document, built when asked (never from a view body). v2 keeps everything and merges by id on
    /// import; "for older Iter" is format 1, readable before the rebuild. Throws `BuildExportError.tripMissing` for a deleted trip.
    public func exportDocument(format: BuildExportFormat) throws -> Data {
        switch format {
        case .v2:
            guard let file = library.exportV2(tripID: tripID) else { throw BuildExportError.tripMissing }
            return try file.encoded()
        case .v1ForOlderIter:
            guard let file = library.exportV1(tripID: tripID) else { throw BuildExportError.tripMissing }
            return try file.encoded()
        }
    }
}

public enum BuildExportError: Error, Equatable, Sendable {
    case tripMissing
}
