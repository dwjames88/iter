import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// Saved: one list of the curated and Apple Maps spots you saved and every spot you added (plan P3.9, critique C65).
struct SavedView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    @State private var query = ""
    @State private var sort: SavedSort = .name
    @State private var filter: SavedFilter = .all
    @State private var selection: Set<UUID> = []
    @State private var editing: PlaceRecord?
    @State private var pendingDelete: PlaceRecord?

    var body: some View {
        let all = items
        Group {
            if all.isEmpty {
                empty
            } else {
                list(all)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(Text("Saved", comment: "Section title"))
        .snapshotOpaqueBackground()
        .sheet(item: $editing) { record in
            SpotEditorSheet(mode: .edit(record))
        }
        .confirmationDialog(deleteTitle, isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { record in
            Button(role: .destructive) { delete(record) } label: { Text("Delete Spot", comment: "Button") }
        } message: { record in
            Text("It is also removed from \(record.stops?.count ?? 0) trip stops. You can undo this.", comment: "Delete spot warning; number of trip stops using it")
        }
    }

    // MARK: Data

    private var items: [SavedItem] {
        _ = model.store.revision
        _ = model.forecasts.revision
        return model.store.savedPlaces().map { record in
            let spot = record.spot
            let score = SavedLight.headline(model, spot)?.window.score
            return SavedItem(id: record.id, spot: spot, todayScore: score)
        }
    }

    private var deleteTitle: String {
        String(localized: "Delete \u{201C}\(pendingDelete?.name ?? "")\u{201D}?", comment: "Delete spot confirmation title")
    }

    // MARK: Empty

    private var empty: some View {
        ContentUnavailableView {
            Label(String(localized: "Nothing saved yet", comment: "Saved empty title"), systemImage: "bookmark")
        } description: {
            Text("Save a spot from Explore or Scout and it shows up here with today's light. Spots you add yourself live here too.",
                 comment: "Saved empty explanation")
        } actions: {
            Button { navigation.show(.explore) } label: { Text("Browse Explore", comment: "Button") }
                .buttonStyle(.borderedProminent)
            Button {
                navigation.show(.explore)
                navigation.addSpotModeRequest += 1
            } label: { Text("Add Your Own Spot", comment: "Button: drop a pin on the Explore map") }
        }
    }

    // MARK: List

    private func list(_ all: [SavedItem]) -> some View {
        let shown = SavedArranger.arrange(all, query: query, filter: filter, sort: sort)
        return List(shown, selection: $selection) { item in
            SavedRow(item: item, intent: model.intent(for: item.spot))
                .tag(item.id)
        }
        .listStyle(.inset)
        .contextMenu(forSelectionType: UUID.self) { ids in
            menu(for: ids)
        } primaryAction: { ids in
            if let item = shown.first(where: { ids.contains($0.id) }) { open(item) }
        }
        .onDeleteCommand { deleteSelection(shown) }
        .overlay {
            if shown.isEmpty {
                if query.isEmpty {
                    filterEmpty
                } else {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: Text("Search saved spots", comment: "Search field prompt"))
        .toolbar {
            ToolbarItem { sortMenu }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Text("\(shown.count) spots", comment: "Saved count footer")
                        .font(IterFont.caption)
                        .foregroundStyle(IterColor.textSecondary)
                    Spacer()
                    WeatherAttributionView()
                }
                .padding(.horizontal, IterSpace.lg)
                .padding(.vertical, IterSpace.sm)
                .background(.bar)
            }
        }
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
            Label(String(localized: "Sort and Filter", comment: "Toolbar button"), systemImage: "line.3.horizontal.decrease.circle")
        }
        .help(Text("Sort and filter saved spots", comment: "Tooltip"))
    }

    private var filterEmpty: some View {
        ContentUnavailableView {
            Label(String(localized: "No spots here", comment: "Saved filter result empty"), systemImage: "line.3.horizontal.decrease.circle")
        } description: {
            Text("No saved spots match this filter.", comment: "Saved filter empty explanation")
        }
    }

    // MARK: Actions

    @ViewBuilder private func menu(for ids: Set<UUID>) -> some View {
        if let id = ids.first, ids.count == 1, let record = model.store.place(id: id) {
            let spot = record.spot
            Button { navigation.open(SpotRoute(spot: spot)) } label: { Label(String(localized: "Open", comment: "Menu item"), systemImage: "arrow.right.circle") }
            AddToTripMenu(spot: spot)
            Divider()
            if record.origin == .user {
                Button { editing = record } label: { Label(String(localized: "Edit…", comment: "Menu item"), systemImage: "pencil") }
                Button(role: .destructive) { requestDelete(record) } label: { Label(String(localized: "Delete", comment: "Menu item"), systemImage: "trash") }
            } else {
                Button { model.store.setSaved(spot, false) } label: { Label(String(localized: "Unsave", comment: "Menu item"), systemImage: "bookmark.slash") }
            }
        } else if !ids.isEmpty {
            Button { for id in ids { if let r = model.store.place(id: id), r.origin != .user { model.store.setSaved(r.spot, false) } } } label: {
                Label(String(localized: "Unsave", comment: "Menu item"), systemImage: "bookmark.slash")
            }
        }
    }

    private func open(_ item: SavedItem) {
        navigation.open(SpotRoute(spot: item.spot))
    }

    /// The Delete key: removes your own spot (undoable), or unsaves a saved one.
    private func deleteSelection(_ shown: [SavedItem]) {
        for id in selection {
            guard let record = model.store.place(id: id) else { continue }
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

private struct SavedRow: View {
    @Environment(AppModel.self) private var model
    let item: SavedItem
    let intent: LightIntent

    var body: some View {
        let spot = item.spot
        let headline = SavedLight.headline(model, spot)
        let window = headline?.window
        HStack(spacing: IterSpace.md) {
            Image(systemName: LightText.symbol(spot.category))
                .font(.title3)
                .foregroundStyle(IterColor.textSecondary)
                .frame(width: IterSize.lightRingSmall)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: IterSpace.xxs) {
                Text(spot.name).font(IterFont.headline).lineLimit(1)
                HStack(spacing: IterSpace.sm) {
                    Text(spot.locality.isEmpty ? LightText.name(spot.category) : spot.locality)
                        .font(IterFont.subheadline)
                        .foregroundStyle(IterColor.textSecondary)
                        .lineLimit(1)
                    ProvenanceTag(origin: spot.origin)
                }
            }
            Spacer(minLength: IterSpace.sm)
            if let window {
                VStack(alignment: .trailing, spacing: IterSpace.xxs) {
                    LightBadge(window: window, style: .compact)
                    if headline?.isTomorrow == true {
                        Text("Tomorrow", comment: "Saved row: the light shown is tomorrow's because today's window has passed")
                            .font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
                    }
                    if let reason = noForecastReason(window) {
                        Text(reason).font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
                    }
                }
            }
        }
        .padding(.vertical, IterSpace.xs)
        .accessibilityElement(children: .combine)
    }

    private func noForecastReason(_ window: LightWindow) -> String? {
        if case .noForecast(let reason) = window.assessment { return LightText.noForecastShort(reason) }
        return nil
    }
}

/// The row's headline light: today's window for the intent, or tomorrow's once today's has passed.
@MainActor private enum SavedLight {
    static func headline(_ model: AppModel, _ spot: Spot) -> (window: LightWindow, isTomorrow: Bool)? {
        let intent = model.intent(for: spot)
        let today = model.today(in: spot.timeZone)
        guard let first = model.dayLight(for: spot, on: today).headline(for: intent) else { return nil }
        if case .noForecast(.inThePast) = first.assessment,
           let next = model.dayLight(for: spot, on: today.adding(days: 1)).headline(for: intent) {
            return (next, true)
        }
        return (first, false)
    }
}
