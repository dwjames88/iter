import Foundation
import Observation
import IterModel
import IterStore

/// Everything the sidebar, All Trips and Saved Places read, and every library action. `@MainActor @Observable`; rows are
/// `Equatable` values rebuilt from the repositories whenever `LibraryStore.revision` moves (an observation hop, no polling
/// loop), and each property is assigned only when it changed, so a view that reads `pinnedTrips` is not invalidated by an
/// edit to a place.
///
/// Actions go through the repositories, which register one named undo step each on `LibraryStore.undoManager` (the shell
/// attaches its window's manager). Nothing here touches a `ModelContext`.
@MainActor @Observable
public final class LibraryModel {
    // MARK: Rows

    /// Every trip: upcoming and in-progress first (soonest first), then past ones (most recent first).
    public private(set) var trips: [TripRow] = []
    /// Pinned trips, in the order they were pinned.
    public private(set) var pinnedTrips: [TripRow] = []
    public private(set) var tripFolders: [FolderRow] = []
    /// Pinned trip folders.
    public private(set) var pinnedTripFolders: [FolderRow] = []
    /// The trip to feature: the soonest one that has not finished.
    public private(set) var nextTrip: TripRow?
    /// Saved and own places, most recently changed first.
    public private(set) var savedPlaces: [PlaceRow] = []
    public private(set) var pinnedPlaces: [PlaceRow] = []
    public private(set) var placeFolders: [FolderRow] = []
    public private(set) var pinnedPlaceFolders: [FolderRow] = []

    // MARK: Plumbing

    @ObservationIgnored private let store: LibraryStore
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private let timeZone: TimeZone
    @ObservationIgnored private var observed = -1

    /// - Parameters:
    ///   - now: the clock ("next trip" and "past" are decided against it).
    ///   - timeZone: the zone "today" is read in (the device's by default).
    public init(library: LibraryStore, now: @escaping @Sendable () -> Date = { Date() }, timeZone: TimeZone = .current) {
        store = library
        self.now = now
        self.timeZone = timeZone
        refresh()
        watch()
    }

    /// The store's window undo manager (set by the shell).
    public var undoManager: UndoManager? {
        get { store.undoManager }
        set { store.undoManager = newValue }
    }

    /// Re-reads the rows if the store changed. Called by the observation hop and after every action; safe to call anytime.
    public func refresh() {
        guard observed != store.revision || observed < 0 else { return }
        observed = store.revision
        rebuild()
    }

    private func watch() {
        withObservationTracking {
            _ = store.revision
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.refresh()
                self?.watch()
            }
        }
    }

    private func rebuild() {
        let today = LocalDay(now(), in: timeZone)
        let tripRepo = store.trips, placeRepo = store.places, folderRepo = store.folders

        func row(_ t: TripRecord) -> TripRow {
            let ordered = t.orderedStops
            return TripRow(id: t.id, name: t.name, startDay: t.startDay, dayCount: t.dayCount, stopCount: ordered.count,
                           placeNames: ordered.prefix(3).compactMap { $0.place?.name }, folderID: t.folder?.id,
                           isPinned: t.isPinned, updatedAt: t.updatedAt)
        }
        func row(_ p: PlaceRecord) -> PlaceRow {
            PlaceRow(id: p.id, name: p.name, locality: p.locality, category: p.category, coordinate: p.coordinate, origin: p.origin,
                     curatedID: p.curatedID, folderID: p.folder?.id, isPinned: p.isPinned, updatedAt: p.updatedAt)
        }

        let all = tripRepo.all().map(row)
        let upcoming = all.filter { $0.endDay >= today }.sorted { ($0.startDay, $0.name, $0.id.uuidString) < ($1.startDay, $1.name, $1.id.uuidString) }
        let past = all.filter { $0.endDay < today }.sorted { ($0.startDay, $0.name, $0.id.uuidString) > ($1.startDay, $1.name, $1.id.uuidString) }
        set(\.trips, upcoming + past)
        set(\.nextTrip, upcoming.first)
        set(\.pinnedTrips, tripRepo.pinned().map(row))

        let tripFolderRows = folderRepo.list(kind: .trips).map {
            FolderRow(id: $0.id, name: $0.name, kind: .trips, count: ($0.trips ?? []).count, isPinned: $0.isPinned)
        }
        set(\.tripFolders, tripFolderRows)
        set(\.pinnedTripFolders, folderRepo.pinned(kind: .trips).compactMap { p in tripFolderRows.first { $0.id == p.id } })

        set(\.savedPlaces, placeRepo.savedPlaces().map(row))
        set(\.pinnedPlaces, placeRepo.pinned().map(row))
        let placeFolderRows = folderRepo.list(kind: .locations).map {
            FolderRow(id: $0.id, name: $0.name, kind: .locations, count: placeRepo.savedPlaces(in: $0).count, isPinned: $0.isPinned)
        }
        set(\.placeFolders, placeFolderRows)
        set(\.pinnedPlaceFolders, folderRepo.pinned(kind: .locations).compactMap { p in placeFolderRows.first { $0.id == p.id } })
    }

    /// Assigns only a changed value, so the observation registrar does not fire for an identical rebuild.
    private func set<V: Equatable>(_ keyPath: ReferenceWritableKeyPath<LibraryModel, V>, _ value: V) {
        if self[keyPath: keyPath] != value { self[keyPath: keyPath] = value }
    }

    /// Runs one action as one undo group when the manager does not group by run-loop event itself (a manager with
    /// `groupsByEvent` true already makes each user event one step; this changes nothing for it).
    private func act<T>(_ body: () -> T) -> T {
        guard let manager = store.undoManager, !manager.groupsByEvent else { return body() }
        manager.beginUndoGrouping()
        defer { manager.endUndoGrouping() }
        return body()
    }

    // MARK: Lookups

    public func trips(in folderID: UUID?) -> [TripRow] { trips.filter { $0.folderID == folderID } }
    public func places(in folderID: UUID?) -> [PlaceRow] { savedPlaces.filter { $0.folderID == folderID } }
    public func tripRow(id: UUID) -> TripRow? { trips.first { $0.id == id } }
    public func placeRow(id: UUID) -> PlaceRow? { savedPlaces.first { $0.id == id } }
    /// The place as a value (for opening its page or Conditions).
    public func place(id: UUID) -> Place? { store.places.value(id: id) }
    public func trip(id: UUID) -> Trip? { store.trips.value(id: id) }

    // MARK: Trips

    /// A new empty trip.
    @discardableResult
    public func createTrip(name: String, startDay: LocalDay, dayCount: Int) -> UUID {
        defer { refresh() }
        return act { store.trips.create(name: name, startDay: startDay, dayCount: dayCount) }.id
    }

    /// A new trip from a template ("canyon-country"). nil for an unknown template.
    @discardableResult
    public func createTrip(templateID: String, startDay: LocalDay) -> UUID? {
        guard let template = TripTemplates.template(id: templateID) else { return nil }
        defer { refresh() }
        return act { store.trips.create(from: template, startDay: startDay) }.id
    }

    /// Adds a place (already in the library) as a stop on `day` of a trip: what New Trip does with a first place. One undo step.
    /// Returns the stop's id; nil when the trip or place is unknown.
    @discardableResult
    public func addStop(placeID: UUID, toTrip tripID: UUID, day: Int = 0) -> UUID? {
        guard let record = store.trips.trip(id: tripID), let place = store.places.value(id: placeID) else { return nil }
        defer { refresh() }
        return act { store.trips.addStop(place, to: record, day: day, session: nil, at: nil) }.id
    }

    public func renameTrip(_ id: UUID, to name: String) {
        guard let record = store.trips.trip(id: id) else { return }
        act { store.trips.rename(record, to: name) }
        refresh()
    }

    @discardableResult
    public func duplicateTrip(_ id: UUID) -> UUID? {
        guard let record = store.trips.trip(id: id) else { return nil }
        defer { refresh() }
        return act { store.trips.duplicate(record) }.id
    }

    public func deleteTrip(_ id: UUID) {
        guard let record = store.trips.trip(id: id) else { return }
        act { store.trips.delete(record) }
        refresh()
    }

    public func setTripPinned(_ id: UUID, _ pinned: Bool) {
        guard let record = store.trips.trip(id: id) else { return }
        act { store.trips.setPinned(record, pinned) }
        refresh()
    }

    /// Files trips in a folder (nil = unfiled) at `index` (a position in the destination as it is now; nil = end). This is
    /// what a drop on a folder or between rows calls.
    public func moveTrips(_ ids: [UUID], to folderID: UUID?, index: Int? = nil) {
        let records = ids.compactMap { store.trips.trip(id: $0) }
        let folder = folderID.flatMap { store.folders.folder(id: $0) }
        if folderID != nil, folder == nil { return }
        act { store.folders.moveTrips(records, to: folder, index: index) }
        refresh()
    }

    // MARK: Places

    /// Saves a place (a discovered or catalogue one) to Saved Places.
    public func savePlace(_ place: Place) {
        act { store.places.setSaved(place, true) }
        refresh()
    }

    public func unsavePlace(_ place: Place) {
        act { store.places.setSaved(place, false) }
        refresh()
    }

    public func isSaved(_ place: Place) -> Bool { store.places.isSaved(place) }

    /// Adds a place of your own (a pin you placed).
    @discardableResult
    public func createPlace(name: String, locality: String = "", coordinate: Coordinate, timeZoneIdentifier: String,
                            category: PlaceCategory = .landscape, notes: String = "") -> UUID {
        defer { refresh() }
        return act {
            store.places.createUserSpot(name: name, locality: locality, coordinate: coordinate,
                                        timeZoneIdentifier: timeZoneIdentifier, category: category, notes: notes)
        }.id
    }

    public func deletePlace(_ id: UUID) {
        guard let record = store.places.place(id: id) else { return }
        act { store.places.deletePlace(record) }
        refresh()
    }

    public func setPlacePinned(_ id: UUID, _ pinned: Bool) {
        guard let record = store.places.place(id: id) else { return }
        act { store.places.setPinned(record, pinned) }
        refresh()
    }

    /// What the place editor (⌘E) starts from. nil when there is no such saved or own place.
    public func placeEdit(id: UUID) -> PlaceEdit? { store.places.place(id: id).map(PlaceEdit.init) }

    /// Whether the place's own facts (coordinate, category, light, walk-in, tags) are the user's to edit; false for a
    /// catalogue place, whose editor shows them read-only.
    public func editsFacts(id: UUID) -> Bool { store.places.place(id: id).map { PlaceEdit.editsFacts(of: $0.origin) } ?? false }

    /// Applies the editor's value as one undo step. False when nothing changed.
    @discardableResult
    public func editPlace(id: UUID, _ edit: PlaceEdit) -> Bool {
        guard let record = store.places.place(id: id) else { return false }
        defer { refresh() }
        return act { store.places.editPlace(record, edit) }
    }

    /// Files places in a location folder (nil = unfiled) at `index`.
    public func movePlaces(_ ids: [UUID], to folderID: UUID?, index: Int? = nil) {
        let records = ids.compactMap { store.places.place(id: $0) }
        let folder = folderID.flatMap { store.folders.folder(id: $0) }
        if folderID != nil, folder == nil { return }
        act { store.folders.movePlaces(records, to: folder, index: index) }
        refresh()
    }

    // MARK: Folders

    /// A new folder, optionally holding the given trips (a trips folder) or places (a locations folder).
    @discardableResult
    public func createFolder(name: String, kind: FolderKind, containing ids: [UUID] = []) -> UUID {
        defer { refresh() }
        switch kind {
        case .trips: return act { store.folders.create(name: name, kind: kind, trips: ids.compactMap { store.trips.trip(id: $0) }) }.id
        case .locations: return act { store.folders.create(name: name, kind: kind, places: ids.compactMap { store.places.place(id: $0) }) }.id
        }
    }

    public func renameFolder(_ id: UUID, to name: String) {
        guard let folder = store.folders.folder(id: id) else { return }
        act { store.folders.rename(folder, to: name) }
        refresh()
    }

    /// Deletes a folder; its contents move out to the top level, they are not deleted.
    public func deleteFolder(_ id: UUID) {
        guard let folder = store.folders.folder(id: id) else { return }
        act { store.folders.delete(folder) }
        refresh()
    }

    public func setFolderPinned(_ id: UUID, _ pinned: Bool) {
        guard let folder = store.folders.folder(id: id) else { return }
        act { store.folders.setPinned(folder, pinned) }
        refresh()
    }

    // MARK: Import and export

    /// Imports `.iter` bytes. A v2 file merges by id (the newer edit wins; deletions carry over) unless `asCopy`; a v1 file
    /// has no ids to merge by and is always added as a new trip. One undo step.
    /// - Throws: `ITERFileError` when the bytes are not a readable `.iter` file.
    @discardableResult
    public func importLibrary(_ data: Data, asCopy: Bool = false) throws -> ImportSummary {
        let file = try ITERFile.read(data)
        defer { refresh() }
        switch file {
        case .v1:
            let added = act { store.importAsCopy(file) }
            return ImportSummary(formatVersion: 1, asCopy: true, tripsAdded: added.count, tripsUpdated: 0, tripsRemoved: 0,
                                 placesAdded: 0, foldersAdded: 0)
        case .v2(let v2):
            if asCopy {
                let before = Set(store.trips.all().map(\.id))
                let added = act { store.importAsCopy(file) }
                return ImportSummary(formatVersion: 2, asCopy: true, tripsAdded: added.filter { !before.contains($0.id) }.count,
                                     tripsUpdated: 0, tripsRemoved: 0, placesAdded: 0, foldersAdded: 0)
            }
            let plan = act { store.importMerging(v2) }
            return ImportSummary(formatVersion: 2, asCopy: false, tripsAdded: plan.trips.inserts.count, tripsUpdated: plan.trips.updates.count,
                                 tripsRemoved: plan.trips.deletes.count, placesAdded: plan.places.inserts.count, foldersAdded: plan.folders.inserts.count)
        }
    }

    /// The whole library as a v2 `.iter` file.
    public func exportLibrary() throws -> ExportedLibrary {
        ExportedLibrary(data: try store.exportLibrary().encoded(), suggestedFileName: "Iter Library.iter")
    }

    /// One trip as a v2 `.iter` file named after the trip.
    public func exportTrip(_ id: UUID) throws -> ExportedLibrary? {
        guard let file = store.exportV2(tripID: id), let trip = store.trips.value(id: id) else { return nil }
        return ExportedLibrary(data: try file.encoded(), suggestedFileName: ITERFileInfo.suggestedFileName(forTripNamed: trip.name))
    }
}
