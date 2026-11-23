import Foundation
import IterModel
import SwiftData

/// Folders and filing. Trips and locations never share a folder; folders are one level deep (no subfolders).
/// Invalid requests are silent no-ops. Every move, reorder and pin stamps `updatedAt` (from the store clock) on each record whose stored fields changed, and only those,
/// so a `.iter` v2 merge import, which keeps the newer `updatedAt` per record, carries the change.
@MainActor
public struct FolderRepository {
    unowned let store: LibraryStore

    // MARK: Fetching

    public func folder(id: UUID) -> FolderRecord? { store.folderRecord(id: id) }

    public func value(id: UUID) -> Folder? { store.folderRecord(id: id)?.value() }

    /// Folders of a kind, ordered (sort order, name, id).
    public func list(kind: FolderKind) -> [FolderRecord] {
        store.allFolders().filter { $0.kind == kind }.sorted(by: FolderFlatten.folderOrder)
    }

    public func values(kind: FolderKind) -> [Folder] { list(kind: kind).map { $0.value() } }

    /// Pinned folders of a kind in the order they were pinned.
    public func pinned(kind: FolderKind) -> [FolderRecord] {
        store.allFolders().filter { $0.kind == kind && $0.isPinned }.sorted {
            ($0.pinnedAt ?? .distantFuture, $0.id.uuidString) < ($1.pinnedAt ?? .distantFuture, $1.id.uuidString)
        }
    }

    // MARK: Folders

    /// A new, empty folder at the end of the top-level list.
    @discardableResult
    public func create(name: String, kind: FolderKind) -> FolderRecord {
        create(name: name, kind: kind, trips: [], places: [])
    }

    /// A new folder holding the given selection (trips only for `.trips` folders, places only for `.locations`).
    /// With an empty selection this is a plain create.
    @discardableResult
    public func create(name: String, kind: FolderKind, trips: [TripRecord] = [], places: [PlaceRecord] = []) -> FolderRecord {
        let trips = kind == .trips ? unique(trips) : []
        let places = kind == .locations ? unique(places) : []
        let action: StoreAction = trips.isEmpty && places.isEmpty ? .createFolder : .newFolderWithSelection
        return store.perform(action) {
            let folder = FolderRecord()
            store.context.insert(folder)
            store.touchNew(folder: folder.id)
            let now = store.clock()
            folder.name = name
            folder.kind = kind
            folder.createdAt = now
            folder.updatedAt = now
            folder.sortOrder = nextFolderSortOrder(kind: kind, excluding: folder.id)
            for (i, trip) in trips.enumerated() {
                store.touch(trip)
                trip.folder = folder
                trip.sortOrder = Double(i)
                trip.updatedAt = now
            }
            for (i, place) in places.enumerated() {
                store.touch(place)
                place.folder = folder
                place.sortOrder = Double(i)
                place.updatedAt = now
            }
            return folder
        }
    }

    public func rename(_ folder: FolderRecord, to name: String) {
        guard folder.name != name else { return }
        store.perform(.renameFolder) {
            store.touch(folder)
            folder.name = name
            folder.updatedAt = store.clock()
        }
    }

    /// Deletes the folder and writes a tombstone; its trips move to unfiled and its places to the top level (unfiled),
    /// after what is already there.
    public func delete(_ folder: FolderRecord) {
        store.perform(.deleteFolder) {
            store.touch(folder)
            if folder.kind == .trips {
                var order = store.nextTripSortOrder(in: nil)
                for trip in store.tripsSorted(in: folder) {
                    store.touch(trip)
                    trip.folder = nil
                    trip.updatedAt = store.clock()
                    trip.sortOrder = order
                    order += 1
                }
            } else {
                for place in (folder.places ?? []).sorted(by: LibraryStore.placeOrder) {
                    store.touch(place)
                    place.folder = nil
                    place.sortOrder = 0
                    place.updatedAt = store.clock()
                }
            }
            store.writeTombstone(.folder, id: folder.id)
            store.context.delete(folder)
        }
    }

    /// Reorders a folder among the folders of its kind. `index` is a position in that ordered list as it is now (before
    /// the move); nil = end.
    public func move(_ folder: FolderRecord, index: Int?) {
        let target = list(kind: folder.kind)
        let ordered = Self.inserting([folder], into: target, at: index) { $0.id }
        guard ordered.map(\.id) != target.map(\.id) else { return }
        store.perform(.moveFolder) {
            store.touch(folder)
            folder.updatedAt = store.clock()
            let now = store.clock()
            for (i, item) in ordered.enumerated() where item.sortOrder != Double(i) {
                store.touch(item)
                item.sortOrder = Double(i)
                item.updatedAt = now
            }
        }
    }

    /// Files trips in `folder` (nil = unfiled) at `index` and renumbers the target. `index` is a position in the
    /// target's ordered list as it is now (before the move, like `onMove`'s destination); nil = end. No-op for a
    /// location folder.
    public func moveTrips(_ trips: [TripRecord], to folder: FolderRecord?, index: Int?) {
        if let folder, folder.kind != .trips { return }
        let moving = unique(trips)
        guard !moving.isEmpty else { return }
        let target = store.tripsSorted(in: folder)
        let ordered = Self.inserting(moving, into: target, at: index) { $0.id }
        guard moving.contains(where: { $0.folder?.id != folder?.id }) || ordered.map(\.id) != target.map(\.id) else { return }
        store.perform(.moveTrips) {
            let now = store.clock()
            for (i, trip) in ordered.enumerated() where trip.folder?.id != folder?.id || trip.sortOrder != Double(i) {
                store.touch(trip)
                trip.folder = folder
                trip.sortOrder = Double(i)
                trip.updatedAt = now
            }
        }
    }

    /// Files places in a location folder at `index` (see `moveTrips`), or unfiles them with nil (the index is
    /// ignored). No-op for a trip folder.
    public func movePlaces(_ places: [PlaceRecord], to folder: FolderRecord?, index: Int?) {
        if let folder, folder.kind != .locations { return }
        let moving = unique(places)
        guard !moving.isEmpty else { return }
        guard let folder else {
            guard moving.contains(where: { $0.folder != nil }) else { return }
            store.perform(.movePlaces) {
                let now = store.clock()
                for place in moving where place.folder != nil {
                    store.touch(place)
                    place.folder = nil
                    place.sortOrder = 0
                    place.updatedAt = now
                }
            }
            return
        }
        let target = (folder.places ?? []).sorted(by: LibraryStore.placeOrder)
        let ordered = Self.inserting(moving, into: target, at: index) { $0.id }
        guard moving.contains(where: { $0.folder?.id != folder.id }) || ordered.map(\.id) != target.map(\.id) else { return }
        store.perform(.movePlaces) {
            let now = store.clock()
            for (i, place) in ordered.enumerated() where place.folder?.id != folder.id || place.sortOrder != Double(i) {
                store.touch(place)
                place.folder = folder
                place.sortOrder = Double(i)
                place.updatedAt = now
            }
        }
    }

    /// Pins or unpins a folder (trips or locations) to the sidebar. A pinned folder keeps its place and contents.
    public func setPinned(_ folder: FolderRecord, _ pinned: Bool) {
        guard folder.isPinned != pinned else { return }
        store.perform(pinned ? .pinFolder : .unpinFolder) {
            store.touch(folder)
            let now = store.clock()
            folder.isPinned = pinned
            folder.pinnedAt = pinned ? now : nil
            folder.updatedAt = now
        }
    }

    // MARK: Helpers

    private func nextFolderSortOrder(kind: FolderKind, excluding id: UUID) -> Double {
        (list(kind: kind).filter { $0.id != id }.map(\.sortOrder).max() ?? -1) + 1
    }

    private func unique<R: PersistentModel>(_ records: [R]) -> [R] {
        var seen = Set<PersistentIdentifier>()
        return records.filter { seen.insert($0.persistentModelID).inserted }
    }

    /// `list` with `items` removed and re-inserted before the element that was at `index` (nil or past the end = end).
    private static func inserting<T>(_ items: [T], into list: [T], at index: Int?, id: (T) -> UUID) -> [T] {
        let moving = Set(items.map(id))
        let at = min(max(0, index ?? list.count), list.count)
        let before = list[..<at].filter { !moving.contains(id($0)) }
        let after = list[at...].filter { !moving.contains(id($0)) }
        return before + items + after
    }
}
