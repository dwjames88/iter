import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// The day-by-day plan, built from the same components as the Mac's Trip Builder: the header card and the day selector
/// scroll with the list, each day is a card (`DayCardHeader`, `StopCard`s, inline `DriveSegmentRow`s and a footer with
/// `AddStopButton` and the overnight note) drawn as slices of one rounded fill, and a transfer card sits between two days.
/// Stops reorder with the system controls (`EditButton`, `.onMove`) and delete with `.onDelete`; the model rows come
/// from `TripBuilderRow.make`.
struct TripDayList: View {
    @Environment(AppModel.self) private var model
    let plan: TripPlan
    let builder: TripBuilderModel
    let selectedDay: Int?
    let scrollTarget: DayScrollTarget?
    /// Collapses the route map above the list (iPhone and narrow iPad); nil when the map is not part of this column.
    var mapCollapsed: Binding<Bool>?
    let changeDates: () -> Void
    let chooseDay: (Int?) -> Void
    let addStop: (Int) -> Void

    private static let edge = BuilderMetrics.panelInset

    /// One List row: a row of the plan, or the 24 pt gap between two cards (a row of its own, so a card's fill never
    /// stretches over it).
    private enum Item: Identifiable {
        case row(TripBuilderRow)
        case gap(String)

        var id: String {
            switch self {
            case .row(let row): row.id
            case .gap(let id): id
            }
        }

        var stopID: UUID? {
            if case .row(let row) = self, case .stop(let entry) = row.kind { return entry.id }
            return nil
        }
    }

    private var items: [Item] {
        var items: [Item] = []
        for row in TripBuilderRow.make(builder.layout) {
            items.append(.row(row))
            switch row.kind {
            case .footer, .transfer: items.append(.gap("gap-\(row.id)"))
            default: break
            }
        }
        return items
    }

    var body: some View {
        let items = items
        ScrollViewReader { proxy in
            List {
                TripHeaderCard(title: plan.name, meta: TripMetaItem.items(plan: plan, builder: builder, changeDates: changeDates),
                               onRename: { builder.rename(to: $0) }, actions: { EmptyView() }) {
                    VStack(alignment: .leading, spacing: IterSpace.sm) {
                        if OfflineStatusText.label(model.offline.status(for: plan.id)) != nil {
                            OfflineStatusBadge(tripID: plan.id, style: .header)
                        }
                        if let mapCollapsed { mapToggle(mapCollapsed) }
                    }
                }
                .padding(.top, IterSpace.sm)
                .padding(.bottom, BuilderMetrics.sectionGap)
                .plainRow(inset: Self.edge)
                if builder.layout.groups.count > 1 {
                    DaySelector(items: builder.layout.daySummaries.map(DaySelectorItem.init), selectedDay: selectedDay, onSelect: chooseDay)
                        .padding(.bottom, BuilderMetrics.sectionGap - 16)
                        .plainRow(inset: 0)
                }
                ForEach(items) { item in
                    switch item {
                    case .row(let row):
                        rowView(row)
                            .id(row.id)
                            .listRowInsets(EdgeInsets(top: 0, leading: Self.edge, bottom: 0, trailing: Self.edge))
                            .listRowSeparator(.hidden)
                            .listRowBackground(background(row))
                            .moveDisabled(item.stopID == nil)
                            .deleteDisabled(item.stopID == nil)
                    case .gap:
                        Color.clear
                            .frame(height: BuilderMetrics.sectionGap)
                            .listRowInsets(EdgeInsets())
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .moveDisabled(true)
                            .deleteDisabled(true)
                    }
                }
                .onMove { move(items, from: $0, to: $1) }
                .onDelete { offsets in offsets.compactMap { items[$0].stopID }.forEach(builder.removeStop) }
                if builder.days.contains(where: { $0.stops.contains { $0.sessionWindow?.score != nil } }) {
                    ForecastSourceLines(app: model, coordinates: builder.days.flatMap(\.stops).map(\.stop.spot.coordinate))
                        .padding(.horizontal, Self.edge)
                        .plainRow(inset: 0)
                }
            }
            .listStyle(.plain)
            .environment(\.defaultMinListRowHeight, 1)
            .scrollContentBackground(.hidden)
            .screenBackground()
            .onChange(of: scrollTarget) {
                if let target = scrollTarget { withAnimation { proxy.scrollTo(target.id, anchor: .top) } }
            }
        }
    }

    private func mapToggle(_ collapsed: Binding<Bool>) -> some View {
        Button { collapsed.wrappedValue.toggle() } label: {
            Label(collapsed.wrappedValue ? String(localized: "Show Route Map", comment: "Button")
                                         : String(localized: "Hide Route Map", comment: "Button"),
                  systemImage: collapsed.wrappedValue ? "map" : "chevron.up")
                .font(BuilderType.control)
                .frame(minHeight: IterSize.hitTarget - 12)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
    }

    @ViewBuilder private func background(_ row: TripBuilderRow) -> some View {
        if let position = row.position { DayCardBackground(position: position) } else { Color.clear }
    }

    // MARK: Rows

    @ViewBuilder private func rowView(_ row: TripBuilderRow) -> some View {
        switch row.kind {
        case .dayHeader(let group):
            Button { chooseDay(group.index) } label: {
                DayCardHeader(dayName: TimeText.dayName(index: group.index), date: TimeText.dayHeading(group.date),
                              totals: LightText.dayTotalsLine(stops: group.stopCount, drivingSeconds: group.drivingSeconds),
                              sunrise: group.sunrise.map { LightText.sunTime(.goldenMorning, at: $0, in: group.timeZone) },
                              sunset: group.sunset.map { LightText.sunTime(.goldenEvening, at: $0, in: group.timeZone) })
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isHeader)
        case .suggestion(let suggestion):
            SuggestionCard(suggestion: suggestion, builder: builder)
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
        case .conflicts(let count):
            DayConflictRow(count: count)
                .padding(.horizontal, 16)
        case .stop(let entry):
            StopRowView(entry: entry, builder: builder, onRemove: { builder.removeStop($0) })
                .padding(.horizontal, BuilderMetrics.bodyInset)
                .padding(.vertical, 2)
        case .drive(let drive):
            DriveRowAdapter(drive: drive, style: .inline)
                .padding(.horizontal, BuilderMetrics.bodyInset)
                .padding(.vertical, 2)
        case .footer(let day, let overnight):
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { footerParts(day, overnight) }
                VStack(alignment: .leading, spacing: 8) { footerParts(day, overnight) }
            }
            .padding(.horizontal, 12 + BuilderMetrics.bodyInset)
            .padding(.top, 14)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .transfer(let drive, let overnight):
            if let drive {
                DriveRowAdapter(drive: drive, style: .transfer(overnight))
            } else if let overnight {
                OvernightNote(text: ConnectorText.overnightNear(overnight.place))
                    .padding(.horizontal, 24)
            }
        }
    }

    @ViewBuilder private func footerParts(_ day: Int, _ overnight: OvernightBoundary?) -> some View {
        AddStopButton { addStop(day) }
        if let overnight {
            Spacer(minLength: 8)
            OvernightNote(text: ConnectorText.overnightNear(overnight.place))
        }
    }

    // MARK: Reordering

    /// A stop dragged to a flat position of the list: it lands before the first stop at or after that position in the
    /// same day, or at the end of the day.
    private func move(_ items: [Item], from source: IndexSet, to destination: Int) {
        guard let src = source.first, let id = items[src].stopID else { return }
        let at = min(destination, items.count)
        let day: Int
        if at < items.count, case .row(let row) = items[at] {
            day = row.day
        } else {
            day = items[..<at].reversed().compactMap { item -> Int? in
                if case .row(let row) = item { return row.day } else { return nil }
            }.first ?? 0
        }
        var before: UUID?
        for item in items[at...] {
            guard case .row(let row) = item else { continue }
            if row.day != day { break }
            if let stop = item.stopID, stop != id { before = stop; break }
        }
        builder.moveStop(id, toDay: day, before: before)
    }
}

private extension View {
    /// A List row with no background or separator, inset from the list's edge by `inset` (0 for a row that insets itself).
    func plainRow(inset: CGFloat) -> some View {
        self.listRowInsets(EdgeInsets(top: 0, leading: inset, bottom: 0, trailing: inset))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

// MARK: - Light-first suggestion

private struct SuggestionCard: View {
    let suggestion: OrderingSuggestion
    let builder: TripBuilderModel

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            Label {
                VStack(alignment: .leading, spacing: IterSpace.xxs) {
                    Text("Reorder by light: fixes ^[\(builder.conflictsFixed(by: suggestion)) conflict](inflect: true)",
                         comment: "Light-first suggestion; the number is how many schedule conflicts it fixes")
                        .font(IterFont.subheadline)
                        .foregroundStyle(IterColor.textPrimary)
                    Text("Puts the stops in the order their light arrives.", comment: "Light-first suggestion explanation")
                        .font(IterFont.caption)
                        .foregroundStyle(IterColor.textSecondary)
                }
            } icon: {
                Image(systemName: "arrow.up.arrow.down").foregroundStyle(IterColor.accent)
            }
            HStack(spacing: IterSpace.sm) {
                Button(String(localized: "Apply", comment: "Button: apply the suggested order")) { builder.apply(suggestion) }
                    .buttonStyle(.borderedProminent)
                Button(String(localized: "Dismiss", comment: "Button")) { builder.dismiss(suggestion) }
                    .buttonStyle(.bordered)
            }
            .controlSize(.regular)
        }
        .padding(IterSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ModuleFill(), in: RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous).strokeBorder(IterColor.accent.opacity(0.5), lineWidth: IterStroke.hairline))
        .accessibilityElement(children: .contain)
    }
}
