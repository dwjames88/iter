import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// Where a dragged stop would land.
enum DropSpot: Hashable {
    case before(UUID)
    case endOfDay(Int)
}

// MARK: - Drag and drop

/// The drag and drop of stops, and the one place a drop indicator is read from. Dragging across rows changes `spot` many
/// times a second; it is its own `@Observable` read only by the indicator overlays, so only the two rows whose indicator
/// flips are redrawn, never the list.
@MainActor @Observable
final class TripDropCoordinator {
    private(set) var spot: DropSpot?
    @ObservationIgnored let builder: TripBuilderModel
    @ObservationIgnored let state: TripViewState

    init(builder: TripBuilderModel, state: TripViewState) {
        self.builder = builder
        self.state = state
    }

    func target(_ spot: DropSpot, _ isTargeted: Bool) {
        if isTargeted {
            if self.spot != spot { self.spot = spot }
        } else if self.spot == spot {
            self.spot = nil
        }
    }

    func drop(_ items: [StopDragItem], day: Int, before: UUID?) -> Bool {
        spot = nil
        guard let item = items.first, item.tripID == builder.tripID, item.stopID != before else { return false }
        IterPerf.count("trip.drop")
        builder.moveStop(item.stopID, toDay: day, before: before)
        state.select(item.stopID, from: .list)
        return true
    }
}

/// The line where a dropped stop will land: an accent line with a round end, the way Reminders and Finder show an
/// insertion, across the top of the row it lands before.
private struct DropIndicator: View {
    let spot: DropSpot
    let coordinator: TripDropCoordinator

    var body: some View {
        if coordinator.spot == spot {
            HStack(spacing: 0) {
                Circle().stroke(IterColor.accent, lineWidth: IterStroke.thick).frame(width: 8, height: 8)
                Rectangle().fill(IterColor.accent).frame(height: IterStroke.thick)
            }
            .padding(.horizontal, IterSpace.md)
            .offset(y: -IterStroke.thick)
            .allowsHitTesting(false)
            .transition(.identity)
        }
    }
}

private extension View {
    /// `indicator: false` for a row whose drop line is drawn by the row above it (a stop under its drive).
    func stopDrop(into day: Int, before: UUID?, indicator: Bool = true, coordinator: TripDropCoordinator) -> some View {
        let spot: DropSpot = before.map { .before($0) } ?? .endOfDay(day)
        return dropDestination(for: StopDragItem.self) { items, _ in
            coordinator.drop(items, day: day, before: before)
        } isTargeted: { isTargeted in
            coordinator.target(spot, isTargeted)
        }
        .overlay(alignment: .top) { if indicator { DropIndicator(spot: spot, coordinator: coordinator) } }
    }
}

// MARK: - The list

/// What one List row of the panel is: the header card, the banner, the day selector, a row of the plan, or the 24 pt gap
/// between two cards (a row of its own, so a card's background never stretches over it).
private enum PanelItem: Identifiable {
    case row(TripBuilderRow)
    case gap(String)

    var id: String {
        switch self {
        case .row(let row): row.id
        case .gap(let id): id
        }
    }
}

private func panelItems(_ layout: TripDayLayout) -> [PanelItem] {
    var items: [PanelItem] = []
    for row in TripBuilderRow.make(layout) {
        items.append(.row(row))
        switch row.kind {
        case .footer, .transfer: items.append(.gap("gap-\(row.id)"))
        default: break
        }
    }
    return items
}

/// The Trip Builder panel's list: the header card, the day selector and the day cards (with the transfer cards between
/// them) as rows of one List, so everything scrolls together. Reordering and moving between days is drag and drop on rows
/// (drop on a row to go before it, on a day header or the Add Stop row to go to the end), plus the context menu's Move Up,
/// Move Down and Move to Day for the keyboard and VoiceOver.
///
/// Every plan row is an `Equatable` view of its own value, so a selection, a day change or a drop rebuilds the rows whose
/// content changed and no others. The List has no selection of its own (its highlight would paint a blue bar over the
/// card): a tap on a stop selects it and the card draws the accent outline.
struct TripPlanList: View {
    @Environment(AppModel.self) private var model
    let plan: TripPlan
    let builder: TripBuilderModel
    let state: TripViewState
    let tripActions: TripCornerActions
    let changeDates: () -> Void
    /// A day chosen on a selector card; nil returns to all days.
    let chooseDay: (Int?) -> Void
    @State private var drops: TripDropCoordinator

    init(plan: TripPlan, builder: TripBuilderModel, state: TripViewState, tripActions: TripCornerActions,
         changeDates: @escaping () -> Void, chooseDay: @escaping (Int?) -> Void) {
        self.plan = plan
        self.builder = builder
        self.state = state
        self.tripActions = tripActions
        self.changeDates = changeDates
        self.chooseDay = chooseDay
        _drops = State(initialValue: TripDropCoordinator(builder: builder, state: state))
    }

    private static let edge = BuilderMetrics.panelInset - BuilderMetrics.listMargin

    var body: some View {
        let _ = IterPerf.count("trip.listBody")
        let selection = state.selection
        ScrollViewReader { proxy in
            List {
                header
                if WeatherStatusText.message(model.weatherStatus) != nil {
                    WeatherStatusBanner(status: model.weatherStatus)
                        .plain(top: 0, bottom: BuilderMetrics.sectionGap)
                }
                if builder.layout.groups.count > 1 {
                    DaySelectorRow(builder: builder, state: state, choose: chooseDay)
                        .listRowInsets(EdgeInsets(top: 0, leading: -BuilderMetrics.listMargin, bottom: 0, trailing: -BuilderMetrics.listMargin))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                ForEach(panelItems(builder.layout)) { item in
                    switch item {
                    case .row(let row):
                        PlanRowView(row: row, isSelected: selection.map { row.id == "stop-\($0)" } ?? false,
                                    builder: builder, state: state, drops: drops)
                            .equatable()
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 0, leading: Self.edge, bottom: 0, trailing: Self.edge))
                            .listRowBackground(background(row))
                    case .gap:
                        Color.clear
                            .frame(height: BuilderMetrics.sectionGap)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }
                if showsScores {
                    ForecastSourceLines(app: model, coordinates: builder.days.flatMap(\.stops).map(\.stop.spot.coordinate))
                        .padding(.horizontal, Self.edge)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 1)
            .scrollContentBackground(.hidden)
            .background(IterColor.backgroundWindow.ignoresSafeArea())
            .task { if DebugScripts.dragScript == "stop-reorder" { await runReorderScript() } }
            .onDeleteCommand(perform: removeSelected)
            .onChange(of: state.scrollRequest) {
                if let request = state.scrollRequest { withAnimation { proxy.scrollTo("header-\(request.day)", anchor: .top) } }
            }
            .onChange(of: state.revealRow) {
                // A pin chosen on the map: bring its row into view with the least scroll, no animation to fight a drag.
                if let id = state.revealRow {
                    proxy.scrollTo("stop-\(id)")
                    state.revealRow = nil
                }
            }
        }
    }

    /// The header card, the panel's first row.
    private var header: some View {
        TripHeaderCard(title: plan.name, meta: metaItems, onRename: { builder.rename(to: $0) }) {
            TripCardCornerButtons(actions: tripActions)
        } accessory: {
            if OfflineStatusText.label(model.offline.status(for: plan.id)) != nil {
                OfflineStatusBadge(tripID: plan.id, style: .header)
            }
        }
        .plain(top: IterSpace.sm, bottom: BuilderMetrics.sectionGap)
    }

    private var metaItems: [TripMetaItem] {
        var items = [
            TripMetaItem(symbol: "calendar", text: TimeText.tripDates(from: plan.startDay, to: plan.day(plan.dayCount - 1)),
                         help: Text("Change Dates…", comment: "Tooltip"), action: changeDates),
            TripMetaItem(symbol: "point.topleft.filled.down.to.point.bottomright.curvepath",
                         text: TimeText.tripSize(days: plan.dayCount, stops: plan.stops.count)),
        ]
        if builder.totalDriveSeconds >= 60 {
            let base = String(localized: "\(TimeText.distance(builder.totalDriveMeters)) • \(TimeText.duration(builder.totalDriveSeconds))",
                              comment: "Trip total driving distance and time, e.g. 490 mi • 9 h 34 min")
            let text = builder.hasEstimatedDrive
                ? String(localized: "\(base) (estimated)", comment: "Trip driving total that includes estimated drives") : base
            items.append(TripMetaItem(symbol: "car.fill", text: text))
        }
        return items
    }

    /// `-IterDragScript stop-reorder`: the targeting and drop calls the rows' drop destinations make, one drag within a day
    /// (the last stop before the first) and one to the end of another day, with the drop line shown mid-drag.
    private func runReorderScript() async {
        await DebugScripts.pause(6)
        func order() -> String {
            builder.days.map { "d\($0.index + 1)=" + $0.stops.map { $0.stop.spot.name }.joined(separator: ",") }.joined(separator: " | ")
        }
        guard let day = builder.days.first(where: { $0.stops.count >= 2 }), let other = builder.days.first(where: { $0.index != day.index }),
              let moving = day.stops.last, let first = day.stops.first else { return }
        let item = StopDragItem(tripID: builder.tripID, stopID: moving.id)
        DebugScripts.say("reorder before: \(order())")
        await DebugScripts.capture("drag-stop-0-before")
        drops.target(.before(first.id), true)
        await DebugScripts.capture("drag-stop-1-hover-row")
        let a = drops.drop([item], day: day.index, before: first.id)
        DebugScripts.say("reorder same-day accepted=\(a): \(order())")
        await DebugScripts.capture("drag-stop-2-after-row")
        drops.target(.endOfDay(other.index), true)
        await DebugScripts.capture("drag-stop-3-hover-day")
        let b = drops.drop([item], day: other.index, before: nil)
        DebugScripts.say("reorder cross-day accepted=\(b): \(order())")
        await DebugScripts.capture("drag-stop-4-after-day")
        DebugScripts.finish()
    }

    @ViewBuilder private func background(_ row: TripBuilderRow) -> some View {
        if let position = row.position {
            DayCardBackground(position: position)
        } else {
            Color.clear
        }
    }

    private func removeSelected() {
        guard let id = state.selection else { return }
        state.select(nil, from: .list)
        builder.removeStop(id)
    }

    private var showsScores: Bool {
        builder.days.contains { $0.stops.contains { $0.sessionWindow?.score != nil } }
    }
}

private extension View {
    /// A List row with the panel's side inset, no background or separator, and the given spacing above and below.
    func plain(top: CGFloat, bottom: CGFloat) -> some View {
        self.padding(.top, top)
            .padding(.bottom, bottom)
            .listRowInsets(EdgeInsets(top: 0, leading: BuilderMetrics.panelInset - BuilderMetrics.listMargin, bottom: 0, trailing: BuilderMetrics.panelInset - BuilderMetrics.listMargin))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

/// The day selector as a list row; it reads the selected day itself, so choosing a day redraws the selector and not the list.
private struct DaySelectorRow: View {
    let builder: TripBuilderModel
    let state: TripViewState
    let choose: (Int?) -> Void

    var body: some View {
        DaySelector(items: builder.layout.daySummaries.map(DaySelectorItem.init), selectedDay: state.selectedDay, onSelect: choose)
            .padding(.bottom, BuilderMetrics.sectionGap - 16)
    }
}

/// One plan row, drawn from its value alone (`==` compares the row and whether it is the selected stop).
private struct PlanRowView: View, Equatable {
    let row: TripBuilderRow
    let isSelected: Bool
    let builder: TripBuilderModel
    let state: TripViewState
    let drops: TripDropCoordinator

    nonisolated static func == (lhs: PlanRowView, rhs: PlanRowView) -> Bool {
        lhs.row == rhs.row && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        switch row.kind {
        case .dayHeader(let group):
            DayCardHeader(dayName: TimeText.dayName(index: group.index), date: TimeText.dayHeading(group.date),
                          totals: LightText.dayTotalsLine(stops: group.stopCount, drivingSeconds: group.drivingSeconds),
                          sunrise: group.sunrise.map { LightText.sunTime(.goldenMorning, at: $0, in: group.timeZone) },
                          sunset: group.sunset.map { LightText.sunTime(.goldenEvening, at: $0, in: group.timeZone) })
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 18)
                .onTapGesture { TripBuilderChoose.day(row.day, builder: builder, state: state) }
                .stopDrop(into: row.day, before: nil, coordinator: drops)
        case .suggestion(let suggestion):
            SuggestionBanner(suggestion: suggestion, builder: builder)
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
        case .conflicts(let count):
            DayConflictRow(count: count)
                .padding(.horizontal, 16)
        case .stop(let entry):
            StopRowView(entry: entry, builder: builder, isSelected: isSelected, onRemove: remove)
                .padding(.horizontal, BuilderMetrics.bodyInset)
                .padding(.vertical, 2)
                .onTapGesture { state.select(entry.id, from: .list) }
                .draggable(StopDragItem(tripID: builder.tripID, stopID: entry.id))
                .stopDrop(into: row.day, before: entry.id, indicator: entry.previous == nil, coordinator: drops)
        case .drive(let drive):
            DriveRowAdapter(drive: drive, style: .inline)
                .padding(.horizontal, BuilderMetrics.bodyInset)
                .padding(.vertical, 2)
                .stopDrop(into: row.day, before: drive.toStopID, coordinator: drops)
        case .footer(let day, let overnight):
            DayFooter(builder: builder, day: day, overnight: overnight)
                .stopDrop(into: row.day, before: nil, coordinator: drops)
        case .transfer(let drive, let overnight):
            if let drive {
                DriveRowAdapter(drive: drive, style: .transfer(overnight))
                    .stopDrop(into: row.day, before: drive.toStopID, coordinator: drops)
            } else if let overnight {
                OvernightNote(text: ConnectorText.overnightNear(overnight.place))
                    .padding(.horizontal, 24)
            }
        }
    }

    private func remove(_ id: UUID) {
        if state.selection == id { state.select(nil, from: .list) }
        builder.removeStop(id)
    }
}

/// Feeds `DriveSegmentRow` from a drive of the plan.
private struct DriveRowAdapter: View {
    enum Style { case inline, transfer(OvernightBoundary?) }

    let drive: TripDriveItem
    let style: Style

    var body: some View {
        let leaveBy = drive.leaveBy.map { TimeText.time($0, in: drive.leaveZone) }
        let summary = drive.leg.map(ConnectorText.driveLine)
        let warning = drive.shortBySeconds.map { ScheduleText.driveDoesNotFit(shortBy: $0) }
        switch style {
        case .inline:
            DriveSegmentRow(style: .inline, leaveBy: leaveBy, summary: summary, isEstimate: drive.isEstimate, warning: warning)
        case .transfer(let overnight):
            let part = drive.leaveBy.map { DayPart.of($0, in: drive.leaveZone) } ?? .morning
            DriveSegmentRow(style: .transfer(headline: ConnectorText.transferHeadline(part), from: drive.fromName,
                                             overnight: overnight.map { ConnectorText.overnightNear($0.place) },
                                             hotels: overnight?.coordinate),
                            leaveBy: leaveBy, summary: summary, isEstimate: drive.isEstimate, warning: warning)
        }
    }
}

/// Chooses a day from a tap on its header: the same path as the selector.
@MainActor
enum TripBuilderChoose {
    static func day(_ day: Int, builder: TripBuilderModel, state: TripViewState) {
        state.selectedDay = day
        builder.setFocusDay(day)
    }
}

/// The foot of a day card: Add Stop (a system bordered button that opens the add-stop popover) and, when this card ends
/// the day you sleep after, the overnight note. The popover's state lives here, so opening it rebuilds this row and not the
/// list.
private struct DayFooter: View {
    let builder: TripBuilderModel
    let day: Int
    let overnight: OvernightBoundary?
    @State private var isAdding = false

    var body: some View {
        HStack(spacing: 8) {
            AddStopButton { isAdding = true }
                .popover(isPresented: $isAdding, arrowEdge: .bottom) { AddStopPopover(builder: builder, day: day) }
            Spacer(minLength: 8)
            if let overnight { OvernightNote(text: ConnectorText.overnightNear(overnight.place)) }
        }
        .padding(.horizontal, 12 + BuilderMetrics.bodyInset)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Light-first suggestion

/// "Reorder by light" for one day. Calm, never automatic: the plan changes only when you press Apply.
struct SuggestionBanner: View {
    let suggestion: OrderingSuggestion
    let builder: TripBuilderModel

    var body: some View {
        HStack(spacing: IterSpace.sm) {
            Image(systemName: "arrow.up.arrow.down").foregroundStyle(IterColor.textSecondary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 0) {
                Text("Reorder by light: fixes ^[\(builder.conflictsFixed(by: suggestion)) conflict](inflect: true)", comment: "Light-first suggestion; the number is how many schedule conflicts it fixes")
                    .font(IterFont.subheadline)
                    .foregroundStyle(IterColor.textPrimary)
                Text("Puts the stops in the order their light arrives.", comment: "Light-first suggestion explanation")
                    .font(IterFont.caption)
                    .foregroundStyle(IterColor.textSecondary)
            }
            Spacer(minLength: IterSpace.sm)
            Button(String(localized: "Dismiss", comment: "Button")) { builder.dismiss(suggestion) }
                .buttonStyle(.borderless)
            Button(String(localized: "Apply", comment: "Button: apply the suggested order")) { builder.apply(suggestion) }
                .buttonStyle(.bordered)
        }
        .controlSize(.small)
        .padding(IterSpace.sm)
        .background(ControlFill(), in: RoundedRectangle(cornerRadius: IterRadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: IterRadius.control, style: .continuous)
            .strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline))
        .accessibilityElement(children: .contain)
    }
}
