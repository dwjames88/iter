import SwiftUI
import MapKit
import IterFeatures
import IterModel
import IterStore
import IterUI

/// Saved Places: a full-bleed map of the places with the list on a floating glass card (the layout Find uses).
struct SavedPlacesContent: View {
    let library: LibraryModel
    let folderID: UUID?
    var mapStyle = "hybrid"
    @State private var selected: UUID?

    var body: some View {
        // The card Find uses: the sidebar's glass surface, concentric with the window, over the full-bleed map.
        FindCardLayout(showsCard: true) { insets in
            SavedPlacesMap(places: library.places(in: folderID), selected: $selected, mapStyle: mapStyle)
                .safeAreaPadding(insets)
        } card: {
            SavedPlacesList(library: library, folderID: folderID, selected: $selected)
        }
        .focusedSceneValue(\.selectedSavedPlace, selected)
    }
}

/// The list part: folders as rows at the top (with counts), then the places. Drag a place onto a folder to file it.
struct SavedPlacesList: View {
    let library: LibraryModel
    let folderID: UUID?
    @Binding var selected: UUID?
    @Environment(AppNavigator.self) private var navigator
    @State private var renaming: UUID?
    @State private var folderName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        let places = library.places(in: folderID)
        List {
            if folderID == nil {
                Section {
                    ForEach(library.placeFolders) { folder in folderRow(folder) }
                    Button { newFolder() } label: {
                        Label(String(localized: "New Folder", comment: "Button"), systemImage: "folder.badge.plus")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(IterColor.accentText)
                } header: {
                    Text("Folders", comment: "Section title")
                }
            }
            Section {
                if places.isEmpty {
                    Text(folderID == nil ? "Save places in Find and they appear here." : "Drag places here to file them.", comment: "Empty list hint")
                        .font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
                }
                ForEach(places) { place in
                    PlaceListRow(row: place, isSelected: selected == place.id)
                        .equatable()
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { navigator.open(.place(place.id)) }
                        .onTapGesture { selected = place.id }
                        .draggable(PlaceDragItem(placeID: place.id))
                        .contextMenu { PlaceMenuItems(row: place, library: library) }
                        .listRowBackground(selected == place.id ? RoundedRectangle(cornerRadius: IterRadius.control).fill(IterColor.selection) : nil)
                }
            } header: {
                Text(folderID == nil ? "Places" : "Places in This Folder", comment: "Section title")
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(minHeight: 200)
    }

    private func folderRow(_ folder: FolderRow) -> some View {
        HStack(spacing: IterSpace.sm) {
            Image(systemName: folder.isPinned ? "folder.fill" : "folder").foregroundStyle(IterColor.accentText)
            if renaming == folder.id {
                TextField(text: $folderName, prompt: Text("Folder name", comment: "Placeholder")) { Text("Folder name", comment: "Label") }
                    .focused($nameFocused)
                    .onSubmit { commit(folder) }
                    .onChange(of: nameFocused) { if !nameFocused { commit(folder) } }
            } else {
                Text(folder.name).font(IterFont.body).foregroundStyle(IterColor.textPrimary).lineLimit(1)
            }
            Spacer()
            Text(folder.count, format: .number).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary).monospacedDigit()
            Image(systemName: "chevron.right").font(IterFont.caption).foregroundStyle(IterColor.textTertiary)
        }
        .contentShape(Rectangle())
        .onTapGesture { navigator.open(.placeFolder(folder.id)) }
        .contextMenu {
            Button { navigator.open(.placeFolder(folder.id)) } label: { Text("Open", comment: "Menu item") }
            Button { folderName = folder.name; renaming = folder.id; nameFocused = true } label: { Text("Rename", comment: "Menu item") }
            Button { library.setFolderPinned(folder.id, !folder.isPinned) } label: {
                Text(folder.isPinned ? "Unpin from Sidebar" : "Pin to Sidebar", comment: "Menu item")
            }
            Divider()
            Button(role: .destructive) { library.deleteFolder(folder.id) } label: { Text("Delete Folder", comment: "Menu item") }
        }
        .dropDestination(for: PlaceDragItem.self) { items, _ in
            library.movePlaces(items.map(\.placeID), to: folder.id)
            return !items.isEmpty
        }
        .accessibilityElement(children: .combine)
    }

    private func newFolder() {
        let id = library.createFolder(name: String(localized: "New Folder", comment: "Default folder name"), kind: .locations)
        folderName = String(localized: "New Folder", comment: "Default folder name")
        renaming = id
        nameFocused = true
    }

    private func commit(_ folder: FolderRow) {
        guard renaming == folder.id else { return }
        renaming = nil
        let trimmed = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != folder.name { library.renameFolder(folder.id, to: trimmed) }
    }
}

/// One place: category glyph, name, locality and category, a pin glyph when pinned.
struct PlaceListRow: View, Equatable {
    let row: PlaceRow
    let isSelected: Bool

    var body: some View {
        HStack(spacing: IterSpace.sm) {
            Image(systemName: LightText.symbol(row.category)).foregroundStyle(IterColor.textSecondary).frame(width: 20)
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
        .frame(minHeight: 40)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        let category = LightText.name(row.category)
        return row.locality.isEmpty ? category : "\(row.locality) · \(category)"
    }
}

/// The place context menu: Open Place Page, Edit (⌘E), Pin/Unpin, Move to Folder, Remove or Delete.
struct PlaceMenuItems: View {
    let row: PlaceRow
    let library: LibraryModel
    @Environment(AppNavigator.self) private var navigator

    var body: some View {
        Button { navigator.open(.place(row.id)) } label: { Text("Open Place Page", comment: "Menu item") }
        Button { navigator.present(.editPlace(row.id)) } label: { Text("Edit…", comment: "Menu item") }
            .keyboardShortcut("e", modifiers: .command)
        Button { library.setPlacePinned(row.id, !row.isPinned) } label: { Text(row.isPinned ? "Unpin" : "Pin", comment: "Menu item") }
        Menu {
            Button { library.movePlaces([row.id], to: nil) } label: {
                Toggle(isOn: .constant(row.folderID == nil)) { Text("No Folder", comment: "Menu item") }
            }
            ForEach(library.placeFolders) { folder in
                Button { library.movePlaces([row.id], to: folder.id) } label: {
                    Toggle(isOn: .constant(row.folderID == folder.id)) { Text(folder.name) }
                }
            }
        } label: { Text("Move to Folder", comment: "Menu item") }
        Divider()
        if row.origin == .user {
            Button(role: .destructive) { library.deletePlace(row.id) } label: { Text("Delete", comment: "Menu item") }
        } else {
            Button(role: .destructive) { if let place = library.place(id: row.id) { library.unsavePlace(place) } } label: {
                Text("Remove from Saved", comment: "Menu item")
            }
        }
    }
}

/// The places on a map: solid category plates, the selected one scaled. Fits the places once.
struct SavedPlacesMap: View {
    let places: [PlaceRow]
    @Binding var selected: UUID?
    let mapStyle: String
    @State private var position: MapCameraPosition = .automatic
    @State private var fitted = false

    var body: some View {
        Map(position: $position, selection: $selected) {
            UserAnnotation()
            ForEach(places) { place in
                Annotation(place.name, coordinate: CLLocationCoordinate2D(latitude: place.coordinate.latitude, longitude: place.coordinate.longitude),
                           anchor: .center) {
                    Image(systemName: LightText.symbol(place.category))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(IterColor.onAccent)
                        .frame(width: 28, height: 28)
                        .background(selected == place.id ? IterColor.mapPin : IterColor.brandDot, in: Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                        .scaleEffect(selected == place.id ? IterEvent.pinScaleSelected : 1)
                        .shadow(radius: selected == place.id ? IterEvent.pinShadowRadiusSelected : IterEvent.pinShadowRadius, y: 1)
                }
                .tag(place.id)
            }
        }
        .mapStyle(BuildMapStyle.make(mapStyle))
        .onAppear { fit() }
        .onChange(of: places.map(\.id)) { if !fitted { fit() } }
    }

    private func fit() {
        guard !fitted, let region = GeoRegion.enclosing(places.map(\.coordinate)) else { return }
        fitted = true
        position = .region(RouteCamera.region(region))
    }
}
