import SwiftUI
import IterFeatures
import IterModel
import IterStore
import IterUI

/// Saved Places (or one place folder) for the iPhone sheet: a system `List` with Pinned, the folders as rows that push, then the
/// places. Swipe right to pin, swipe left to delete or remove (with an Undo toast), touch and hold for the menu. A tap opens the
/// place's page (`open`).
public struct PhoneSavedList: View {
    let library: LibraryModel
    let folderID: UUID?
    let toast: PhoneUndoToast
    let open: (AppRoute) -> Void
    @Environment(AppNavigator.self) private var navigator
    @State private var renameTarget: UUID?
    @State private var newName = ""
    @State private var tripPick: PlaceRow?

    public init(library: LibraryModel, folderID: UUID? = nil, toast: PhoneUndoToast,
                open: @escaping (AppRoute) -> Void) {
        self.library = library
        self.folderID = folderID
        self.toast = toast
        self.open = open
    }

    public var body: some View {
        let s = PhonePlaceSections.make(places: library.savedPlaces, folders: library.placeFolders, folderID: folderID)
        Group {
            if library.savedPlaces.isEmpty && folderID == nil && library.placeFolders.isEmpty {
                ContentUnavailableView {
                    Label(String(localized: "No Saved Places", comment: "Empty state title"), systemImage: "bookmark")
                } description: {
                    Text("Save places in Find and they appear here.", comment: "Empty list hint")
                }
            } else {
                list(s)
            }
        }
        .alert("Rename Folder", isPresented: Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })) {
            TextField(text: $newName) { Text("Name", comment: "Rename field label") }
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if let id = renameTarget, !trimmed.isEmpty { library.renameFolder(id, to: trimmed) }
            }
        }
    }

    private func list(_ s: PhonePlaceSections) -> some View {
        List {
            if !s.pinned.isEmpty {
                Section { rows(s.pinned) } header: { Text("Pinned", comment: "Section title") }
            }
            if !s.folders.isEmpty {
                Section {
                    ForEach(s.folders) { folder in folderRow(folder) }
                } header: { Text("Folders", comment: "Section title") }
            }
            Section {
                if s.places.isEmpty && s.pinned.isEmpty {
                    Text(folderID == nil ? "Save places in Find and they appear here." : "Touch and hold a place, then choose Move to Folder.",
                         comment: "Empty list hint")
                        .font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
                        .listRowBackground(Rectangle().fill(ContentFill()))
                } else {
                    rows(s.places)
                }
            } header: {
                Text(folderID == nil ? "Places" : "In This Folder", comment: "Section title")
            }
        }
        .phoneGroupedList()
    }

    private func rows(_ places: [PlaceRow]) -> some View {
        ForEach(places) { place in
            Button { open(.place(place.id)) } label: {
                HStack(spacing: IterSpace.sm) {
                    PhonePlaceRow(row: place).frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(IterFont.caption).foregroundStyle(IterColor.textTertiary).accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .listRowBackground(Rectangle().fill(ContentFill()))
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { library.setPlacePinned(place.id, !place.isPinned) } label: {
                    Label(place.isPinned ? "Unpin" : "Pin", systemImage: place.isPinned ? "pin.slash" : "pin")
                }
                .tint(IterColor.accent)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) { remove(place) } label: {
                    Label(place.origin == .user ? "Delete" : "Remove", systemImage: place.origin == .user ? "trash" : "bookmark.slash")
                }
            }
            .contextMenu { menu(place) }
            .confirmationDialog("Add to Trip", isPresented: Binding(get: { tripPick?.id == place.id }, set: { if !$0 { tripPick = nil } }),
                                titleVisibility: .visible) {
                ForEach(library.trips.prefix(10)) { trip in
                    Button(trip.name) { if let value = library.place(id: place.id) { _ = library.addPlace(value, toTrip: trip.id) } }
                }
                Button("New Trip with This Place") { navigator.present(.newTrip(templateID: nil, firstPlace: place.id)) }
            }
        }
    }

    private func remove(_ place: PlaceRow) {
        if place.origin == .user {
            toast.perform(String(localized: "Place Deleted", comment: "Undo toast")) { library.deletePlace(place.id) }
        } else if let value = library.place(id: place.id) {
            toast.perform(String(localized: "Place Removed", comment: "Undo toast")) { library.unsavePlace(value) }
        }
    }

    @ViewBuilder private func menu(_ place: PlaceRow) -> some View {
        Button { open(.place(place.id)) } label: { Label("Open Place Page", systemImage: "info.circle") }
        Button { navigator.present(.editPlace(place.id)) } label: { Label("Edit", systemImage: "pencil") }
        Button { tripPick = place } label: { Label("Add to Trip", systemImage: "plus") }
        Button { library.setPlacePinned(place.id, !place.isPinned) } label: {
            Label(place.isPinned ? "Unpin" : "Pin", systemImage: place.isPinned ? "pin.slash" : "pin")
        }
        Menu {
            Button { library.movePlaces([place.id], to: nil) } label: {
                Toggle(isOn: .constant(place.folderID == nil)) { Text("No Folder", comment: "Menu item") }
            }
            ForEach(library.placeFolders) { folder in
                Button { library.movePlaces([place.id], to: folder.id) } label: {
                    Toggle(isOn: .constant(place.folderID == folder.id)) { Text(folder.name) }
                }
            }
        } label: { Label("Move to Folder", systemImage: "folder") }
        Divider()
        Button(role: .destructive) { remove(place) } label: {
            Label(place.origin == .user ? "Delete" : "Remove from Saved", systemImage: "trash")
        }
    }

    private func folderRow(_ folder: FolderRow) -> some View {
        Button { open(.placeFolder(folder.id)) } label: {
            HStack(spacing: IterSpace.md) {
                Image(systemName: "folder").foregroundStyle(IterColor.accentText).frame(width: 24).accessibilityHidden(true)
                Text(folder.name).font(IterFont.body).foregroundStyle(IterColor.textPrimary).lineLimit(1)
                Spacer(minLength: IterSpace.sm)
                Text(folder.count, format: .number).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary).monospacedDigit()
                Image(systemName: "chevron.right").font(IterFont.caption).foregroundStyle(IterColor.textTertiary).accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Rectangle().fill(ContentFill()))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                toast.perform(String(localized: "Folder Deleted", comment: "Undo toast")) { library.deleteFolder(folder.id) }
            } label: { Label("Delete", systemImage: "trash") }
        }
        .contextMenu {
            Button { open(.placeFolder(folder.id)) } label: { Label("Open", systemImage: "folder") }
            Button { newName = folder.name; renameTarget = folder.id } label: { Label("Rename", systemImage: "pencil") }
            Divider()
            Button(role: .destructive) {
                toast.perform(String(localized: "Folder Deleted", comment: "Undo toast")) { library.deleteFolder(folder.id) }
            } label: { Label("Delete Folder", systemImage: "trash") }
        }
        .accessibilityElement(children: .combine)
    }
}

/// One saved place: category glyph, name, locality and category, a pin glyph when pinned.
struct PhonePlaceRow: View {
    let row: PlaceRow

    var body: some View {
        HStack(spacing: IterSpace.md) {
            Image(systemName: LightText.symbol(row.category)).foregroundStyle(IterColor.textSecondary).frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text(row.name).font(IterFont.headline).foregroundStyle(IterColor.textPrimary).lineLimit(1)
                Text(detail).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary).lineLimit(1)
            }
            Spacer(minLength: IterSpace.xs)
            if row.isPinned {
                Image(systemName: "pin.fill").font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
                    .accessibilityLabel(Text("Pinned", comment: "Accessibility label"))
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let category = LightText.name(row.category)
        return row.locality.isEmpty ? category : "\(row.locality) · \(category)"
    }
}

/// The saved places on a map, for the iPhone: pins inset above the sheet; a tap on a pin runs `onSelect` (the app pushes the page).
public struct SavedPhoneMap: View {
    let places: [PlaceRow]
    let mapStyle: String
    let bottomInset: CGFloat
    let onSelect: (UUID) -> Void
    @State private var selected: UUID?

    public init(places: [PlaceRow], mapStyle: String, bottomInset: CGFloat, onSelect: @escaping (UUID) -> Void) {
        self.places = places
        self.mapStyle = mapStyle
        self.bottomInset = bottomInset
        self.onSelect = onSelect
    }

    public var body: some View {
        SavedPlacesMap(places: places, selected: $selected, mapStyle: mapStyle)
            .safeAreaPadding(.bottom, bottomInset)
            .onChange(of: selected) { _, id in
                guard let id else { return }
                onSelect(id)
                selected = nil
            }
    }
}

/// The trip's route map, inset above the sheet.
public struct TripPhoneMap: View {
    let model: BuildModel
    let mapStyle: String
    let bottomInset: CGFloat

    public init(model: BuildModel, mapStyle: String, bottomInset: CGFloat) {
        self.model = model
        self.mapStyle = mapStyle
        self.bottomInset = bottomInset
    }

    public var body: some View {
        TripRouteMap(model: model, mapStyle: mapStyle).safeAreaPadding(.bottom, bottomInset)
    }
}
