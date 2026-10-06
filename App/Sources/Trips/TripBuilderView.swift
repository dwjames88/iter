import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// The trip builder (plan 6.3-A): the plan as a day list with feasibility connectors on the left, the route on the right.
struct TripBuilderView: View {
    let tripID: UUID
    @Environment(AppModel.self) private var model

    var body: some View {
        TripBuilderContent(tripID: tripID, model: model)
    }
}

/// Holds the builder model. Built once per trip; `TripBuilderView` is re-created freely by the navigation stack.
private struct TripBuilderContent: View {
    let tripID: UUID
    let model: AppModel
    @Environment(AppNavigation.self) private var navigation
    @State private var builder: TripBuilderModel
    @State private var selection: UUID?
    /// The day picked in the toolbar picker; shared with the map (the selected stop's day wins there).
    @State private var chosenDay: Int?
    @State private var changesDates = false
    @State private var exports = false
    @State private var exportMessage: String?

    init(tripID: UUID, model: AppModel) {
        self.tripID = tripID
        self.model = model
        _builder = State(initialValue: TripBuilderModel(tripID: tripID, store: model.store, scheduler: model.scheduler,
                                                        drives: model.drives, forecasts: model.forecasts, now: { model.now() }))
    }

    var body: some View {
        Group {
            if let plan = builder.plan {
                builderBody(plan)
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
        }
        .onChange(of: model.store.revision) { builder.refreshIfChanged() }
        .onChange(of: model.forecasts.revision) { builder.refreshIfChanged() }
        .tripFlows()
    }

    // MARK: Content

    @ViewBuilder private func builderBody(_ plan: TripPlan) -> some View {
        ResizableSplit(storageKey: "trip", idealWidth: IterSize.listMax) {
            VStack(spacing: 0) {
                TripHeader(plan: plan, builder: builder) { changesDates = true }
                Divider()
                WeatherStatusBanner(status: model.weatherStatus)
                TripPlanList(builder: builder, selection: $selection)
            }
        } trailing: {
            TripRouteMap(builder: builder, selection: $selection, chosenDay: $chosenDay)
        }
        .background(IterColor.backgroundWindow, ignoresSafeAreaEdges: [])
        .unifiedToolbarBackground()
        .navigationTitle(plan.name)
        .toolbar(removing: .title)
        .toolbar { toolbar(plan) }
        .sheet(isPresented: $changesDates) { ChangeDatesSheet(builder: builder) }
        .fileExporter(isPresented: $exports, item: exportItem, contentTypes: [.iterTrip],
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

    private var record: TripRecord? { model.store.trip(id: tripID) }

    private var exportItem: TripDocument? { record.map { model.store.document(for: $0) } }

    /// Day numbers that have stops, and the day the map highlights (same rule as `TripRouteMap`).
    private var dayIndices: [Int] { builder.days.filter { !$0.stops.isEmpty }.map(\.index) }

    private var activeDay: Int {
        if let selection, let entry = builder.days.flatMap(\.stops).first(where: { $0.id == selection }) { return entry.stop.dayIndex }
        return chosenDay ?? dayIndices.first ?? 0
    }

    @ViewBuilder private var dayPicker: some View {
        let picker = Picker(selection: Binding(get: { activeDay }, set: { chosenDay = $0; selection = nil })) {
            ForEach(dayIndices, id: \.self) { index in
                Text("Day \(index + 1)", comment: "Route day picker segment").tag(index)
            }
        } label: {
            Text("Route day", comment: "Accessibility label of the route day picker")
        }
        .labelsHidden()
        if dayIndices.count <= 5 {
            picker.pickerStyle(.segmented)
        } else {
            picker.pickerStyle(.menu)
        }
    }

    @ToolbarContentBuilder private func toolbar(_ plan: TripPlan) -> some ToolbarContent {
        if dayIndices.count > 1 {
            ToolbarItem(placement: .principal) {
                dayPicker
                    .help(Text("Choose the day whose route is highlighted on the map", comment: "Tooltip"))
            }
        }
        if builder.isLoadingLegs {
            ToolbarItem {
                ProgressView().controlSize(.small)
                    .help(Text("Fetching drive times", comment: "Tooltip"))
                    .accessibilityLabel(Text("Fetching drive times", comment: "Accessibility label"))
            }
        }
        ToolbarItem {
            if let record {
                ShareLink(item: model.store.document(for: record), preview: SharePreview(plan.name)) {
                    Label(String(localized: "Share", comment: "Toolbar button"), systemImage: "square.and.arrow.up")
                }
                .help(Text("Share this trip as an Iter file", comment: "Tooltip"))
            }
        }
        ToolbarItem {
            Menu {
                Button(String(localized: "Change Dates…", comment: "Menu item")) { changesDates = true }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button(String(localized: "Export…", comment: "Menu item")) { exports = true }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
                Button(String(localized: "Duplicate", comment: "Menu item")) {
                    if let record {
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
        VStack(alignment: .leading, spacing: IterSpace.xs) {
            TextField(String(localized: "Trip name", comment: "Placeholder"), text: $name)
                .textFieldStyle(.plain)
                .font(IterFont.titleSpot)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { if !focused { commit() } }
                .onChange(of: plan.name) { if !focused { name = plan.name } }
                .onAppear { name = plan.name }
                .help(Text("Click to rename", comment: "Tooltip"))
                .accessibilityLabel(Text("Trip name", comment: "Accessibility label"))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: IterSpace.sm) {
                    datesButton
                    Text(verbatim: "·").accessibilityHidden(true)
                    sizeText
                    if builder.totalDriveSeconds >= 60 {
                        Text(verbatim: "·").accessibilityHidden(true)
                        drivingText
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                // Narrow column: dates and size share a line, the driving total sits under them.
                VStack(alignment: .leading, spacing: IterSpace.xxs) {
                    HStack(spacing: IterSpace.sm) {
                        datesButton
                        Text(verbatim: "·").accessibilityHidden(true)
                        sizeText
                    }
                    if builder.totalDriveSeconds >= 60 { drivingText }
                }
                VStack(alignment: .leading, spacing: IterSpace.xxs) {
                    datesButton
                    sizeText
                    if builder.totalDriveSeconds >= 60 { drivingText }
                }
            }
            .font(IterFont.subheadline)
            .foregroundStyle(IterColor.textSecondary)
        }
        .padding(IterSpace.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var datesButton: some View {
        Button(action: changeDates) {
            Label(TimeText.dateRange(from: plan.startDay, to: plan.day(plan.dayCount - 1)), systemImage: "calendar")
        }
        .buttonStyle(.borderless)
        .help(Text("Change Dates…", comment: "Tooltip"))
    }

    private var sizeText: some View { Text(TimeText.dayAndStops(days: plan.dayCount, stops: plan.stops.count)) }

    private var drivingText: some View { Text(totalDriving).monospacedDigit() }

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
