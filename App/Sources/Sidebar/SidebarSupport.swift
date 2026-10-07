import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

// MARK: - Expansion

/// Which sidebar folders are open, remembered per folder id as a comma-separated list in one stored string.
struct FolderExpansion {
    let raw: Binding<String>

    private var ids: Set<String> { Set(raw.wrappedValue.split(separator: ",").map(String.init)) }

    func isExpanded(_ id: UUID) -> Bool { AppLaunch.expandFolders || ids.contains(id.uuidString) }

    func set(_ id: UUID, _ expanded: Bool) {
        var all = ids
        if expanded { all.insert(id.uuidString) } else { all.remove(id.uuidString) }
        raw.wrappedValue = all.sorted().joined(separator: ",")
    }

    func binding(for id: UUID) -> Binding<Bool> {
        Binding(get: { isExpanded(id) }, set: { set(id, $0) })
    }
}

// MARK: - New folders

extension AppNavigation {
    /// The kind of folder New Folder makes: locations when a locations screen is up, trips otherwise.
    var newFolderKind: FolderKind {
        switch selection {
        case .locations, .locationFolder: .locations
        default: .trips
        }
    }

    /// Makes a folder named "New Folder" (numbered if taken), optionally holding a selection, and puts its sidebar row
    /// into rename.
    @discardableResult
    func newFolder(model: AppModel, kind: FolderKind? = nil, parent: FolderRecord? = nil,
                   trips: [TripRecord] = [], places: [PlaceRecord] = []) -> FolderRecord {
        let kind = kind ?? newFolderKind
        let siblings = parent.map { model.store.subfolders(of: $0) } ?? model.store.folders(kind: kind)
        let name = LibraryNaming.uniqueName(String(localized: "New Folder", comment: "Default name of a new folder"), among: siblings.map(\.name))
        let folder = model.store.createFolder(name: name, kind: kind, parent: parent, trips: trips, places: places)
        renamingID = folder.id
        return folder
    }
}

// MARK: - Inline rename

/// A sidebar label whose title becomes a text field while `navigation.renamingID` is this row's id.
struct RenamableLabel<Trailing: View>: View {
    @Environment(AppNavigation.self) private var navigation
    let id: UUID
    let title: String
    let symbol: String
    let rename: (String) -> Void
    @ViewBuilder var trailing: Trailing

    var body: some View {
        let renaming = navigation.renamingID == id
        Label {
            HStack(spacing: IterSpace.xs) {
                if renaming {
                    InlineRenameField(initial: title, commit: rename) { navigation.renamingID = nil }
                } else {
                    Text(title).lineLimit(1)
                }
                Spacer(minLength: 0)
                trailing
            }
        } icon: {
            Image(systemName: symbol)
        }
        .accessibilityElement(children: renaming ? .contain : .combine)
    }
}

/// The text field itself: focused when it appears, commits on Return or focus loss, Escape cancels, empty is rejected.
private struct InlineRenameField: View {
    let initial: String
    let commit: (String) -> Void
    let finish: () -> Void
    @State private var text = ""
    @State private var finished = false
    @FocusState private var focused: Bool

    var body: some View {
        TextField(String(localized: "Name", comment: "Inline rename field"), text: $text)
            .textFieldStyle(.plain)
            .focused($focused)
            .onSubmit { done(save: true) }
            #if os(macOS)
            .onExitCommand { done(save: false) }
            #endif
            .onChange(of: focused) { _, now in if !now { done(save: true) } }
            .onAppear {
                text = initial
                DispatchQueue.main.async { focused = true }
            }
    }

    private func done(save: Bool) {
        guard !finished else { return }
        finished = true
        if save, let name = LibraryNaming.cleanedName(text), name != initial { commit(name) }
        finish()
    }
}

// MARK: - Dropping

/// Lightly highlights a row while a library item is dragged over it, and hands the drop to `handler`.
private struct LibraryDropModifier: ViewModifier {
    let handler: ([LibraryDragItem]) -> Bool
    @State private var targeted = false

    func body(content: Content) -> some View {
        content
            .dropDestination(for: LibraryDragItem.self) { items, _ in handler(items) } isTargeted: { targeted = $0 }
            .background {
                if targeted {
                    RoundedRectangle(cornerRadius: IterRadius.control, style: .continuous)
                        .fill(IterColor.accent.opacity(0.18))
                        .padding(.horizontal, -IterSpace.xs)
                }
            }
    }
}

extension View {
    /// Accepts dragged library items; `handler` returns whether it used them.
    func libraryDrop(_ handler: @escaping ([LibraryDragItem]) -> Bool) -> some View {
        modifier(LibraryDropModifier(handler: handler))
    }
}

/// What dropping library items on each kind of sidebar row does. All changes go through the store (so they undo).
@MainActor
struct LibraryDrops {
    let model: AppModel
    private var store: IterStore { model.store }

    private func trips(_ items: [LibraryDragItem]) -> [TripRecord] { items.compactMap(\.tripID).compactMap { store.trip(id: $0) } }
    private func places(_ items: [LibraryDragItem]) -> [PlaceRecord] { items.compactMap(\.placeID).compactMap { store.place(id: $0) } }
    private func folders(_ items: [LibraryDragItem], kind: FolderKind) -> [FolderRecord] {
        items.compactMap(\.folderID).compactMap { store.folder(id: $0) }.filter { $0.kind == kind }
    }

    /// A trips folder: trips are filed at its end, a folder moves inside it (root folders without subfolders only).
    func onTripsFolder(_ items: [LibraryDragItem], _ folder: FolderRecord) -> Bool {
        let moving = trips(items), nested = folders(items, kind: .trips)
        if !moving.isEmpty { store.moveTrips(moving, to: folder, index: nil) }
        for dragged in nested where dragged.id != folder.id { store.moveFolder(dragged, to: folder, index: nil) }
        return !moving.isEmpty || !nested.isEmpty
    }

    /// "All Trips": trips are unfiled, folders go back to the top level.
    func onAllTrips(_ items: [LibraryDragItem]) -> Bool {
        let moving = trips(items), nested = folders(items, kind: .trips)
        if !moving.isEmpty { store.moveTrips(moving, to: nil, index: nil) }
        for dragged in nested { store.moveFolder(dragged, to: nil, index: nil) }
        return !moving.isEmpty || !nested.isEmpty
    }

    /// A trip row: a dragged trip goes before it in its container; on a pinned row (or the pinned group) it is pinned.
    func onTripRow(_ items: [LibraryDragItem], before target: TripRecord) -> Bool {
        let moving = trips(items).filter { $0.id != target.id }
        guard !moving.isEmpty else { return false }
        if target.isPinned { return pin(moving) }
        let index = store.trips(in: target.folder).firstIndex { $0.id == target.id }
        store.moveTrips(moving, to: target.folder, index: index)
        return true
    }

    func pin(_ moving: [TripRecord]) -> Bool {
        for trip in moving where !trip.isPinned { model.offline.pin(trip) }
        return !moving.isEmpty
    }

    func onPinned(_ items: [LibraryDragItem]) -> Bool { pin(trips(items)) }

    /// A locations folder: places are filed in it, a folder moves inside it.
    func onLocationsFolder(_ items: [LibraryDragItem], _ folder: FolderRecord) -> Bool {
        let moving = places(items), nested = folders(items, kind: .locations)
        if !moving.isEmpty { store.movePlaces(moving, to: folder, index: nil) }
        for dragged in nested where dragged.id != folder.id { store.moveFolder(dragged, to: folder, index: nil) }
        return !moving.isEmpty || !nested.isEmpty
    }

    /// "All Locations": places are unfiled, folders go back to the top level.
    func onAllLocations(_ items: [LibraryDragItem]) -> Bool {
        let moving = places(items), nested = folders(items, kind: .locations)
        if !moving.isEmpty { store.movePlaces(moving, to: nil, index: nil) }
        for dragged in nested { store.moveFolder(dragged, to: nil, index: nil) }
        return !moving.isEmpty || !nested.isEmpty
    }
}
