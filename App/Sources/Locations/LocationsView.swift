import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// Locations: the spots you saved and the ones you added, in one list beside their map, with their folders as rows at
/// the top (open one, drop locations on it, or use a location's Move to Folder menu). In a folder it shows that folder's
/// spots. The sidebar only lists what is pinned. Replaces Saved (plan P3.9, critique C65).
struct LocationsView: View {
    /// The location folder to show; nil = All Locations.
    let folderID: UUID?

    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    /// The window's search field (in the sidebar) filters the list.
    private var query: String { navigation.searchText }
    @State private var sort: SavedSort = .name
    @State private var filter: SavedFilter = .all
    @State private var selection: Set<UUID> = []
    @State private var editing: PlaceRecord?
    @State private var pendingDelete: PlaceRecord?
    @State private var folderPrompt: FolderNameRequest?

    /// `selected` opens the screen with those rows selected (snapshots show a selected pin in context).
    init(folderID: UUID?, selected: Set<UUID> = []) {
        self.folderID = folderID
        _selection = State(initialValue: selected)
    }

    private var folder: FolderRecord? { folderID.flatMap { model.store.folder(id: $0) } }

    private var title: String { folder?.name ?? String(localized: "All Locations", comment: "Screen title") }

    var body: some View {
        let all = items
        let shown = SavedArranger.arrange(all, query: query, filter: filter, sort: sort)
        let _ = model.store.revision
        Group {
            if all.isEmpty && folders.isEmpty {
                empty
            } else {
                FloatingPanelLayout {
                    list(shown)
                } map: { insets in
                    LocationsMap(items: shown, selection: $selection, insets: insets)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(title)
        .toolbar(removing: .title)
        .sheet(item: $editing) { record in
            SpotEditorSheet(mode: .edit(record))
        }
        .locationFolderNamePrompt($folderPrompt)
        .onChange(of: navigation.newFolderRequest) { takeNewFolderRequest() }
        .onAppear { takeNewFolderRequest() }
        .task { if folderID == nil, DebugScripts.dragScript == "spot-to-folder" { await runSpotToFolderScript() } }
        .confirmationDialog(LightText.deleteTitle(pendingDelete?.name ?? ""), isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { record in
            Button(role: .destructive) { delete(record) } label: { Text(LightText.deleteSpot) }
        } message: { record in
            Text(LightText.deleteMessage(stops: record.stops?.count ?? 0))
        }
    }

    // MARK: Scripted drag (`-IterDragScript spot-to-folder`)

    /// Runs the drop handler a spot dragged onto a folder row calls (`LibraryDrops.onLocationsFolder`) with the hover
    /// highlight shown first, and logs the folders' contents before and after. The gesture itself is not driven.
    private func runSpotToFolderScript() async {
        await DebugScripts.pause(5)
        let store = model.store
        guard let target = store.folders(kind: .locations).first,
              let place = store.savedPlaces().first(where: { $0.folder == nil }) else { DebugScripts.say("drag: no folder or loose spot"); return }
        func state() -> String {
            store.folders(kind: .locations).map { "\($0.name)=\(store.savedPlaces(in: $0).map(\.name))" }.joined(separator: " ")
        }
        DebugScripts.say("drag before: \(state()); dragging \(place.name) onto \(target.name)")
        await DebugScripts.capture("drag-spot-0-before")
        ScriptedDropHover.shared.folderID = target.id
        await DebugScripts.capture("drag-spot-1-hover")
        let accepted = LibraryDrops(model: model).onLocationsFolder([.place(place.id)], target)
        ScriptedDropHover.shared.folderID = nil
        DebugScripts.say("drag drop accepted=\(accepted) after: \(state())")
        await DebugScripts.capture("drag-spot-2-after")
        navigation.show(.locationFolder(target.id))
        await DebugScripts.capture("drag-spot-3-folder")
        DebugScripts.finish()
    }

    // MARK: Data

    private var items: [SavedItem] {
        _ = model.store.revision
        _ = model.forecasts.revision
        let records: [PlaceRecord]
        if let folderID {
            records = model.store.folder(id: folderID).map { model.store.savedPlaces(in: $0) } ?? []
        } else {
            records = model.store.savedPlaces()
        }
        return records.map { record in
            let spot = record.spot
            let score = model.nextLight(for: spot)?.window.score
            return SavedItem(id: record.id, spot: spot, todayScore: score)
        }
    }

    /// The folders listed at the top: all of them on All Locations, none inside a folder.
    private var folders: [FolderRecord] { locationFolders(in: folder, store: model.store) }

    /// File > New Folder while this screen is up.
    private func takeNewFolderRequest() {
        guard navigation.newFolderRequest == .locations else { return }
        navigation.newFolderRequest = nil
        folderPrompt = .new(filing: [])
    }

    private func deleteFolder(_ target: FolderRecord) {
        if navigation.selection == .locationFolder(target.id) { navigation.selection = .locations }
        model.store.deleteFolder(target)
    }

    private func records(_ ids: Set<UUID>) -> [PlaceRecord] { ids.compactMap { model.store.place(id: $0) } }

    // MARK: Empty

    @ViewBuilder private var empty: some View {
        if folderID == nil {
            ContentUnavailableView {
                Label(String(localized: "Nothing saved yet", comment: "Locations empty title"), systemImage: "mappin.and.ellipse")
            } description: {
                Text("Save a spot from Explore and it shows up here with its next sunrise or sunset. Spots you add yourself live here too.",
                     comment: "Locations empty explanation")
            } actions: {
                Button { navigation.show(.explore) } label: { Text("Browse Explore", comment: "Button") }
                    .buttonStyle(.borderedProminent)
                Button {
                    navigation.show(.explore)
                    navigation.addSpotModeRequest += 1
                } label: { Text("Add Your Own Spot", comment: "Button: drop a pin on the Explore map") }
            }
        } else {
            ContentUnavailableView {
                Label(String(localized: "This folder is empty", comment: "Locations folder empty title"), systemImage: "folder")
            } description: {
                Text("Drag locations here from All Locations, or choose Move to Folder from a location's menu.",
                     comment: "Locations folder empty explanation")
            } actions: {
                Button { navigation.show(.locations) } label: { Text("Show All Locations", comment: "Button") }
            }
        }
    }

    // MARK: List

    private func list(_ shown: [SavedItem]) -> some View {
        VStack(spacing: 0) {
            FloatingPanelHeader(title: title, subtitle: Text("\(shown.count) spots", comment: "Locations count under the title")) {
                if let folder {
                    Button { navigation.show(.locations) } label: {
                        Label(String(localized: "Back", comment: "Toolbar button: up one level in Locations"), systemImage: "chevron.backward")
                    }
                    .help(Text("Back to \(String(localized: "All Locations", comment: "Screen title"))", comment: "Tooltip"))
                }
                newFolderButton
                sortMenu
            }
            listBody(shown)
        }
    }

    private func listBody(_ shown: [SavedItem]) -> some View {
        List(selection: $selection) {
            if !folders.isEmpty {
                Section {
                    ForEach(folders, id: \.id) { sub in
                        LocationFolderRow(folder: sub, rename: { folderPrompt = .rename(sub.id) }, delete: { deleteFolder(sub) })
                    }
                } header: {
                    Text("Folders", comment: "Locations section header")
                }
            }
            Section {
                ForEach(shown) { item in
                    SavedRow(item: item)
                        .tag(item.id)
                        .draggable(containerItemID: item.id)
                }
            } header: {
                if !folders.isEmpty { Text("Locations", comment: "Locations section header") }
            }
        }
        .dragContainer(for: LibraryDragItem.self) { ids in ids.map { LibraryDragItem.place($0) } }
        .listStyle(.inset)
        .layoutGrid(lanes: LayoutLane.eventRow(disclosure: true))
        .scrollContentBackground(.hidden)
        .contextMenu(forSelectionType: UUID.self) { ids in
            menu(for: ids)
        } primaryAction: { ids in
            if let item = shown.first(where: { ids.contains($0.id) }) { navigation.open(SpotRoute(spot: item.spot)) }
        }
        .onDeleteCommand { deleteSelection() }
        .overlay {
            if shown.isEmpty {
                if query.isEmpty {
                    filterEmpty
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { WeatherStatusBanner(status: model.weatherStatus) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Spacer()
                    ForecastSourceLines(app: model, coordinates: shown.map(\.spot.coordinate))
                }
                .padding(.horizontal, IterSpace.lg)
                .padding(.vertical, IterSpace.sm)
            }
        }
    }

    private var newFolderButton: some View {
        Button { folderPrompt = .new(filing: []) } label: {
            Label(String(localized: "New Folder", comment: "Toolbar button"), systemImage: "folder.badge.plus")
        }
        .help(Text("New folder", comment: "Tooltip"))
    }

    private var sortMenu: some View {
        Menu {
            Picker(selection: $sort) {
                ForEach(SavedSort.allCases, id: \.self) { (option: SavedSort) in Text(LightText.name(option)).tag(option) }
            } label: { Text("Sort By", comment: "Menu") }
            Picker(selection: $filter) {
                ForEach(SavedFilter.allCases, id: \.self) { (option: SavedFilter) in Text(LightText.name(option)).tag(option) }
            } label: { Text("Show", comment: "Menu") }
        } label: {
            Label(String(localized: "Sort and Filter", comment: "Toolbar button"), systemImage: "line.3.horizontal.decrease")
        }
        .help(Text("Sort and filter locations", comment: "Tooltip"))
    }

    private var filterEmpty: some View {
        ContentUnavailableView {
            Label(String(localized: "No spots here", comment: "Locations filter result empty"), systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("No saved spots match this filter.", comment: "Locations filter empty explanation")
        }
    }

    // MARK: Actions

    @ViewBuilder private func menu(for ids: Set<UUID>) -> some View {
        let chosen = records(ids)
        if let record = chosen.first, chosen.count == 1 {
            let spot = record.spot
            Button { navigation.open(SpotRoute(spot: spot)) } label: { Label(String(localized: "Open", comment: "Menu item"), systemImage: "arrow.right.circle") }
            AddToTripMenu(spot: spot)
            Divider()
        }
        if !chosen.isEmpty { PinLocationsButton(places: chosen) }
        if !chosen.isEmpty {
            let shared = Set(chosen.map { $0.folder?.id })
            MoveToFolderMenu(kind: .locations, currentFolderID: shared.count == 1 ? shared.first ?? nil : nil,
                             inNoFolder: shared == [nil]) { target in
                model.store.movePlaces(chosen, to: target, index: nil)
            }
            Button(String(localized: "New Folder with Selection", comment: "Context menu")) {
                folderPrompt = .new(filing: chosen.map(\.id))
            }
            if folderID != nil {
                Button(String(localized: "Remove from Folder", comment: "Context menu")) {
                    model.store.movePlaces(chosen, to: nil, index: nil)
                }
            }
            Divider()
            removal(chosen)
        }
    }

    @ViewBuilder private func removal(_ chosen: [PlaceRecord]) -> some View {
        if let record = chosen.first, chosen.count == 1 {
            if record.origin == .user {
                Button { editing = record } label: { Label(String(localized: "Edit…", comment: "Menu item"), systemImage: "pencil") }
                Button(role: .destructive) { requestDelete(record) } label: { Label(String(localized: "Delete", comment: "Menu item"), systemImage: "trash") }
            } else {
                Button { model.store.setSaved(record.spot, false) } label: { Label(String(localized: "Unsave", comment: "Menu item"), systemImage: "bookmark.slash") }
            }
        } else {
            Button { for r in chosen where r.origin != .user { model.store.setSaved(r.spot, false) } } label: {
                Label(String(localized: "Unsave", comment: "Menu item"), systemImage: "bookmark.slash")
            }
        }
    }

    /// The Delete key: removes your own spot (undoable), or unsaves a saved one.
    private func deleteSelection() {
        for record in records(selection) {
            if record.origin == .user { requestDelete(record) } else { model.store.setSaved(record.spot, false) }
        }
        selection = []
    }

    /// Deleting a spot that trips use also removes those stops, so ask first; otherwise just do it (it is undoable).
    private func requestDelete(_ record: PlaceRecord) {
        if (record.stops?.count ?? 0) > 0 { pendingDelete = record } else { delete(record) }
    }

    private func delete(_ record: PlaceRecord) {
        model.store.deletePlace(record)
        pendingDelete = nil
    }
}
