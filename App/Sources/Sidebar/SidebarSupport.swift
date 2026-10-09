import SwiftUI
import IterCore
import IterData
import IterFeatures

// MARK: - New folders

extension AppNavigation {
    /// The kind of folder New Folder makes: locations when a locations screen is up, trips otherwise.
    var newFolderKind: FolderKind {
        switch selection {
        case .locations, .locationFolder: .locations
        default: .trips
        }
    }

    /// Makes a folder named "New Folder" (numbered if taken), optionally holding a selection, and asks the screen that
    /// shows it to rename it (`renamingID`).
    @discardableResult
    func newFolder(model: AppModel, kind: FolderKind? = nil,
                   trips: [TripRecord] = [], places: [PlaceRecord] = []) -> FolderRecord {
        let kind = kind ?? newFolderKind
        let siblings = model.store.folders(kind: kind)
        let name = LibraryNaming.uniqueName(String(localized: "New Folder", comment: "Default name of a new folder"), among: siblings.map(\.name))
        let folder = model.store.createFolder(name: name, kind: kind, trips: trips, places: places)
        renamingID = folder.id
        return folder
    }
}

// MARK: - Dropping

/// What dropping library items on each kind of sidebar row does. All changes go through the store (so they undo).
@MainActor
struct LibraryDrops {
    let model: AppModel
    private var store: IterStore { model.store }

    private func trips(_ items: [LibraryDragItem]) -> [TripRecord] { items.compactMap(\.tripID).compactMap { store.trip(id: $0) } }
    private func places(_ items: [LibraryDragItem]) -> [PlaceRecord] { items.compactMap(\.placeID).compactMap { store.place(id: $0) } }
    /// A trips folder: trips are filed at its end. Folders do not nest, so a dropped folder does nothing.
    func onTripsFolder(_ items: [LibraryDragItem], _ folder: FolderRecord) -> Bool {
        let moving = trips(items)
        if !moving.isEmpty { store.moveTrips(moving, to: folder, index: nil) }
        return !moving.isEmpty
    }

    /// "All Trips": trips are unfiled.
    func onAllTrips(_ items: [LibraryDragItem]) -> Bool {
        let moving = trips(items)
        if !moving.isEmpty { store.moveTrips(moving, to: nil, index: nil) }
        return !moving.isEmpty
    }

    /// A locations folder: places are filed in it.
    func onLocationsFolder(_ items: [LibraryDragItem], _ folder: FolderRecord) -> Bool {
        let moving = places(items)
        if !moving.isEmpty { store.movePlaces(moving, to: folder, index: nil) }
        return !moving.isEmpty
    }
}
