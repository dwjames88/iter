import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// Where a dragged stop would land.
enum DropSpot: Hashable {
    case before(UUID)
    case endOfDay(Int)
}

/// One row of the plan, flattened: each day is a header row, its banners, its timeline and an Add Stop row, drawn as one
/// rounded container; overnight boundaries sit between containers. Equatable, so a row whose content is unchanged is not
/// rebuilt when another row's is.
private struct PlanRow: Identifiable, Equatable {
    enum Kind: Equatable {
        case header(TripDayGroup)
        case suggestion(OrderingSuggestion)
        case conflicts(Int)
        case drive(TripDriveItem, isDriveIn: Bool, above: RailTone?, below: RailTone?)
        case stop(TripStopEntry, above: RailTone?, below: RailTone?)
        case addStop
        case overnight(OvernightBoundary)
    }

    var id: String
    var day: Int
    var kind: Kind
    /// nil for rows outside a container.
    var position: ContainerPosition?
}

private func planRows(_ layout: TripDayLayout) -> [PlanRow] {
    var rows: [PlanRow] = []
    for group in layout.groups {
        let day = group.index
        var inside: [PlanRow] = [PlanRow(id: "header-\(day)", day: day, kind: .header(group))]
        if let suggestion = group.suggestion {
            inside.append(PlanRow(id: "suggestion-\(day)", day: day, kind: .suggestion(suggestion)))
        }
        if group.hasConflict {
            inside.append(PlanRow(id: "conflicts-\(day)", day: day, kind: .conflicts(group.conflictCount)))
        }
        for (index, item) in group.items.enumerated() {
            let before = index > 0 ? group.items[index - 1] : nil
            let after = index + 1 < group.items.count ? group.items[index + 1] : nil
            func tone(_ item: TripTimelineItem?) -> RailTone? {
                switch item {
                case .drive(let drive), .driveIn(let drive): RailTone(drive)
                default: nil
                }
            }
            switch item {
            case .driveIn(let drive):
                inside.append(PlanRow(id: item.id, day: day, kind: .drive(drive, isDriveIn: true, above: nil, below: RailTone(drive))))
            case .drive(let drive):
                inside.append(PlanRow(id: item.id, day: day, kind: .drive(drive, isDriveIn: false, above: RailTone(drive), below: RailTone(drive))))
            case .stop(let entry):
                inside.append(PlanRow(id: item.id, day: day, kind: .stop(entry, above: tone(before), below: tone(after))))
            case .addStop:
                inside.append(PlanRow(id: item.id, day: day, kind: .addStop))
            }
        }
        for (index, var row) in inside.enumerated() {
            row.position = inside.count == 1 ? .only : index == 0 ? .first : index == inside.count - 1 ? .last : .middle
            rows.append(row)
        }
        if let boundary = group.overnightAfter {
            rows.append(PlanRow(id: "overnight-\(day)", day: day, kind: .overnight(boundary)))
        }
    }
    return rows
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

/// The plan: one container per day (header, banners, timeline, Add Stop), overnight boundaries between them. Reordering
/// and moving between days is drag and drop on rows (drop on a row to go before it, on a day header or the Add Stop row
/// to go to the end), plus the context menu's Move Up, Move Down and Move to Day for the keyboard and VoiceOver.
///
/// Every row is an `Equatable` view of its own value, so a selection, a day change or a drop rebuilds the rows whose
/// content changed and no others; the system List draws the selection highlight itself.
struct TripPlanList: View {
    @Environment(AppModel.self) private var model
    let builder: TripBuilderModel
    let state: TripViewState
    @State private var drops: TripDropCoordinator

    init(builder: TripBuilderModel, state: TripViewState) {
        self.builder = builder
        self.state = state
        _drops = State(initialValue: TripDropCoordinator(builder: builder, state: state))
    }

    var body: some View {
        let _ = IterPerf.count("trip.listBody")
        let selectedDay = state.selectedDay
        ScrollViewReader { proxy in
            List(selection: Binding(get: { state.selection }, set: { state.select($0, from: .list) })) {
                ForEach(planRows(builder.layout)) { row in
                    PlanRowView(row: row, daySelected: row.day == selectedDay, builder: builder, state: state, drops: drops)
                        .equatable()
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: IterSpace.lg, bottom: 0, trailing: IterSpace.lg))
                        .listRowBackground(background(row, selectedDay: selectedDay))
                }
                if showsScores {
                    ForecastSourceLines(app: model, coordinates: builder.days.flatMap(\.stops).map(\.stop.spot.coordinate))
                        .selectionDisabled()
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
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

    @ViewBuilder private func background(_ row: PlanRow, selectedDay: Int?) -> some View {
        if let position = row.position {
            DayContainerBackground(position: position, selected: row.day == selectedDay, isHeader: isHeader(row))
        } else {
            Color.clear
        }
    }

    private func isHeader(_ row: PlanRow) -> Bool {
        if case .header = row.kind { true } else { false }
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

/// One row, drawn from its value alone (`==` compares the row and whether its day is the selected one).
private struct PlanRowView: View, Equatable {
    let row: PlanRow
    let daySelected: Bool
    let builder: TripBuilderModel
    let state: TripViewState
    let drops: TripDropCoordinator

    nonisolated static func == (lhs: PlanRowView, rhs: PlanRowView) -> Bool {
        lhs.row == rhs.row && lhs.daySelected == rhs.daySelected
    }

    var body: some View {
        switch row.kind {
        case .header(let group):
            DayHeaderRow(group: group, isSelected: daySelected)
                .selectionDisabled()
                .onTapGesture { TripBuilderChoose.day(row.day, builder: builder, state: state) }
                .stopDrop(into: row.day, before: nil, coordinator: drops)
        case .suggestion(let suggestion):
            SuggestionBanner(suggestion: suggestion, builder: builder)
                .padding(.vertical, IterSpace.xs)
                .selectionDisabled()
        case .conflicts(let count):
            DayConflictRow(count: count)
                .selectionDisabled()
        case .drive(let drive, let isDriveIn, let above, let below):
            DriveRowView(drive: drive, isDriveIn: isDriveIn, above: above, below: below)
                .selectionDisabled()
                .stopDrop(into: row.day, before: drive.toStopID, coordinator: drops)
        case .stop(let entry, let above, let below):
            StopRowView(entry: entry, builder: builder, onRemove: remove, railAbove: above, railBelow: below)
                .tag(entry.id)
                .draggable(StopDragItem(tripID: builder.tripID, stopID: entry.id))
                .stopDrop(into: row.day, before: entry.id, indicator: entry.previous == nil, coordinator: drops)
        case .addStop:
            AddStopRow(builder: builder, day: row.day)
                .selectionDisabled()
                .stopDrop(into: row.day, before: nil, coordinator: drops)
        case .overnight(let boundary):
            OvernightBoundaryRow(boundary: boundary)
                .selectionDisabled()
        }
    }

    private func remove(_ id: UUID) {
        if state.selection == id { state.select(nil, from: .list) }
        builder.removeStop(id)
    }
}

/// Chooses a day from a tap on its header: the same path as the strip.
@MainActor
enum TripBuilderChoose {
    static func day(_ day: Int, builder: TripBuilderModel, state: TripViewState) {
        state.selectedDay = day
        builder.setFocusDay(day)
    }
}

/// "Add Stop" at the foot of a day: a system bordered button that opens the add-stop popover. The popover's state lives
/// here, so opening it rebuilds this row and not the list.
private struct AddStopRow: View {
    let builder: TripBuilderModel
    let day: Int
    @State private var isAdding = false

    var body: some View {
        Button { isAdding = true } label: {
            Label(String(localized: "Add Stop", comment: "Button at the end of a day"), systemImage: "plus")
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .padding(.vertical, IterSpace.md)
        .padding(.leading, TimelineMetrics.gutterWidth + TimelineMetrics.railWidth + IterSpace.sm * 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(Text("Add a stop to this day, nearest spots first", comment: "Tooltip"))
        .popover(isPresented: $isAdding, arrowEdge: .bottom) {
            AddStopPopover(builder: builder, day: day)
        }
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
