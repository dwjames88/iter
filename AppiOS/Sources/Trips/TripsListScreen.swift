import SwiftUI
import UniformTypeIdentifiers
import IterCore
import IterData
import IterDesign
import IterFeatures

/// Which trips the page shows: everything in sections, only the pinned ones, or one folder (and its subfolders).
private enum TripsFilter: Hashable {
    case all, pinned
    case folder(UUID)
}

/// iPhone Trips tab root and iPad "All Trips": the hero trip, then cards in Pinned, folder and other sections (the
/// shared page in `TripsPage.swift`); one column on iPhone, a grid on iPad. Opening a trip calls `navigation.show(.trip(id))`.
struct TripsListScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.undoManager) private var undoManager

    @State private var filter: TripsFilter = .all
    @State private var newTrip: NewTripRequest?
    @State private var importing = false
    @State private var importError: String?
    @State private var prompt: TripNamePrompt?
    @State private var deletedName: String?
    @State private var didApplyLaunch = false

    var body: some View {
        let _ = model.store.revision
        let _ = model.forecasts.revision
        let today = model.today(in: .current)
        let overview = TripsHomeModel(store: model.store, engine: model.engine, now: { model.now() })
            .overview(today: today, featuring: filter == .all)
        Group {
            if model.store.trips().isEmpty {
                ScrollView { TripsEmptyState { newTrip = NewTripRequest(templateID: $0) } }
            } else if sizeClass == .compact {
                // A List so the rows get the system's swipe actions (Pin leading, Delete trailing).
                TripsPhoneList(overview: overview, today: today, mode: mode, prompt: $prompt, chips: chipRow, onDelete: delete)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        chipRow
                        TripsPageContent(overview: overview, today: today, mode: mode, prompt: $prompt)
                    }
                }
            }
        }
        .overlay(alignment: .bottom) { undoBanner }
        .screenBackground()
        .navigationTitle(String(localized: "Trips", comment: "Screen title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { prompt = .newFolder(parent: nil, trip: nil) } label: {
                        Label(String(localized: "New Folder…", comment: "Menu item"), systemImage: "folder.badge.plus")
                    }
                    Button { importing = true } label: {
                        Label(String(localized: "Import Trip…", comment: "Menu item"), systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Label(String(localized: "More", comment: "Toolbar menu"), systemImage: "ellipsis")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { newTrip = NewTripRequest(templateID: nil) } label: {
                    Label(String(localized: "New Trip", comment: "Toolbar button"), systemImage: "plus")
                }
            }
        }
        .environment(\.openTripFolder) { id in withAnimation(.snappy) { filter = .folder(id) } }
        .tripNamePrompt($prompt)
        .sheet(item: $newTrip) { request in
            NewTripScreenSheet(initialTemplate: request.templateID)
                .presentationDetents([.large])
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.iterTrip, .json]) { result in
            switch result {
            case .success(let url):
                switch TripImport.read(url, into: model.store) {
                case .success(let id): navigation.show(.trip(id))
                case .failure(let message): importError = message
                }
            case .failure:
                importError = String(localized: "The file couldn't be read.", comment: "Import error")
            }
        }
        .alert(String(localized: "Couldn't import trip", comment: "Alert title"),
               isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button(String(localized: "OK", comment: "Alert button")) {}
        } message: {
            Text(importError ?? "")
        }
        .onAppear(perform: applyLaunch)
    }

    // MARK: Data

    private var mode: TripsPageMode {
        switch filter {
        case .all: .all
        case .pinned: .pinned
        case .folder(let id): .folder(id)
        }
    }

    // MARK: Chips

    private var chipRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: IterSpace.sm) {
                chip(String(localized: "All", comment: "Trips filter chip"), symbol: nil, value: .all)
                if !model.store.pinnedTrips().isEmpty {
                    chip(String(localized: "Pinned", comment: "Trips filter chip"), symbol: "pin.fill", value: .pinned)
                }
                ForEach(model.store.folders(kind: .trips), id: \.id) { folder in
                    chip(folder.name, symbol: "folder", value: .folder(folder.id))
                }
            }
            .filterChipStyle()
            .padding(.horizontal, sizeClass == .compact ? IterSpace.lg : TripsMetrics.margin)
            .padding(.vertical, IterSpace.sm)
        }
    }

    private func chip(_ title: String, symbol: String?, value: TripsFilter) -> some View {
        FilterChip(title: title, symbol: symbol, isOn: filter == value) {
            withAnimation(.snappy) { filter = value }
        }
    }

    // MARK: Delete and undo

    /// Deletes the trip, then offers Undo for six seconds (the store's undo manager brings the trip back).
    private func delete(_ trip: TripRecord) {
        let name = trip.name
        if navigation.selection == .trip(trip.id) { navigation.selection = .trips }
        model.store.deleteTrip(trip)
        withAnimation { deletedName = name }
        Task {
            try? await Task.sleep(for: .seconds(6))
            withAnimation { if deletedName == name { deletedName = nil } }
        }
    }

    @ViewBuilder private var undoBanner: some View {
        if let deletedName {
            HStack(spacing: IterSpace.md) {
                Text("Deleted \(deletedName)", comment: "Undo banner after deleting a trip")
                    .font(IterFont.subheadline)
                    .lineLimit(1)
                Spacer(minLength: IterSpace.sm)
                Button(String(localized: "Undo", comment: "Button")) {
                    undoManager?.undo()
                    withAnimation { self.deletedName = nil }
                }
                .font(IterFont.bodyEmphasis)
                .foregroundStyle(IterColor.accentText)
                .frame(minHeight: IterSize.hitTarget)
            }
            .padding(.horizontal, IterSpace.lg)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, IterSpace.lg)
            .padding(.bottom, IterSpace.lg)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private func applyLaunch() {
        guard !didApplyLaunch else { return }
        didApplyLaunch = true
        if let name = AppLaunch.tripsFilterName {
            if name == "pinned" { filter = .pinned }
            else if let folder = model.store.folders(kind: .trips).first(where: { $0.name == name }) { filter = .folder(folder.id) }
        }
        if AppLaunch.newTripSheet { newTrip = NewTripRequest(templateID: nil) }
    }
}

/// The iPhone page: the same hero and cards as `TripsPageContent`, as List rows so a card can swipe. Swipe right
/// pins or unpins (downloads the trip for offline use), swipe left deletes. Folder tiles keep their context menu.
private struct TripsPhoneList<Chips: View>: View {
    @Environment(AppModel.self) private var model
    let overview: TripsOverview
    let today: LocalDay
    let mode: TripsPageMode
    @Binding var prompt: TripNamePrompt?
    let chips: Chips
    let onDelete: (TripRecord) -> Void

    private let insets = EdgeInsets(top: IterSpace.sm, leading: IterSpace.lg, bottom: IterSpace.sm, trailing: IterSpace.lg)

    var body: some View {
        List {
            chips
                .listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(EdgeInsets())
            switch mode {
            case .all:
                if let hero = overview.hero {
                    row(hero) { TripHeroView(entry: hero, today: today, prompt: $prompt) }
                }
                if !overview.pinned.isEmpty || !overview.folders.isEmpty || !overview.others.isEmpty {
                    Section {
                        ForEach(overview.pinned) { card($0) }
                        ForEach(overview.folders) { tile in
                            TripFolderTileView(tile: tile, prompt: $prompt)
                                .listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(insets)
                        }
                        ForEach(overview.others) { card($0) }
                    } header: {
                        if overview.hero != nil { header(String(localized: "Your Trips", comment: "Trips grid title under the hero")) }
                    }
                }
            case .pinned:
                ForEach(overview.pinned) { card($0) }
            case .folder(let id):
                let entries = overview.folders.first { $0.id == id }?.entries ?? []
                if entries.isEmpty {
                    ContentUnavailableView {
                        Label(String(localized: "No trips here", comment: "Empty filter title"), systemImage: "folder")
                    } description: {
                        Text("Move a trip into this folder from its menu.", comment: "Empty filter explanation")
                    }
                    .listRowBackground(Color.clear).listRowSeparator(.hidden)
                }
                ForEach(entries) { card($0) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func card(_ entry: TripEntry) -> some View {
        row(entry) { TripCardView(entry: entry, prompt: $prompt) }
    }

    private func row<Content: View>(_ entry: TripEntry, @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .listRowBackground(Color.clear).listRowSeparator(.hidden).listRowInsets(insets)
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button { togglePin(entry.record) } label: {
                    entry.record.isPinned ? Label(String(localized: "Unpin", comment: "Swipe action"), systemImage: "pin.slash")
                                          : Label(String(localized: "Pin", comment: "Swipe action"), systemImage: "pin")
                }
                .tint(IterColor.accent)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) { onDelete(entry.record) } label: {
                    Label(String(localized: "Delete", comment: "Swipe action"), systemImage: "trash")
                }
            }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(IterFont.titleSection)
            .foregroundStyle(IterColor.textPrimary)
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }

    private func togglePin(_ trip: TripRecord) {
        if trip.isPinned { model.offline.unpin(trip) } else { _ = model.offline.pin(trip) }
    }
}

struct NewTripRequest: Identifiable {
    let id = UUID()
    var templateID: String?
}

// MARK: - New trip

/// New Trip as an iOS form: name, template, start date, days.
struct NewTripScreenSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss
    @State private var draft: NewTripDraft

    private static let utc = TimeZone(identifier: "UTC")!

    init(initialTemplate: String?) {
        let start = LocalDay(Date.now.addingTimeInterval(86_400), in: Self.utc)
        _draft = State(initialValue: NewTripDraft(startDay: start,
                                                  dayCount: initialTemplate.flatMap(TripTemplates.template(id:))?.dayCount ?? 3,
                                                  templateID: initialTemplate))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Name", comment: "New trip field"), text: $draft.name,
                              prompt: Text(draft.template?.defaultName ?? String(localized: "New Trip", comment: "Default trip name")))
                    Picker(String(localized: "Start from", comment: "New trip field"), selection: $draft.templateID) {
                        Text("Empty trip", comment: "No template").tag(String?.none)
                        ForEach(TripTemplates.all) { template in
                            Text(String(localized: "\(template.defaultName) · \(template.dayCount) days, \(template.stops.count) stops",
                                        comment: "Template menu item: name, days, stops")).tag(String?.some(template.id))
                        }
                    }
                }
                Section {
                    DatePicker(String(localized: "Starts", comment: "New trip field"),
                               selection: Binding(get: { draft.startDay.noon(in: Self.utc) }, set: { draft.startDay = LocalDay($0, in: Self.utc) }),
                               displayedComponents: .date)
                        .environment(\.timeZone, Self.utc)
                    Picker(String(localized: "Days", comment: "New trip field"),
                           selection: Binding(get: { draft.effectiveDayCount }, set: { draft.dayCount = $0 })) {
                        ForEach(1...TripsHomeModel.maximumDayCount, id: \.self) { days in
                            Text(InflectedCount.string("day", count: days) { AttributedString(localized: "^[\(days) day](inflect: true)", comment: "Number of days in a trip, e.g. 3 days") }).tag(days)
                        }
                    }
                    .disabled(draft.template != nil)
                } footer: {
                    if draft.template != nil {
                        Text("The template sets the number of days. You can add, move and remove stops afterwards.",
                             comment: "Explains the days picker is fixed by a template")
                    }
                }
            }
            .navigationTitle(Text("New Trip", comment: "Sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel", comment: "Button")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Create", comment: "Button: create the trip")) { create() }
                }
            }
        }
    }

    private func create() {
        let home = TripsHomeModel(store: model.store, engine: model.engine, now: { model.now() })
        let trip = home.create(draft, fallbackName: String(localized: "New Trip", comment: "Default trip name"))
        navigation.show(.trip(trip.id))
        dismiss()
    }
}
