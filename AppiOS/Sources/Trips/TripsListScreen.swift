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

    @State private var filter: TripsFilter = .all
    @State private var newTrip: NewTripRequest?
    @State private var importing = false
    @State private var importError: String?
    @State private var prompt: TripNamePrompt?
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
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        chipRow
                        TripsPageContent(overview: overview, today: today, mode: mode, prompt: $prompt)
                    }
                }
            }
        }
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
            .padding(.horizontal, IterSpace.lg)
            .padding(.vertical, IterSpace.sm)
        }
    }

    private func chip(_ title: String, symbol: String?, value: TripsFilter) -> some View {
        FilterChip(title: title, symbol: symbol, isOn: filter == value) {
            withAnimation(.snappy) { filter = value }
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
