import SwiftUI
import MapKit
import IterCore
import IterData
import IterDesign
import IterFeatures

/// Locations on iOS (all, or one folder): a Folders section of rows (count, pin mark, drop target), a small collapsible map of the spots, then the list of
/// saved and own places. Swipe to unsave or delete (undoable through the store), context menu for the rest.
struct LocationsScreen: View {
    let folderID: UUID?

    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    @State private var query = ""
    @State private var sort: SavedSort = .name
    @State private var filter: SavedFilter = .all
    @State private var editing: PlaceRecord?
    @State private var pendingDelete: PlaceRecord?
    @State private var folderPrompt: FolderNameRequest?
    @State private var folderToDelete: FolderRecord?
    @AppStorage("IterLocationsMapShown") private var mapShown = true
    @Environment(\.isInFloatingSheet) private var isInFloatingSheet
    @Environment(PhoneBackdrop.self) private var backdrop: PhoneBackdrop?

    private var store: IterStore { model.store }
    private var folder: FolderRecord? { folderID.flatMap { store.folder(id: $0) } }
    private var title: String { folder?.name ?? String(localized: "Locations", comment: "Screen title") }

    var body: some View {
        let all = items
        let shown = SavedArranger.arrange(all, query: query, filter: filter, sort: sort)
        List {
            if !folders.isEmpty {
                Section {
                    ForEach(folders, id: \.id) { sub in
                        LocationFolderRow(folder: sub, rename: { folderPrompt = .rename(sub.id) }, delete: { folderToDelete = sub })
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { folderToDelete = sub } label: { Label(String(localized: "Delete", comment: "Swipe action"), systemImage: "trash") }
                                Button { folderPrompt = .rename(sub.id) } label: { Label(String(localized: "Rename", comment: "Swipe action"), systemImage: "pencil") }
                                    .tint(IterColor.textSecondary)
                            }
                            .swipeActions(edge: .leading) {
                                Button { store.setPinned(sub, !sub.isPinned) } label: {
                                    Label(sub.isPinned ? String(localized: "Unpin", comment: "Swipe action") : String(localized: "Pin", comment: "Swipe action"),
                                          systemImage: sub.isPinned ? "pin.slash" : "pin")
                                }
                                .tint(IterColor.accent)
                            }
                    }
                } header: {
                    Text("Folders", comment: "Locations section header")
                }
            }
            if !all.isEmpty {
                HStack {
                    Text("\(shown.count) spots", comment: "Locations count header")
                        .font(IterFont.callout)
                        .foregroundStyle(IterColor.textSecondary)
                    Spacer()
                    // In the phone's sheet the spots are on the map behind it.
                    if !isInFloatingSheet {
                    Button { withAnimation { mapShown.toggle() } } label: {
                        Text(mapShown ? "Hide map" : "Show map", comment: "Button: collapse or expand the Locations map")
                            .font(IterFont.callout)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(IterColor.accentText)
                    }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: IterSpace.lg, bottom: 0, trailing: IterSpace.lg))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                if mapShown, !isInFloatingSheet {
                    LocationsMapHeader(items: shown, onOpen: open)
                        .frame(height: 190)
                        .clipShape(RoundedRectangle(cornerRadius: IterRadius.panel, style: .continuous))
                        .listRowInsets(EdgeInsets(top: 0, leading: IterSpace.lg, bottom: IterSpace.sm, trailing: IterSpace.lg))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                ForEach(shown) { item in
                    row(item)
                }
                if shown.isEmpty { filterEmpty }
            }
        }
        .listStyle(.plain)
        .onChange(of: shown.map(\.id), initial: true) { backdrop?.locations = shown }
        .listSectionSpacing(.compact)
        .scrollContentBackground(.hidden)
        .screenBackground()
        .safeAreaInset(edge: .top, spacing: 0) { WeatherStatusBanner(status: model.weatherStatus) }
        .overlay { if all.isEmpty && folders.isEmpty { empty } }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, prompt: Text("Search locations", comment: "Search field prompt"))
        .toolbar { toolbar }
        .sheet(item: $editing) { record in SpotEditorSheet(mode: .edit(record)) }
        .locationFolderNamePrompt($folderPrompt)
        .confirmationDialog(String(localized: "Delete this folder?", comment: "Dialog title"), isPresented: Binding(get: { folderToDelete != nil }, set: { if !$0 { folderToDelete = nil } }), titleVisibility: .visible, presenting: folderToDelete) { target in
            Button(String(localized: "Delete Folder", comment: "Button"), role: .destructive) { deleteFolder(target) }
        } message: { _ in
            Text("The spots inside stay saved. Only the folder goes.", comment: "Dialog message: deleting a locations folder")
        }
        .confirmationDialog(LightText.deleteTitle(pendingDelete?.name ?? ""), isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { record in
            Button(role: .destructive) { delete(record) } label: { Text(LightText.deleteSpot) }
        } message: { record in
            Text(LightText.deleteMessage(stops: record.stops?.count ?? 0))
        }
        .onChange(of: navigation.newFolderRequest) { takeNewFolderRequest() }
        .onAppear { takeNewFolderRequest() }
    }

    private var folders: [FolderRecord] { _ = store.revision; return locationFolders(in: folder, store: store) }

    private func takeNewFolderRequest() {
        guard navigation.newFolderRequest == .locations else { return }
        navigation.newFolderRequest = nil
        folderPrompt = .new(filing: [])
    }

    private func deleteFolder(_ target: FolderRecord) {
        folderToDelete = nil
        if navigation.selection == .locationFolder(target.id) { navigation.selection = target.parent.map { .locationFolder($0.id) } ?? .locations }
        store.deleteFolder(target)
    }

    // MARK: Data

    private var items: [SavedItem] {
        _ = store.revision
        _ = model.forecasts.revision
        let records: [PlaceRecord]
        if let folder { records = store.savedPlaces(in: folder) } else { records = store.savedPlaces() }
        return records.map { SavedItem(id: $0.id, spot: $0.spot, todayScore: model.nextLight(for: $0.spot)?.window.score) }
    }

    private func record(_ item: SavedItem) -> PlaceRecord? { store.place(id: item.id) }

    private func open(_ spot: Spot) { navigation.open(SpotRoute(spot: spot)) }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker(selection: $sort) {
                    ForEach(SavedSort.allCases, id: \.self) { (option: SavedSort) in Text(LightText.name(option)).tag(option) }
                } label: { Text("Sort By", comment: "Menu") }
                Picker(selection: $filter) {
                    ForEach(SavedFilter.allCases, id: \.self) { (option: SavedFilter) in Text(LightText.name(option)).tag(option) }
                } label: { Text("Show", comment: "Menu") }
                Divider()
                Button { folderPrompt = .new(filing: []) } label: {
                    Label(String(localized: "New Folder", comment: "Menu item"), systemImage: "folder.badge.plus")
                }
                if let folder {
                    Button { store.setPinned(folder, !folder.isPinned) } label: {
                        Label(folder.isPinned ? String(localized: "Unpin from Sidebar", comment: "Menu item") : String(localized: "Pin to Sidebar", comment: "Menu item"),
                              systemImage: folder.isPinned ? "pin.slash" : "pin")
                    }
                    Button { folderPrompt = .rename(folder.id) } label: {
                        Label(String(localized: "Rename Folder", comment: "Menu item"), systemImage: "pencil")
                    }
                    Button(role: .destructive) { folderToDelete = folder } label: {
                        Label(String(localized: "Delete Folder", comment: "Menu item"), systemImage: "trash")
                    }
                }
            } label: {
                Label(String(localized: "More", comment: "Toolbar button"), systemImage: "ellipsis.circle")
            }
        }
    }

    // MARK: Rows

    private func row(_ item: SavedItem) -> some View {
        Button { open(item.spot) } label: { LocationRow(item: item) }
            .buttonStyle(.plain)
            .listRowBackground(Color.clear)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if let place = record(item) {
                    if place.origin == .user {
                        Button(role: .destructive) { requestDelete(place) } label: {
                            Label(String(localized: "Delete", comment: "Swipe action"), systemImage: "trash")
                        }
                    } else {
                        Button(role: .destructive) { store.setSaved(place.spot, false) } label: {
                            Label(String(localized: "Unsave", comment: "Swipe action"), systemImage: "bookmark.slash")
                        }
                    }
                }
            }
            .contextMenu { menu(for: item) }
            .draggable(LibraryDragItem.place(item.id))
    }

    @ViewBuilder private func menu(for item: SavedItem) -> some View {
        if let place = record(item) {
            Button { open(item.spot) } label: { Label(String(localized: "Open", comment: "Menu item"), systemImage: "arrow.right.circle") }
            AddToTripMenu(spot: item.spot)
            Divider()
            MoveToFolderMenu(kind: .locations, currentFolderID: place.folder?.id, inNoFolder: place.folder == nil) { target in
                store.movePlaces([place], to: target, index: nil)
            }
            PinLocationsButton(places: [place])
            Button { folderPrompt = .new(filing: [place.id]) } label: {
                Label(String(localized: "New Folder with Spot", comment: "Context menu"), systemImage: "folder.badge.plus")
            }
            if folderID != nil {
                Button { store.movePlaces([place], to: nil, index: nil) } label: {
                    Label(String(localized: "Remove from Folder", comment: "Context menu"), systemImage: "folder.badge.minus")
                }
            }
            Divider()
            if place.origin == .user {
                Button { editing = place } label: { Label(String(localized: "Edit…", comment: "Menu item"), systemImage: "pencil") }
                Button(role: .destructive) { requestDelete(place) } label: { Label(String(localized: "Delete", comment: "Menu item"), systemImage: "trash") }
            } else {
                Button(role: .destructive) { store.setSaved(place.spot, false) } label: {
                    Label(String(localized: "Unsave", comment: "Menu item"), systemImage: "bookmark.slash")
                }
            }
        }
    }

    /// Deleting a spot that trips use also removes those stops, so ask first; otherwise just do it (it is undoable).
    private func requestDelete(_ place: PlaceRecord) {
        if (place.stops?.count ?? 0) > 0 { pendingDelete = place } else { delete(place) }
    }

    private func delete(_ place: PlaceRecord) {
        store.deletePlace(place)
        pendingDelete = nil
    }

    // MARK: Empty

    @ViewBuilder private var empty: some View {
        if folderID == nil {
            ContentUnavailableView {
                Label(String(localized: "Nothing saved yet", comment: "Locations empty title"), systemImage: "mappin.and.ellipse")
            } description: {
                Text("Save a spot from Explore and it shows up here with its next sunrise or sunset. Spots you add yourself live here too.",
                     comment: "Locations empty explanation")
            } actions: {
                Button { navigation.show(.explore) } label: { Text("Browse Explore", comment: "Button").frame(minHeight: 28) }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 120)
        } else {
            ContentUnavailableView {
                Label(String(localized: "This folder is empty", comment: "Locations folder empty title"), systemImage: "folder")
            } description: {
                Text("Choose Move to Folder from a location's menu in All Locations to file it here.",
                     comment: "Locations folder empty explanation on iPhone and iPad")
            } actions: {
                Button { navigation.show(.locations) } label: { Text("Show All Locations", comment: "Button") }
                Button { navigation.show(.explore) } label: { Text("Browse Explore", comment: "Button") }
            }
            .padding(.top, 120)
        }
    }

    private var filterEmpty: some View {
        ContentUnavailableView {
            Label(String(localized: "No spots here", comment: "Locations filter result empty"), systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text(query.isEmpty ? String(localized: "No saved spots match this filter.", comment: "Locations filter empty explanation")
                               : String(localized: "Nothing matches your search.", comment: "Locations search empty explanation"))
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

// MARK: - Row

private struct LocationRow: View {
    @Environment(AppModel.self) private var model
    let item: SavedItem

    var body: some View {
        let spot = item.spot
        let next = model.savedEvent(for: spot)
        HStack(spacing: IterSpace.sm) {
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                Text(spot.name)
                    .font(IterFont.headline)
                    .foregroundStyle(IterColor.textPrimary)
                    .lineLimit(2)
                HStack(spacing: IterSpace.xs) {
                    Image(systemName: LightText.symbol(spot.category))
                        .accessibilityHidden(true)
                    Text(spot.locality.isEmpty ? LightText.name(spot.category) : spot.locality)
                        .lineLimit(1)
                }
                .font(IterFont.secondary)
                .foregroundStyle(IterColor.textSecondary)
                if spot.origin == .user {
                    Text("Added by you", comment: "Tag on a spot the user added")
                        .font(IterFont.captionStrong)
                        .foregroundStyle(IterColor.accentText)
                        .padding(.horizontal, IterSpace.sm)
                        .padding(.vertical, 2)
                        .background(IterColor.accent.opacity(0.14), in: Capsule())
                }
            }
            Spacer(minLength: IterSpace.sm)
            EventLane(window: next?.window, zone: spot.timeZone, isLoading: model.forecasts.isLoading(spot.coordinate),
                      isTomorrow: next?.isTomorrow ?? false)
        }
        .padding(.vertical, IterSpace.sm)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Map

/// The small map above the list: a pin per spot (the event unit as Explore draws it), framed to fit them.
struct LocationsMapHeader: View {
    @Environment(AppModel.self) private var model
    let items: [SavedItem]
    let onOpen: (Spot) -> Void
    /// Full screen behind the phone's sheet: the sheet's height as the bottom inset, and the map controls top trailing.
    var backdropInset: CGFloat?
    @State private var position: MapCameraPosition = .automatic
    @State private var selection: UUID?
    @AppStorage(MapStyleChoice.storageKey) private var mapStyleRaw = MapStyleChoice.default.rawValue

    var body: some View {
        Map(position: $position, selection: $selection) {
            ForEach(items) { item in
                Annotation(item.spot.name, coordinate: CLLocationCoordinate2D(latitude: item.spot.coordinate.latitude, longitude: item.spot.coordinate.longitude)) {
                    pin(item.spot)
                }
                .tag(item.id)
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(MapStyleChoice(stored: mapStyleRaw).mapStyle())
        .mapControls { MapCompass() }
        .safeAreaPadding(.bottom, backdropInset ?? 0)
        .overlay(alignment: backdropInset == nil ? .bottomTrailing : .topTrailing) {
            if backdropInset == nil {
                MapStyleMenu().padding(IterSpace.sm)
            } else {
                MapStyleMenu(isGlass: false)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .padding(.trailing, IterSpace.lg)
                    .padding(.top, IterSpace.sm)
            }
        }
        .onAppear { position = Self.framing(items) }
        .onChange(of: items.map(\.id)) { withAnimation { position = Self.framing(items) } }
        .onChange(of: selection) { _, id in
            guard let id, let item = items.first(where: { $0.id == id }) else { return }
            selection = nil
            onOpen(item.spot)
        }
    }

    @ViewBuilder private func pin(_ spot: Spot) -> some View {
        if let event = model.savedEvent(for: spot) {
            EventScore(window: event.window, zone: spot.timeZone, timeStyle: .start, variant: .pin,
                       isLoading: event.isLoading, isTomorrow: event.isTomorrow, isSelected: false)
        } else {
            Circle().fill(IterColor.mapPin)
                .frame(width: 14, height: 14)
                .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 1.5))
                .accessibilityLabel(Text(spot.name))
        }
    }

    private static func framing(_ items: [SavedItem]) -> MapCameraPosition {
        guard let r = GeoRegion.enclosing(items.map(\.spot.coordinate), padding: 0.4, minimumDelta: 0.2) else { return .automatic }
        return .region(MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: r.center.latitude, longitude: r.center.longitude),
            span: MKCoordinateSpan(latitudeDelta: r.latitudeDelta, longitudeDelta: r.longitudeDelta)))
    }
}
