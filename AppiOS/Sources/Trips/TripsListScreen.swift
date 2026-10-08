import SwiftUI
import UniformTypeIdentifiers
import IterCore
import IterData
import IterDesign
import IterFeatures

/// Which trips the list shows: everything in sections, only the pinned ones, or one folder (and its subfolders).
private enum TripsFilter: Hashable {
    case all, pinned
    case folder(UUID)
}

private struct TripGroup: Identifiable {
    var id: String
    var title: String?
    var symbol: String?
    var trips: [TripRecord]
}

/// iPhone Trips tab root and iPad "All Trips": the "My Flights" list (IOS-REFERENCE pattern 15). Pinned trips first, then
/// each folder, then unfiled, in the order the sidebar uses. Opening a trip calls `navigation.show(.trip(id))`.
struct TripsListScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.undoManager) private var undoManager

    @State private var filter: TripsFilter = .all
    @State private var newTrip: NewTripRequest?
    @State private var importing = false
    @State private var importError: String?
    @State private var renaming: TripRecord?
    @State private var renameText = ""
    @State private var deletedName: String?
    @State private var didApplyLaunch = false

    var body: some View {
        let _ = model.store.revision
        let groups = groups(for: filter)
        let hasTrips = !model.store.trips().isEmpty
        Group {
            if !hasTrips {
                EmptyTripsState { newTrip = NewTripRequest(templateID: $0) }
            } else {
                List {
                    chipRow
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets())
                    ForEach(groups) { group in
                        Section {
                            ForEach(group.trips, id: \.id) { trip in
                                TripCardRow(trip: trip, onRename: beginRename, onDelete: delete)
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                    .listRowInsets(EdgeInsets(top: IterSpace.xs, leading: IterSpace.lg, bottom: IterSpace.xs, trailing: IterSpace.lg))
                            }
                        } header: {
                            if let title = group.title { groupHeader(group, title) }
                        }
                    }
                    if groups.isEmpty { noMatches }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .screenBackground()
        .navigationTitle(String(localized: "Trips", comment: "Screen title"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
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
        .overlay(alignment: .bottom) { undoBanner }
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
        .alert(String(localized: "Rename trip", comment: "Alert title"), isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(String(localized: "Trip name", comment: "Placeholder"), text: $renameText)
            Button(String(localized: "Cancel", comment: "Button"), role: .cancel) {}
            Button(String(localized: "Rename", comment: "Button")) {
                let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                if let renaming, !trimmed.isEmpty { model.store.renameTrip(renaming, to: trimmed) }
            }
        }
        .onAppear(perform: applyLaunch)
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

    private func groupHeader(_ group: TripGroup, _ title: String) -> some View {
        Label {
            Text(title).font(.subheadline.weight(.semibold))
        } icon: {
            if let symbol = group.symbol { Image(systemName: symbol).font(IterFont.caption) }
        }
        .foregroundStyle(IterColor.textSecondary)
        .padding(.horizontal, IterSpace.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }

    private var noMatches: some View {
        ContentUnavailableView {
            Label(String(localized: "No trips here", comment: "Empty filter title"), systemImage: "folder")
        } description: {
            Text("Move a trip into this folder from its menu.", comment: "Empty filter explanation")
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    // MARK: Data

    /// Pinned first, then folders (subfolders after their parent), then unfiled. A pinned trip is listed once, in Pinned.
    private func groups(for filter: TripsFilter) -> [TripGroup] {
        let store = model.store
        let pinned = store.pinnedTrips()
        var out: [TripGroup] = []
        var folderGroups: [TripGroup] = []
        for root in store.folders(kind: .trips) {
            let direct = store.trips(in: root).filter { !$0.isPinned }
            if !direct.isEmpty || filter == .folder(root.id) {
                folderGroups.append(TripGroup(id: root.id.uuidString, title: root.name, symbol: "folder", trips: direct))
            }
            for sub in store.subfolders(of: root) {
                let inSub = store.trips(in: sub).filter { !$0.isPinned }
                if !inSub.isEmpty {
                    folderGroups.append(TripGroup(id: sub.id.uuidString, title: "\(root.name) › \(sub.name)", symbol: "folder", trips: inSub))
                }
            }
        }
        let unfiled = store.trips(in: nil).filter { !$0.isPinned }
        switch filter {
        case .all:
            if !pinned.isEmpty {
                out.append(TripGroup(id: "pinned", title: String(localized: "Pinned", comment: "Trips list section"), symbol: "pin.fill", trips: pinned))
            }
            out += folderGroups
            if !unfiled.isEmpty {
                let title = out.isEmpty ? nil : String(localized: "Other trips", comment: "Trips list section for trips in no folder")
                out.append(TripGroup(id: "unfiled", title: title, symbol: nil, trips: unfiled))
            }
        case .pinned:
            if !pinned.isEmpty { out.append(TripGroup(id: "pinned", title: nil, symbol: nil, trips: pinned)) }
        case .folder(let id):
            let wanted = store.folder(id: id)
            let ids = Set(([id] + (wanted.map { store.subfolders(of: $0).map(\.id) } ?? [])).map(\.uuidString))
            out = folderGroups.filter { ids.contains($0.id) && !$0.trips.isEmpty }
            if out.count == 1 { out[0].title = nil }
        }
        return out
    }

    // MARK: Actions

    private func beginRename(_ trip: TripRecord) {
        renameText = trip.name
        renaming = trip
    }

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

struct NewTripRequest: Identifiable {
    let id = UUID()
    var templateID: String?
}

// MARK: - Card

/// One trip in the list: small-caps date overline, large name, the next session as a score, and the size.
private struct TripCardRow: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    let trip: TripRecord
    let onRename: (TripRecord) -> Void
    let onDelete: (TripRecord) -> Void

    var body: some View {
        let plan = trip.plan
        let _ = model.forecasts.revision
        let summary = TripsHomeModel.summary(of: plan, engine: model.engine, now: model.now())
        Button { navigation.show(.trip(trip.id)) } label: {
            card(plan, summary)
        }
        .buttonStyle(.plain)
        .contextMenu { menu }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button { togglePin() } label: {
                trip.isPinned ? Label(String(localized: "Unpin", comment: "Swipe action"), systemImage: "pin.slash")
                              : Label(String(localized: "Pin", comment: "Swipe action"), systemImage: "pin")
            }
            .tint(IterColor.accent)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) { onDelete(trip) } label: {
                Label(String(localized: "Delete", comment: "Swipe action"), systemImage: "trash")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens the trip", comment: "VoiceOver hint"))
        .task(id: summary.next?.stopID) {
            if let next = summary.next, let stop = plan.stops.first(where: { $0.id == next.stopID }) {
                model.forecasts.request(stop.spot.coordinate)
            }
        }
    }

    private func card(_ plan: TripPlan, _ summary: TripSummary) -> some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            HStack(alignment: .firstTextBaseline, spacing: IterSpace.sm) {
                overline(summary)
                Spacer(minLength: IterSpace.sm)
                if trip.isPinned {
                    OfflineStatusBadge(tripID: trip.id, style: .row)
                    Image(systemName: "pin.fill").font(IterFont.caption).foregroundStyle(IterColor.textSecondary).accessibilityHidden(true)
                }
            }
            Text(trip.name)
                .font(IterFont.titleSpot)
                .foregroundStyle(IterColor.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            status(plan, summary)
            Text(InflectedCount.string("stop", count: summary.stopCount) { AttributedString(localized: "^[\(summary.stopCount) stop](inflect: true)", comment: "Number of stops on a trip card") })
                .font(IterFont.subheadline)
                .foregroundStyle(IterColor.textSecondary)
        }
        .padding(IterSpace.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ModuleFill(), in: RoundedRectangle(cornerRadius: IterRadius.panel, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: IterRadius.panel, style: .continuous))
    }

    private func overline(_ summary: TripSummary) -> some View {
        let range = summary.dayCount > 1
            ? "\(Self.short(summary.startDay)) – \(Self.short(summary.endDay))"
            : Self.short(summary.startDay)
        return Text("\(range) · ^[\(summary.dayCount) day](inflect: true)", comment: "Trip card overline: dates and length")
            .font(.subheadline)
            .foregroundStyle(IterColor.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
    }

    /// "Tue 7 Oct" (the overline upper-cases it).
    private static func short(_ day: LocalDay) -> String {
        var style = Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated)
        style.timeZone = TimeZone(identifier: "UTC")!
        return day.noon(in: TimeZone(identifier: "UTC")!).formatted(style)
    }

    /// The next session: its score when the forecast is known, else the kind and start; or why there is none.
    @ViewBuilder private func status(_ plan: TripPlan, _ summary: TripSummary) -> some View {
        if let next = summary.next {
            HStack(alignment: .center, spacing: IterSpace.sm) {
                if let window = nextWindow(plan, next) {
                    EventScore(window: window, zone: next.timeZone, timeStyle: .start, variant: .regular,
                               isLoading: model.forecasts.isLoading(coordinate(plan, next)))
                } else {
                    EventScore(kind: next.kind, start: next.start, zone: next.timeZone, variant: .regular)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(next.spotName).font(IterFont.callout).foregroundStyle(IterColor.textPrimary).lineLimit(1)
                    Text("Next · \(TimeText.weekday(next.day))", comment: "Trip card: the next session's day")
                        .font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(LightText.nextSession(next)))
        } else if summary.stopCount == 0 {
            Label {
                Text("No stops yet. Open the trip to add the first.", comment: "Trip card with no stops")
            } icon: {
                Image(systemName: "plus.circle").foregroundStyle(IterColor.accent)
            }
            .font(IterFont.subheadline)
            .foregroundStyle(IterColor.textSecondary)
        } else {
            Label {
                Text("All sessions have passed", comment: "Trip card when every session is in the past")
            } icon: {
                Image(systemName: "checkmark.circle")
            }
            .font(IterFont.subheadline)
            .foregroundStyle(IterColor.textSecondary)
        }
    }

    private func coordinate(_ plan: TripPlan, _ next: NextSession) -> Coordinate {
        plan.stops.first(where: { $0.id == next.stopID })?.spot.coordinate ?? Coordinate(latitude: 0, longitude: 0)
    }

    private func nextWindow(_ plan: TripPlan, _ next: NextSession) -> LightWindow? {
        guard let stop = plan.stops.first(where: { $0.id == next.stopID }) else { return nil }
        let state = model.forecasts.state(for: stop.spot.coordinate)
        guard state.forecast != nil else { return nil }
        let light = model.engine.dayLight(for: stop.spot, on: next.day, forecast: state.forecast,
                                          unavailable: state.unavailableReason, now: model.now())
        return light.window(stop.session)
    }

    private func togglePin() {
        if trip.isPinned { model.offline.unpin(trip) } else { _ = model.offline.pin(trip) }
    }

    @ViewBuilder private var menu: some View {
        Button { navigation.show(.trip(trip.id)) } label: {
            Label(String(localized: "Open", comment: "Context menu"), systemImage: "arrow.up.right.square")
        }
        Button { onRename(trip) } label: {
            Label(String(localized: "Rename", comment: "Context menu"), systemImage: "pencil")
        }
        Button {
            let copy = model.store.duplicateTrip(trip, name: String(localized: "\(trip.name) copy", comment: "Name of a duplicated trip"))
            navigation.show(.trip(copy.id))
        } label: {
            Label(String(localized: "Duplicate", comment: "Context menu"), systemImage: "plus.square.on.square")
        }
        MoveToFolderMenu(kind: .trips, currentFolderID: trip.folder?.id, inNoFolder: trip.folder == nil) { folder in
            model.store.moveTrips([trip], to: folder, index: nil)
        }
        Button { togglePin() } label: {
            trip.isPinned ? Label(String(localized: "Unpin Trip", comment: "Context menu"), systemImage: "pin.slash")
                          : Label(String(localized: "Pin Trip", comment: "Context menu: keeps the trip downloaded for offline use"), systemImage: "pin")
        }
        ShareLink(item: model.store.document(for: trip), preview: SharePreview(trip.name)) {
            Label(String(localized: "Share…", comment: "Context menu"), systemImage: "square.and.arrow.up")
        }
        Divider()
        Button(role: .destructive) { onDelete(trip) } label: {
            Label(String(localized: "Delete Trip", comment: "Context menu"), systemImage: "trash")
        }
    }
}

// MARK: - Empty state

private struct EmptyTripsState: View {
    let start: (String?) -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: IterSpace.xl) {
                VStack(spacing: IterSpace.sm) {
                    Text("Plan trips around the light", comment: "Empty trips screen headline")
                        .font(IterFont.titleSpot)
                        .multilineTextAlignment(.center)
                    Text("Pick your spots and days. Iter works out when to leave so you are set up before the light arrives.",
                         comment: "Empty trips screen explanation")
                        .font(IterFont.callout)
                        .foregroundStyle(IterColor.textSecondary)
                        .multilineTextAlignment(.center)
                }
                Button { start(nil) } label: {
                    Text("New Trip", comment: "Primary button on the empty trips screen")
                        .font(IterFont.bodyEmphasis)
                        .frame(maxWidth: .infinity, minHeight: IterSize.hitTarget)
                }
                .buttonStyle(.borderedProminent)
                VStack(alignment: .leading, spacing: IterSpace.sm) {
                    Text("Or start from a template", comment: "Heading above the trip templates")
                        .font(IterFont.captionStrong)
                        .foregroundStyle(IterColor.textSecondary)
                    ForEach(TripTemplates.all) { template in
                        Button { start(template.id) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: IterSpace.xxs) {
                                    Text(template.defaultName).font(IterFont.headline).foregroundStyle(IterColor.textPrimary)
                                    Text(TimeText.dayAndStops(days: template.dayCount, stops: template.stops.count))
                                        .font(IterFont.subheadline).foregroundStyle(IterColor.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
                            }
                            .padding(IterSpace.lg)
                            .background(ModuleFill(), in: RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(IterSpace.lg)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }
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
