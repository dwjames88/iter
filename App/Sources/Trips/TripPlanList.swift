import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// Where a dragged stop would land.
private enum DropSpot: Hashable {
    case before(UUID)
    case endOfDay(Int)
}

/// The plan: one section per day, stops with the drive connectors between them. Reordering and moving between days
/// is drag and drop on rows (drop on a row to go before it, on a day header or the Add Stop row to go to the end),
/// plus the context menu's Move Up, Move Down and Move to Day for the keyboard and VoiceOver.
struct TripPlanList: View {
    @Environment(AppModel.self) private var model
    let builder: TripBuilderModel
    @Binding var selection: UUID?

    @State private var dropSpot: DropSpot?
    @State private var addingToDay: Int?

    var body: some View {
        List(selection: $selection) {
            if let reason = globalNoForecastReason {
                Text(LightText.noForecastReason(reason))
                    .font(IterFont.caption)
                    .foregroundStyle(IterColor.textSecondary)
                    .selectionDisabled()
                    .listRowSeparator(.hidden)
            }
            ForEach(builder.days) { day in
                Section {
                    if let suggestion = builder.suggestion(forDay: day.index) {
                        SuggestionBanner(suggestion: suggestion, builder: builder)
                            .selectionDisabled()
                            .listRowSeparator(.hidden)
                    }
                    ForEach(day.stops) { entry in
                        if entry.previous != nil {
                            ConnectorRowView(entry: entry)
                                .selectionDisabled()
                                .listRowSeparator(.hidden)
                                .dropIndicator(isTargeted: dropSpot == .before(entry.id))
                                .stopDrop(into: day.index, before: entry.id, handler: drop, targeted: target)
                        }
                        StopRowView(entry: entry, builder: builder, selection: $selection)
                            .tag(entry.id)
                            .dropIndicator(isTargeted: dropSpot == .before(entry.id) && entry.previous == nil)
                            .draggable(StopDragItem(tripID: builder.tripID, stopID: entry.id))
                            .stopDrop(into: day.index, before: entry.id, handler: drop, targeted: target)
                    }
                    addStopRow(day)
                } header: {
                    DayHeader(day: day)
                        .stopDrop(into: day.index, before: nil, handler: drop, targeted: target)
                }
            }
            if showsScores {
                WeatherAttributionView()
                    .selectionDisabled()
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.inset)
        .onDeleteCommand(perform: removeSelected)
        .animation(.default, value: dropSpot)
    }

    // MARK: Add stop

    private func addStopRow(_ day: TripDay) -> some View {
        Button { addingToDay = day.index } label: {
            Label(String(localized: "Add Stop", comment: "Button at the end of a day"), systemImage: "plus")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(IterColor.accent)
        .padding(.vertical, IterSpace.xs)
        .selectionDisabled()
        .listRowSeparator(.hidden)
        .help(Text("Add a stop to this day, nearest spots first", comment: "Tooltip"))
        .popover(isPresented: Binding(get: { addingToDay == day.index }, set: { if !$0 { addingToDay = nil } }), arrowEdge: .bottom) {
            AddStopPopover(builder: builder, day: day.index)
        }
        .dropIndicator(isTargeted: dropSpot == .endOfDay(day.index))
        .stopDrop(into: day.index, before: nil, handler: drop, targeted: target)
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

    /// One calm line when no stop can be scored for a reason that applies to every stop (weather off, offline),
    /// instead of repeating it on every row.
    private var globalNoForecastReason: ForecastUnavailableReason? {
        let reasons = builder.days.flatMap(\.stops).compactMap { entry -> ForecastUnavailableReason? in
            if case .noForecast(let reason)? = entry.sessionWindow?.assessment { return reason }
            return nil
        }
        guard let first = reasons.first, reasons.count == builder.days.flatMap(\.stops).count else { return nil }
        switch first {
        case .weatherServiceNotEnabled, .serviceFailed: return first
        default: return nil
        }
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

// MARK: - Day header

struct DayHeader: View {
    let day: TripDay

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: IterSpace.md) {
            VStack(alignment: .leading, spacing: IterSpace.xxs) {
                Text(TimeText.tripDay(index: day.index, day: day.day))
                    .font(IterFont.headline)
                    .foregroundStyle(IterColor.textPrimary)
                if let frame = LightText.dayFrame(sunrise: day.sunrise, sunset: day.sunset, in: day.timeZone) {
                    Label {
                        Text(frame).monospacedDigit()
                    } icon: {
                        Image(systemName: "sun.horizon")
                    }
                    .font(IterFont.caption)
                    .foregroundStyle(IterColor.textSecondary)
                }
            }
            Spacer(minLength: IterSpace.sm)
            Text(LightText.dayTotals(stops: day.stops.count, drivingSeconds: day.drivingSeconds))
                .font(IterFont.caption)
                .foregroundStyle(IterColor.textSecondary)
                .monospacedDigit()
        }
        .textCase(nil)
        .padding(.vertical, IterSpace.xs)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
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
