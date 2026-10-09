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
///
/// This body reads no selection state: the selected stop and day live in `TripViewState`, read only by the list, the map
/// and the day strip, so a selection never re-evaluates the card, its header or this view.
private struct TripBuilderContent: View {
    let tripID: UUID
    let model: AppModel
    @Environment(AppNavigation.self) private var navigation
    @State private var builder: TripBuilderModel?
    @State private var state: TripViewState
    @State private var changesDates = false
    @State private var exports = false
    @State private var exportMessage: String?

    init(tripID: UUID, model: AppModel, initialDay: Int?) {
        self.tripID = tripID
        self.model = model
        _state = State(initialValue: TripViewState(day: initialDay))
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
        if let day = state.selectedDay {
            if made.layout.groups.indices.contains(day) { made.setFocusDay(day) } else { state.selectedDay = nil }
        }
        builder = made
        made.viewAppeared()
        if TripPerfScript.enabled {
            let state = state
            Task { @MainActor in
                await TripPerfScript.run(made, chooseDay: { Self.chooseDay($0, in: made, state: state) },
                                         select: { Self.stopSelected($0, in: made, state: state, from: .script) },
                                         moveByDrop: { id, day, before in
                                             made.moveStop(id, toDay: day, before: before)
                                             state.select(id, from: .list)
                                         })
            }
        }
    }

    // MARK: Day selection

    /// The strip and the map's switcher choose a day (nil: all days): the list scrolls to it and the map frames it.
    static func chooseDay(_ day: Int?, in builder: TripBuilderModel, state: TripViewState) {
        state.selectedDay = day
        if let day, let selected = state.selection, builder.layout.day(ofStop: selected) != day { state.select(nil, from: .strip) }
        builder.setFocusDay(day)
        if let day { state.scrollRequest = DayScrollRequest(day: day, token: (state.scrollRequest?.token ?? 0) + 1) }
    }

    /// A stop was selected (in the list or on the map): its day becomes the selected day and the map follows, by panning
    /// only if the pin is out of view. The camera is never refitted by a selection, so a click does not zoom the map away
    /// from where the user left it.
    static func stopSelected(_ id: UUID?, in builder: TripBuilderModel, state: TripViewState, from source: TripViewState.Source) {
        state.select(id, from: source)
        guard let id, let entry = builder.days.flatMap(\.stops).first(where: { $0.id == id }) else { return }
        if state.selectedDay != entry.stop.dayIndex {
            state.selectedDay = entry.stop.dayIndex
            builder.setFocusDay(entry.stop.dayIndex, refit: false)
        }
        builder.reveal(entry.stop.spot.coordinate)
        if source == .map { state.revealRow = id }
    }

    // MARK: Content

    @ViewBuilder private func builderBody(_ plan: TripPlan, _ builder: TripBuilderModel) -> some View {
        let state = self.state
        FloatingPanelLayout(placement: .centered(min: 560, max: 800, fraction: 0.62)) {
            VStack(spacing: 0) {
                TripHeader(plan: plan, builder: builder, tripActions: tripActions(plan, builder)) { changesDates = true }
                WeatherStatusBanner(status: model.weatherStatus)
                if builder.layout.groups.count > 1 {
                    TripDayStrip(builder: builder, state: state) { Self.chooseDay($0, in: builder, state: state) }
                }
                TripPlanList(builder: builder, state: state)
            }
        } map: { insets in
            TripRouteMap(builder: builder, state: state, insets: insets) { Self.chooseDay($0, in: builder, state: state) }
        }
        .navigationTitle(plan.name)
        .toolbar(removing: .title)
        .onChange(of: model.store.revision) { builder.refreshIfChanged() }
        .onChange(of: model.forecasts.revision) { builder.refreshIfChanged() }
        .background { TripSelectionFollower(builder: builder, state: state) }
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

    /// Share and More, the card's two corner buttons (round glass, in the card's top corner row as on Maps' place card).
    private func tripActions(_ plan: TripPlan, _ builder: TripBuilderModel) -> TripCornerActions {
        TripCornerActions(
            planName: plan.name,
            isLoading: builder.isLoadingLegs,
            shareItem: LazyTripDocument(tripName: plan.name, build: { [store = model.store, tripID] in
                store.trip(id: tripID).map { store.document(for: $0) }
            }),
            changeDates: { changesDates = true },
            exportTrip: { exports = true },
            duplicate: {
                if let record = self.record {
                    let copy = model.store.duplicateTrip(record, name: String(localized: "\(plan.name) copy", comment: "Name of a duplicated trip"))
                    navigation.show(.trip(copy.id))
                }
            },
            delete: {
                navigation.show(.trips)
                builder.deleteTrip()
            })
    }
}

/// The follow-up to a selection, in a view of its own so that reading the selection invalidates only this empty view:
/// a stop chosen in the list pans the map (when its pin is out of view), a pin chosen on the map scrolls its row in.
private struct TripSelectionFollower: View {
    let builder: TripBuilderModel
    let state: TripViewState

    var body: some View {
        Color.clear
            .onChange(of: state.selection) {
                // A selection that came through `stopSelected` has already done its work; this catches the ones the
                // system List and the Map make on their own through their selection bindings.
                if state.selection != nil, state.selectionSource != .script {
                    let source = state.selectionSource
                    TripBuilderContent.stopSelected(state.selection, in: builder, state: state, from: source)
                }
            }
    }
}

// MARK: - Corner actions

/// The Share and More buttons plus the drive-fetch spinner, with the closures the menu runs.
struct TripCornerActions {
    var planName: String
    var isLoading: Bool
    var shareItem: LazyTripDocument
    var changeDates: () -> Void
    var exportTrip: () -> Void
    var duplicate: () -> Void
    var delete: () -> Void
}

struct TripCardCornerButtons: View {
    let actions: TripCornerActions

    var body: some View {
        GlassEffectContainer(spacing: IterSpace.sm) {
            HStack(spacing: IterSpace.sm) {
                if actions.isLoading {
                    ProgressView().controlSize(.small)
                        .help(Text("Fetching drive times", comment: "Tooltip"))
                        .accessibilityLabel(Text("Fetching drive times", comment: "Accessibility label"))
                }
                // The document is built when the share is performed, not on every pass of this body.
                ShareLink(item: actions.shareItem, preview: SharePreview(actions.planName)) {
                    Label(String(localized: "Share", comment: "Toolbar button"), systemImage: "square.and.arrow.up")
                }
                .help(Text("Share this trip as an Iter file", comment: "Tooltip"))
                Menu {
                    Button(String(localized: "Change Dates…", comment: "Menu item"), action: actions.changeDates)
                        .keyboardShortcut("d", modifiers: [.command, .shift])
                    Button(String(localized: "Export…", comment: "Menu item"), action: actions.exportTrip)
                        .keyboardShortcut("e", modifiers: [.command, .shift])
                    Button(String(localized: "Duplicate", comment: "Menu item"), action: actions.duplicate)
                    Divider()
                    Button(String(localized: "Delete Trip", comment: "Menu item"), role: .destructive, action: actions.delete)
                } label: {
                    Label(String(localized: "Trip Actions", comment: "Toolbar menu"), systemImage: "ellipsis")
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .help(Text("Change dates, export, duplicate or delete this trip", comment: "Tooltip"))
            }
            .buttonStyle(GlassCircleButtonStyle())
        }
    }

    /// The space the buttons take, so the title never runs under them.
    static var reservedWidth: CGFloat { GlassCircleButtonStyle.size * 2 + IterSpace.sm + GlassCircleButtonStyle.inset + IterSpace.sm }
}

// MARK: - Header

/// The card's header, as Maps titles its cards: the corner buttons sit in the card's top corner (concentric with it), the
/// title runs beside them and never under them, then the dates and the trip's totals, each with its symbol.
private struct TripHeader: View {
    let plan: TripPlan
    let builder: TripBuilderModel
    let tripActions: TripCornerActions
    let changeDates: () -> Void

    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        // Formatted once per pass; the layouts below share them.
        let dates = TimeText.dateRange(from: plan.startDay, to: plan.day(plan.dayCount - 1))
        let size = TimeText.dayAndStops(days: plan.dayCount, stops: plan.stops.count)
        let driving: String? = builder.totalDriveSeconds >= 60 ? totalDriving : nil
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            TextField(String(localized: "Trip name", comment: "Placeholder"), text: $name)
                .textFieldStyle(.plain)
                .font(.largeTitle.bold())
                .lineLimit(1)
                .focused($focused)
                .onSubmit(commit)
                .onChange(of: focused) { if !focused { commit() } }
                .onChange(of: plan.name) { if !focused { name = plan.name } }
                .onAppear { name = plan.name }
                .help(Text("Click to rename", comment: "Tooltip"))
                .accessibilityLabel(Text("Trip name", comment: "Accessibility label"))
                // Beside the corner buttons, not under them.
                .padding(.trailing, TripCardCornerButtons.reservedWidth)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: IterSpace.lg) {
                    datesButton(dates)
                    summary("signpost.right.and.left", size)
                    if let driving { summary("car", driving) }
                }
                .fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: IterSpace.xs) {
                    HStack(spacing: IterSpace.lg) {
                        datesButton(dates)
                        summary("signpost.right.and.left", size)
                    }
                    if let driving { summary("car", driving) }
                }
                VStack(alignment: .leading, spacing: IterSpace.xs) {
                    datesButton(dates)
                    summary("signpost.right.and.left", size)
                    if let driving { summary("car", driving) }
                }
            }
            .font(IterFont.subheadline)
            .foregroundStyle(IterColor.textSecondary)
            OfflineStatusBadge(tripID: plan.id, style: .header)
        }
        .padding(.horizontal, IterSpace.lg)
        .padding(.top, IterSpace.lg)
        .padding(.bottom, IterSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            TripCardCornerButtons(actions: tripActions).padding(GlassCircleButtonStyle.inset)
        }
    }

    private func datesButton(_ title: String) -> some View {
        Button(action: changeDates) {
            Label(title, systemImage: "calendar")
        }
        .buttonStyle(.borderless)
        .help(Text("Change Dates…", comment: "Tooltip"))
    }

    private func summary(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).monospacedDigit()
        } icon: {
            Image(systemName: symbol).foregroundStyle(IterColor.textTertiary)
        }
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
