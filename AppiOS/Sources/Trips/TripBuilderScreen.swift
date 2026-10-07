import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// The trip builder for iPhone (pushed) and iPad (detail). The model is made once per view life (never in an initializer:
/// the navigation stack re-creates the view struct on every state change), as on the Mac. OWNER: Trips.
struct TripBuilderScreen: View {
    let tripID: UUID
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    @State private var builder: TripBuilderModel?

    var body: some View {
        Group {
            if let builder {
                if let plan = builder.plan {
                    TripBuilderContent(plan: plan, builder: builder)
                } else {
                    ContentUnavailableView {
                        Label(String(localized: "Trip not found", comment: "Empty state title"), systemImage: "map")
                    } description: {
                        Text("This trip was deleted or its creation was undone.", comment: "Empty state explanation")
                    } actions: {
                        Button(String(localized: "Back to all trips", comment: "Button")) { navigation.show(.trips) }
                            .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                Color.clear
            }
        }
        .background(IterColor.backgroundWindow, ignoresSafeAreaEdges: .all)
        .onAppear {
            guard builder == nil else { return }
            builder = TripBuilderModel(tripID: tripID, store: model.store, scheduler: model.scheduler, drives: model.drives,
                                       forecasts: model.forecasts, now: { model.now() })
        }
    }
}

private struct TripBuilderContent: View {
    let plan: TripPlan
    let builder: TripBuilderModel
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var selectedDay: Int?
    @State private var scrollRequest: DayScrollTarget?
    @State private var editMode: EditMode = AppLaunch.editStops ? .active : .inactive
    @State private var mapCollapsed = AppLaunch.routeCollapsed
    @State private var addingToDay: Int?
    @State private var changesDates = false
    @State private var renames = false
    @State private var renameText = ""
    @State private var confirmsDelete = false
    @State private var didLaunch = false

    var body: some View {
        let _ = model.offline.status(for: plan.id)
        Group {
            if sizeClass == .regular {
                HStack(spacing: 0) {
                    planColumn(showsMap: false)
                        .frame(maxWidth: 480)
                    Divider()
                    TripRouteMapView(builder: builder, selectedDay: $selectedDay, onSelectStop: scrollToStop)
                        .frame(maxWidth: .infinity)
                }
            } else {
                planColumn(showsMap: true)
            }
        }
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .environment(\.editMode, $editMode)
        .onChange(of: model.store.revision) { builder.refreshIfChanged() }
        .onChange(of: model.forecasts.revision) { builder.refreshIfChanged() }
        .sheet(isPresented: $changesDates) { ChangeDatesScreenSheet(builder: builder).presentationDetents([.medium, .large]) }
        .sheet(item: Binding(get: { addingToDay.map(AddStopTarget.init) }, set: { addingToDay = $0?.day })) { target in
            AddStopSheet(builder: builder, day: target.day)
                .presentationDetents([.medium, .large])
        }
        .alert(String(localized: "Rename trip", comment: "Alert title"), isPresented: $renames) {
            TextField(String(localized: "Trip name", comment: "Placeholder"), text: $renameText)
            Button(String(localized: "Cancel", comment: "Button"), role: .cancel) {}
            Button(String(localized: "Rename", comment: "Button")) { builder.rename(to: renameText) }
        }
        .confirmationDialog(String(localized: "Delete this trip?", comment: "Confirmation title"), isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button(String(localized: "Delete Trip", comment: "Button"), role: .destructive) {
                navigation.show(.trips)
                builder.deleteTrip()
            }
        } message: {
            Text("You can undo this right after.", comment: "Confirmation message")
        }
        .onAppear(perform: applyLaunch)
    }

    // MARK: Layout

    private func planColumn(showsMap: Bool) -> some View {
        VStack(spacing: 0) {
            WeatherStatusBanner(status: model.weatherStatus)
            TripSummaryBar(plan: plan, builder: builder, collapsible: showsMap, collapsed: $mapCollapsed)
            if showsMap, !mapCollapsed {
                TripRouteMapView(builder: builder, selectedDay: $selectedDay, onSelectStop: scrollToStop)
                    .frame(height: 220)
                    .transition(.opacity)
            }
            if builder.layout.groups.count > 1 {
                TripOverviewStrip(cells: builder.layout.overviewCells, selectedDay: selectedDay) { chooseDay($0) }
            }
            TripDayList(plan: plan, builder: builder, selectedDay: $selectedDay, scrollTarget: scrollRequest) { addingToDay = $0 }
        }
        .animation(.snappy, value: mapCollapsed)
    }

    // MARK: Day selection

    private func chooseDay(_ day: Int?) {
        selectedDay = day
        builder.setFocusDay(day)
        if let day { scrollRequest = DayScrollTarget(id: "header-\(day)", token: (scrollRequest?.token ?? 0) + 1) }
    }

    private func scrollToStop(_ id: UUID) {
        guard let day = builder.layout.day(ofStop: id) else { return }
        if selectedDay != day { selectedDay = day; builder.setFocusDay(day) }
        scrollRequest = DayScrollTarget(id: "stop-\(id)", token: (scrollRequest?.token ?? 0) + 1)
    }

    private func applyLaunch() {
        guard !didLaunch else { return }
        didLaunch = true
        if let day = AppLaunch.tripDay, builder.layout.groups.indices.contains(day) {
            selectedDay = day
            builder.setFocusDay(day)
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                scrollRequest = DayScrollTarget(id: "header-\(day)", token: 1)
            }
        }
        if AppLaunch.addStop { addingToDay = selectedDay ?? 0 }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if builder.isLoadingLegs {
            ToolbarItem(placement: .topBarTrailing) {
                ProgressView().accessibilityLabel(Text("Fetching drive times", comment: "Accessibility label"))
            }
        }
        ToolbarItem(placement: .topBarTrailing) { EditButton() }
        ToolbarItem(placement: .topBarTrailing) {
            if let record = model.store.trip(id: plan.id) {
                ShareLink(item: model.store.document(for: record), preview: SharePreview(plan.name)) {
                    Label(String(localized: "Share", comment: "Toolbar button"), systemImage: "square.and.arrow.up")
                }
            }
        }
        ToolbarItem(placement: .topBarTrailing) { actionsMenu }
    }

    private var actionsMenu: some View {
        let record = model.store.trip(id: plan.id)
        let status = OfflineStatusText.label(model.offline.status(for: plan.id))
        return Menu {
            if let record {
                if record.isPinned {
                    Button { model.offline.unpin(record) } label: {
                        Label(String(localized: "Unpin trip", comment: "Menu item"), systemImage: "pin.slash")
                    }
                    if let status { Text(status) }
                } else {
                    Button { _ = model.offline.pin(record) } label: {
                        Label(String(localized: "Pin for offline", comment: "Menu item: keeps the trip downloaded"), systemImage: "pin")
                    }
                }
            }
            Divider()
            Button { changesDates = true } label: {
                Label(String(localized: "Change dates…", comment: "Menu item"), systemImage: "calendar")
            }
            Button { renameText = plan.name; renames = true } label: {
                Label(String(localized: "Rename", comment: "Menu item"), systemImage: "pencil")
            }
            Button {
                if let record {
                    let copy = model.store.duplicateTrip(record, name: String(localized: "\(plan.name) copy", comment: "Name of a duplicated trip"))
                    navigation.show(.trip(copy.id))
                }
            } label: {
                Label(String(localized: "Duplicate", comment: "Menu item"), systemImage: "plus.square.on.square")
            }
            Divider()
            Button(role: .destructive) { confirmsDelete = true } label: {
                Label(String(localized: "Delete trip", comment: "Menu item"), systemImage: "trash")
            }
        } label: {
            Label(String(localized: "Trip actions", comment: "Toolbar menu"), systemImage: "ellipsis")
        }
    }
}

struct DayScrollTarget: Equatable {
    var id: String
    var token: Int
}

private struct AddStopTarget: Identifiable {
    var day: Int
    var id: Int { day }
}

// MARK: - Summary bar

/// Dates, size and driving total, the offline badge, and (on iPhone) the chevron that collapses the route map.
private struct TripSummaryBar: View {
    let plan: TripPlan
    let builder: TripBuilderModel
    let collapsible: Bool
    @Binding var collapsed: Bool

    var body: some View {
        HStack(spacing: IterSpace.sm) {
            VStack(alignment: .leading, spacing: IterSpace.xxs) {
                Text(TimeText.dateRange(from: plan.startDay, to: plan.day(plan.dayCount - 1)))
                    .font(IterFont.captionStrong)
                    .textCase(.uppercase)
                    .tracking(0.6)
                    .foregroundStyle(IterColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(summary)
                    .font(IterFont.subheadline)
                    .foregroundStyle(IterColor.textPrimary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: IterSpace.sm)
            OfflineStatusBadge(tripID: plan.id, style: .row)
            if collapsible {
                Button { collapsed.toggle() } label: {
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(collapsed ? 180 : 0))
                        .font(IterFont.bodyEmphasis)
                        .foregroundStyle(IterColor.textSecondary)
                        .frame(width: IterSize.hitTarget, height: IterSize.hitTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(collapsed ? Text("Show route map", comment: "Accessibility label") : Text("Hide route map", comment: "Accessibility label"))
            }
        }
        .padding(.leading, IterSpace.lg)
        .padding(.trailing, collapsible ? IterSpace.xs : IterSpace.lg)
        .padding(.vertical, IterSpace.xs)
        .frame(minHeight: IterSize.hitTarget + IterSpace.sm)
        .background(IterColor.backgroundWindow)
    }

    private var summary: String {
        let size = TimeText.dayAndStops(days: plan.dayCount, stops: plan.stops.count)
        guard builder.totalDriveSeconds >= 60 else { return size }
        return "\(size) · \(TimeText.duration(builder.totalDriveSeconds)) \(String(localized: "driving", comment: "Trip summary: after a drive time"))"
    }
}
