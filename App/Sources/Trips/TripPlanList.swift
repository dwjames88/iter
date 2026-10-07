import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// Where a dragged stop would land.
private enum DropSpot: Hashable {
    case before(UUID)
    case endOfDay(Int)
}

/// A request to scroll the list to a day; `token` makes a repeat request for the same day a new value.
struct DayScrollRequest: Equatable {
    var day: Int
    var token: Int
}

/// One row of the plan, flattened: each day is a header row, its banners, its timeline and an Add Stop row, drawn as one
/// rounded container; overnight boundaries sit between containers.
private struct PlanRow: Identifiable {
    enum Kind {
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

/// The plan: one container per day (header, banners, timeline, Add Stop), overnight boundaries between them. Reordering
/// and moving between days is drag and drop on rows (drop on a row to go before it, on a day header or the Add Stop row
/// to go to the end), plus the context menu's Move Up, Move Down and Move to Day for the keyboard and VoiceOver.
struct TripPlanList: View {
    @Environment(AppModel.self) private var model
    let builder: TripBuilderModel
    @Binding var selection: UUID?
    @Binding var selectedDay: Int?
    let scrollRequest: DayScrollRequest?

    @State private var dropSpot: DropSpot?
    @State private var addingToDay: Int?

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: $selection) {
                ForEach(planRows(builder.layout)) { row in
                    rowView(row)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 0, leading: IterSpace.lg, bottom: 0, trailing: IterSpace.lg))
                        .listRowBackground(background(row))
                }
                if showsScores {
                    ForecastSourceLines(app: model, coordinates: builder.days.flatMap(\.stops).map(\.stop.spot.coordinate))
                        .selectionDisabled()
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .background(IterColor.backgroundWindow, ignoresSafeAreaEdges: [])
            .onDeleteCommand(perform: removeSelected)
            .animation(.default, value: dropSpot)
            .onChange(of: scrollRequest) {
                if let request = scrollRequest { withAnimation { proxy.scrollTo("header-\(request.day)", anchor: .top) } }
            }
        }
    }

    @ViewBuilder private func background(_ row: PlanRow) -> some View {
        if let position = row.position {
            DayContainerBackground(position: position, selected: row.day == selectedDay, isHeader: isHeader(row))
        } else {
            Color.clear
        }
    }

    private func isHeader(_ row: PlanRow) -> Bool {
        if case .header = row.kind { true } else { false }
    }

    // MARK: Rows

    @ViewBuilder private func rowView(_ row: PlanRow) -> some View {
        switch row.kind {
        case .header(let group):
            DayHeaderRow(group: group)
                .selectionDisabled()
                .dropIndicator(isTargeted: dropSpot == .endOfDay(row.day))
                .onTapGesture { selectedDay = row.day }
                .stopDrop(into: row.day, before: nil, handler: drop, targeted: target)
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
                .dropIndicator(isTargeted: dropSpot == .before(drive.toStopID))
                .stopDrop(into: row.day, before: drive.toStopID, handler: drop, targeted: target)
        case .stop(let entry, let above, let below):
            StopRowView(entry: entry, builder: builder, selection: $selection, railAbove: above, railBelow: below)
                .tag(entry.id)
                .dropIndicator(isTargeted: dropSpot == .before(entry.id) && entry.previous == nil)
                .draggable(StopDragItem(tripID: builder.tripID, stopID: entry.id))
                .stopDrop(into: row.day, before: entry.id, handler: drop, targeted: target)
        case .addStop:
            addStopRow(day: row.day)
        case .overnight(let boundary):
            OvernightBoundaryRow(boundary: boundary)
                .selectionDisabled()
        }
    }

    // MARK: Add stop

    private func addStopRow(day: Int) -> some View {
        Button { addingToDay = day } label: {
            Label(String(localized: "Add Stop", comment: "Button at the end of a day"), systemImage: "plus")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(IterColor.accentText)
        .padding(.vertical, IterSpace.sm)
        .padding(.leading, TimelineMetrics.gutterWidth + TimelineMetrics.railWidth + IterSpace.sm * 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .selectionDisabled()
        .help(Text("Add a stop to this day, nearest spots first", comment: "Tooltip"))
        .popover(isPresented: Binding(get: { addingToDay == day }, set: { if !$0 { addingToDay = nil } }), arrowEdge: .bottom) {
            AddStopPopover(builder: builder, day: day)
        }
        .dropIndicator(isTargeted: dropSpot == .endOfDay(day))
        .stopDrop(into: day, before: nil, handler: drop, targeted: target)
    }

    // MARK: Drag and drop

    private func drop(_ items: [StopDragItem], day: Int, before: UUID?) -> Bool {
        guard let item = items.first, item.tripID == builder.tripID else { return false }
        dropSpot = nil
        guard item.stopID != before else { return false }
        builder.moveStop(item.stopID, toDay: day, before: before)
        selection = item.stopID
        return true
    }

    private func target(_ spot: DropSpot?, _ isTargeted: Bool) {
        if isTargeted { dropSpot = spot } else if dropSpot == spot { dropSpot = nil }
    }

    private func removeSelected() {
        guard let id = selection else { return }
        selection = nil
        builder.removeStop(id)
    }

    // MARK: Honesty

    private var showsScores: Bool {
        builder.days.contains { $0.stops.contains { $0.sessionWindow?.score != nil } }
    }
}

// MARK: - Drop plumbing

private extension View {
    func stopDrop(into day: Int, before: UUID?, handler: @escaping ([StopDragItem], Int, UUID?) -> Bool,
                  targeted: @escaping (DropSpot?, Bool) -> Void) -> some View {
        dropDestination(for: StopDragItem.self) { items, _ in
            handler(items, day, before)
        } isTargeted: { isTargeted in
            targeted(before.map { .before($0) } ?? .endOfDay(day), isTargeted)
        }
    }

    /// A line where a dropped stop will land.
    func dropIndicator(isTargeted: Bool) -> some View {
        overlay(alignment: .top) {
            if isTargeted {
                Capsule().fill(IterColor.accent).frame(height: IterStroke.thick)
            }
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
        .background(IterColor.backgroundControl, in: RoundedRectangle(cornerRadius: IterRadius.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: IterRadius.control, style: .continuous)
            .strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline))
        .accessibilityElement(children: .contain)
    }
}
