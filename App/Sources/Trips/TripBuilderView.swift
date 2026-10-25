import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// The trip builder: three columns. The sidebar, the route map and, in the system inspector on the trailing edge, the Trip
/// Builder panel (header card, day selector, day cards).
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
    /// The Trip Builder panel (the inspector) is shown; remembered per window.
    @SceneStorage("tripBuilderShown") private var showsBuilder = true

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
        .inspector(isPresented: $showsBuilder) { panel }
        // One toggle, at the trailing end of the toolbar as in Xcode and Mail. Without the flexible spacer the item (with
        // `.primaryAction` or `.automatic`) sat at the map's leading edge, beside the sidebar toggle.
        .toolbar {
            ToolbarSpacer(.flexible)
            ToolbarItem(placement: .automatic) { builderToggle }
        }
        .onAppear(perform: makeBuilderIfNeeded)
        .onDisappear { builder?.viewDisappeared() }
        .tripFlows()
    }

    private var builderToggle: some View {
        Button { showsBuilder.toggle() } label: {
            Label(String(localized: "Trip Builder", comment: "Toolbar button: shows or hides the trip builder panel"), systemImage: "sidebar.trailing")
        }
        .keyboardShortcut("0", modifiers: [.command, .option])
        .help(Text("Show or hide the Trip Builder", comment: "Tooltip"))
    }

    /// The Trip Builder panel, in the system inspector on the trailing edge. The design's panel is 639 pt; at 560 the map keeps
    /// 440 pt in a 1280 pt window (the sidebar takes 280).
    @ViewBuilder private var panel: some View {
        if let builder, let plan = builder.plan {
            TripPlanList(plan: plan, builder: builder, state: state, tripActions: tripActions(plan, builder),
                         changeDates: { changesDates = true }, chooseDay: { Self.chooseDay($0, in: builder, state: state) })
                .inspectorColumnWidth(min: 480, ideal: 560, max: 680)
        } else {
            Color.clear.inspectorColumnWidth(min: 480, ideal: 560, max: 680)
        }
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
        TripMapColumn(builder: builder, state: state) { Self.chooseDay($0, in: builder, state: state) }
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

    /// Share and More, the header card's two round glass buttons.
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
            .buttonStyle(GlassCircleButtonStyle(diameter: 36))
        }
    }
}

// MARK: - Map column

/// The map column: the route fills it under the toolbar. Its top inset (the toolbar) is measured here; nothing floats over
/// it any more, so it needs no leading or trailing inset.
private struct TripMapColumn: View {
    let builder: TripBuilderModel
    let state: TripViewState
    let chooseDay: (Int?) -> Void
    @State private var topInset: CGFloat = 0

    var body: some View {
        TripRouteMap(builder: builder, state: state, insets: EdgeInsets(top: topInset, leading: 0, bottom: 0, trailing: 0), chooseDay: chooseDay)
            .ignoresSafeArea(edges: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
            // As in Maps, the map runs under the toolbar with no bar or edge of its own.
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
    }
}
