import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// The trip builder (plan 6.3-A): the plan as day containers with feasibility connectors on the left, the route on the right.
struct TripBuilderView: View {
    let tripID: UUID
    /// The day selected on first appearance (0-based); `-IterTripDay` for captures.
    var initialDay: Int? = AppLaunch.tripDay
    @Environment(AppModel.self) private var model

    var body: some View {
        let _ = IterPerf.count("trip.viewBody")
        TripBuilderContent(tripID: tripID, model: model, initialDay: initialDay)
    }
}

/// Holds the builder model. The model is made once, when the view first appears, never in an initializer: the
/// navigation stack re-creates `TripBuilderView` (and this view's `init`) on every state change, and a model made there
/// would run a full refresh and a drive fetch each time. `DetailView` gives the view `.id(tripID)`, so each trip
/// gets its own.
private struct TripBuilderContent: View {
    let tripID: UUID
    let model: AppModel
    @Environment(AppNavigation.self) private var navigation
    @State private var builder: TripBuilderModel?
    @State private var selection: UUID?
    /// The one selected day, shared by the overview strip, the list, the map and its switcher. nil: all days.
    @State private var selectedDay: Int?
    @State private var scrollRequest: DayScrollRequest?
    @State private var changesDates = false
    @State private var exports = false
    @State private var exportMessage: String?

    init(tripID: UUID, model: AppModel, initialDay: Int?) {
        self.tripID = tripID
        self.model = model
        _selectedDay = State(initialValue: initialDay)
    }

    var body: some View {
        Group {
            if let builder {
                if let plan = builder.plan {
                    builderBody(plan, builder)
                } else {
                    ContentUnavailableView {
                        Label(String(localized: "Trip Not Found", comment: "Empty state title"), systemImage: "map")
                    } description: {
                        Text("This trip was deleted or its creation was undone.", comment: "Empty state explanation")
                    } actions: {
                        Button(String(localized: "Back to All Trips", comment: "Button")) { navigation.show(.trips) }
                            .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                Color.clear
            }
        }
        .onAppear(perform: makeBuilderIfNeeded)
        .onDisappear { builder?.viewDisappeared() }
        .tripFlows()
    }

    private func makeBuilderIfNeeded() {
        guard builder == nil else {
            builder?.viewAppeared()
            return
        }
        let made = TripBuilderModel(tripID: tripID, store: model.store, scheduler: model.scheduler, drives: model.drives,
                                    forecasts: model.forecasts, now: { model.now() })
        if let day = selectedDay {
            if made.layout.groups.indices.contains(day) { made.setFocusDay(day) } else { selectedDay = nil }
        }
        builder = made
        made.viewAppeared()
        if TripPerfScript.enabled {
            Task { @MainActor in
                await TripPerfScript.run(made, chooseDay: { chooseDay($0, in: made) }, select: { selection = $0 })
            }
        }
    }

    // MARK: Day selection

    /// The strip and the map's switcher choose a day (nil: all days): the list scrolls to it and the map frames it.
    private func chooseDay(_ day: Int?, in builder: TripBuilderModel) {
        selectedDay = day
        if let selected = selection, builder.layout.day(ofStop: selected) != day { selection = nil }
        builder.setFocusDay(day)
        if let day { scrollRequest = DayScrollRequest(day: day, token: (scrollRequest?.token ?? 0) + 1) }
    }

    /// A stop was selected (in the list or on the map): its day becomes the selected day and the map follows.
    private func stopSelected(_ id: UUID?, in builder: TripBuilderModel) {
        guard let id, let entry = builder.days.flatMap(\.stops).first(where: { $0.id == id }) else { return }
        let requestBefore = builder.cameraRequest?.id
        if selectedDay != entry.stop.dayIndex {
            selectedDay = entry.stop.dayIndex
            builder.setFocusDay(entry.stop.dayIndex)
        }
        // A refit to the new day already frames the stop; otherwise pan to it without changing the zoom.
        if builder.cameraRequest?.id == requestBefore { builder.reveal(entry.stop.spot.coordinate) }
    }

    // MARK: Content

    @ViewBuilder private func builderBody(_ plan: TripPlan, _ builder: TripBuilderModel) -> some View {
        FloatingPanelLayout(panelWidth: IterSize.listMax) {
            VStack(spacing: 0) {
                TripHeader(plan: plan, builder: builder) { changesDates = true }
                Divider()
                WeatherStatusBanner(status: model.weatherStatus)
                if builder.layout.groups.count > 1 {
                    TripOverviewStrip(cells: builder.layout.overviewCells, selectedDay: selectedDay) { chooseDay($0, in: builder) }
                    Divider()
                }
                TripPlanList(builder: builder, selection: $selection, selectedDay: $selectedDay, scrollRequest: scrollRequest)
            }
        } map: { insets in
            TripRouteMap(builder: builder, selection: $selection, selectedDay: Binding(get: { selectedDay }, set: { chooseDay($0, in: builder) }),
                         insets: insets)
        }
        .navigationTitle(plan.name)
        .toolbar(removing: .title)
        .toolbar { toolbar(plan, builder) }
        .onChange(of: model.store.revision) { builder.refreshIfChanged() }
        .onChange(of: model.forecasts.revision) { builder.refreshIfChanged() }
        .onChange(of: selection) { stopSelected(selection, in: builder) }
        .sheet(isPresented: $changesDates) { ChangeDatesSheet(builder: builder) }
        .fileExporter(isPresented: $exports, item: exports ? exportItem : nil, contentTypes: [.iterTrip],
                      defaultFilename: TripDocument.suggestedFileName(forTripNamed: plan.name)) { result in
            if case .failure = result {
                exportMessage = String(localized: "The trip couldn't be saved to that location.", comment: "Export error")
            }
        }
        .alert(Text("Couldn't Export Trip", comment: "Alert title"), isPresented: Binding(
            get: { exportMessage != nil }, set: { if !$0 { exportMessage = nil } })) {
            Button(String(localized: "OK", comment: "Alert button")) { exportMessage = nil }
        } message: {
            if let exportMessage { Text(exportMessage) }
        }
    }

    /// Fetched only when something needs it (a menu action, an export), never while the body is built.
    private var record: TripRecord? { model.store.trip(id: tripID) }

    /// The `.iter` document, built on demand: `fileExporter` asks for it only while `exports` is true.
    private var exportItem: TripDocument? { record.map { model.store.document(for: $0) } }

    @ToolbarContentBuilder private func toolbar(_ plan: TripPlan, _ builder: TripBuilderModel) -> some ToolbarContent {
        if builder.isLoadingLegs {
            ToolbarItem {
                ProgressView().controlSize(.small)
                    .help(Text("Fetching drive times", comment: "Tooltip"))
                    .accessibilityLabel(Text("Fetching drive times", comment: "Accessibility label"))
            }
        }
        ToolbarItem {
            // The document is built when the share is performed, not on every pass of this body.
            ShareLink(item: LazyTripDocument(tripName: plan.name, build: { [store = model.store, tripID] in
                store.trip(id: tripID).map { store.document(for: $0) }
            }), preview: SharePreview(plan.name)) {
                Label(String(localized: "Share", comment: "Toolbar button"), systemImage: "square.and.arrow.up")
            }
            .help(Text("Share this trip as an Iter file", comment: "Tooltip"))
        }
        ToolbarItem {
            Menu {
                Button(String(localized: "Change Dates…", comment: "Menu item")) { changesDates = true }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button(String(localized: "Export…", comment: "Menu item")) { exports = true }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button(String(localized: "Duplicate", comment: "Menu item")) {
                    if let record = self.record {
                        let copy = model.store.duplicateTrip(record, name: String(localized: "\(plan.name) copy", comment: "Name of a duplicated trip"))
                        navigation.show(.trip(copy.id))
                    }
                }
                Divider()
                Button(String(localized: "Delete Trip", comment: "Menu item"), role: .destructive) {
                    navigation.show(.trips)
                    builder.deleteTrip()
                }
            } label: {
                Label(String(localized: "Trip Actions", comment: "Toolbar menu"), systemImage: "ellipsis.circle")
            }
            .help(Text("Change dates, export, duplicate or delete this trip", comment: "Tooltip"))
        }
    }
}

// MARK: - Header

/// The trip's name (edit in place), dates and totals.
private struct TripHeader: View {
    let plan: TripPlan
    let builder: TripBuilderModel
    let changeDates: () -> Void

    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        // Formatted once per pass; the three layouts below share them.
        let dates = TimeText.dateRange(from: plan.startDay, to: plan.day(plan.dayCount - 1))
        let size = TimeText.dayAndStops(days: plan.dayCount, stops: plan.stops.count)
        let driving: String? = builder.totalDriveSeconds >= 60 ? totalDriving : nil
        VStack(alignment: .leading, spacing: IterSpace.xs) {
            TextField(String(localized: "Trip name", comment: "Placeholder"), text: $name)
                .textFieldStyle(.plain)
                .font(.largeTitle.bold())
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { if !focused { commit() } }
                .onChange(of: plan.name) { if !focused { name = plan.name } }
                .onAppear { name = plan.name }
                .help(Text("Click to rename", comment: "Tooltip"))
                .accessibilityLabel(Text("Trip name", comment: "Accessibility label"))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: IterSpace.sm) {
                    datesButton(dates)
                    Text(verbatim: "·").accessibilityHidden(true)
                    Text(size)
                    if let driving {
                        Text(verbatim: "·").accessibilityHidden(true)
                        Text(driving).monospacedDigit()
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                // Narrow column: dates and size share a line, the driving total sits under them.
                VStack(alignment: .leading, spacing: IterSpace.xxs) {
                    HStack(spacing: IterSpace.sm) {
                        datesButton(dates)
                        Text(verbatim: "·").accessibilityHidden(true)
                        Text(size)
                    }
                    if let driving { Text(driving).monospacedDigit() }
                }
                VStack(alignment: .leading, spacing: IterSpace.xxs) {
                    datesButton(dates)
                    Text(size)
                    if let driving { Text(driving).monospacedDigit() }
                }
            }
            .font(IterFont.subheadline)
            .foregroundStyle(IterColor.textSecondary)
            OfflineStatusBadge(tripID: plan.id, style: .header)
        }
        .padding(IterSpace.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func datesButton(_ title: String) -> some View {
        Button(action: changeDates) {
            Label(title, systemImage: "calendar")
        }
        .buttonStyle(.borderless)
        .help(Text("Change Dates…", comment: "Tooltip"))
    }

    private var totalDriving: String {
        let base = String(localized: "\(TimeText.distance(builder.totalDriveMeters)) · \(TimeText.duration(builder.totalDriveSeconds)) driving",
                          comment: "Trip total driving distance and time")
        return builder.hasEstimatedDrive ? String(localized: "\(base) (estimated)", comment: "Trip driving total that includes estimated drives") : base
    }

    private func commit() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { name = plan.name } else if trimmed != plan.name { builder.rename(to: trimmed) }
    }
}
