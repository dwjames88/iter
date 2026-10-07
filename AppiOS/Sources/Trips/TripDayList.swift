import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// The day-by-day plan: a `List` with a section per day. Stops reorder with the system controls (`EditButton`, `.onMove`
/// within a day, and a "Move to day" menu across days) and delete with `.onDelete`; drive connectors sit inside the stop
/// row they lead to, so the movable rows are exactly the stops.
struct TripDayList: View {
    @Environment(AppModel.self) private var model
    let plan: TripPlan
    let builder: TripBuilderModel
    @Binding var selectedDay: Int?
    let scrollTarget: DayScrollTarget?
    let addStop: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(builder.layout.groups) { group in
                    section(group)
                }
                if builder.days.contains(where: { $0.stops.contains { $0.sessionWindow?.score != nil } }) {
                    ForecastSourceLines(app: model, coordinates: builder.days.flatMap(\.stops).map(\.stop.spot.coordinate))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(IterColor.backgroundWindow)
            .onChange(of: scrollTarget) {
                if let target = scrollTarget { withAnimation { proxy.scrollTo(target.id, anchor: .top) } }
            }
        }
    }

    @ViewBuilder private func section(_ group: TripDayGroup) -> some View {
        let drives = Dictionary(group.items.compactMap { item -> (UUID, (TripDriveItem, Bool))? in
            switch item {
            case .driveIn(let drive): (drive.toStopID, (drive, true))
            case .drive(let drive): (drive.toStopID, (drive, false))
            default: nil
            }
        }, uniquingKeysWith: { first, _ in first })
        Section {
            if let suggestion = group.suggestion {
                SuggestionCard(suggestion: suggestion, builder: builder)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: IterSpace.xs, leading: 0, bottom: IterSpace.xs, trailing: 0))
            }
            if group.hasConflict {
                DayConflictRow(count: group.conflictCount)
                    .listRowBackground(IterColor.backgroundModule)
            }
            ForEach(group.stops) { entry in
                StopCard(entry: entry, builder: builder, plan: plan, drive: drives[entry.id]?.0, isDriveIn: drives[entry.id]?.1 ?? false)
                    .id("stop-\(entry.id)")
                    .listRowBackground(IterColor.backgroundModule)
                    .listRowInsets(EdgeInsets(top: IterSpace.sm, leading: IterSpace.lg, bottom: IterSpace.sm, trailing: IterSpace.lg))
            }
            .onMove { move(group, from: $0, to: $1) }
            .onDelete { offsets in
                let ids = offsets.map { group.stops[$0].id }
                ids.forEach(builder.removeStop)
            }
            Button { addStop(group.index) } label: {
                Label(String(localized: "Add stop", comment: "Button at the end of a day"), systemImage: "plus.circle.fill")
                    .font(IterFont.bodyEmphasis)
                    .foregroundStyle(IterColor.accentText)
                    .frame(maxWidth: .infinity, minHeight: IterSize.hitTarget, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .moveDisabled(true)
            .deleteDisabled(true)
            .listRowBackground(IterColor.backgroundModule)
        } header: {
            DayHeader(group: group, plan: plan, isSelected: selectedDay == group.index) {
                selectedDay = group.index
                builder.setFocusDay(group.index)
            }
            .id("header-\(group.index)")
        } footer: {
            if let boundary = group.overnightAfter {
                OvernightBoundaryRow(boundary: boundary)
                    .padding(.vertical, -IterSpace.xs)
            }
        }
    }

    private func move(_ group: TripDayGroup, from source: IndexSet, to destination: Int) {
        let ids = group.stops.map(\.id)
        guard let src = source.first else { return }
        var remaining = ids
        let moving = remaining.remove(at: src)
        let insertAt = destination > src ? destination - 1 : destination
        let before = remaining.indices.contains(insertAt) ? remaining[insertAt] : nil
        builder.moveStop(moving, toDay: group.index, before: before)
    }
}

// MARK: - Day header

private struct DayHeader: View {
    let group: TripDayGroup
    let plan: TripPlan
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: IterSpace.xxs) {
                HStack(spacing: IterSpace.sm) {
                    Text(Self.title(group))
                        .font(IterFont.titleSection)
                        .foregroundStyle(isSelected ? IterColor.accentText : IterColor.textPrimary.color)
                    if group.hasConflict {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(IterColor.warning).font(IterFont.caption)
                            .accessibilityHidden(true)
                    }
                }
                HStack(spacing: IterSpace.md) {
                    Text(LightText.dayTotals(stops: group.stopCount, drivingSeconds: group.drivingSeconds)).monospacedDigit()
                    if let sunrise = group.sunrise { bookend("sunrise.fill", sunrise) }
                    if let sunset = group.sunset { bookend("sunset.fill", sunset) }
                }
                .font(IterFont.caption)
                .foregroundStyle(IterColor.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            }
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, IterSpace.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
    }

    /// "Day 2 · Wed 8 Oct"
    private static func title(_ group: TripDayGroup) -> String {
        let utc = TimeZone(identifier: "UTC")!
        var style = Date.FormatStyle().weekday(.abbreviated).day().month(.abbreviated)
        style.timeZone = utc
        return String(localized: "Day \(group.index + 1) · \(group.date.noon(in: utc).formatted(style))", comment: "Trip day header, e.g. Day 2 · Wed 7 Oct")
    }

    private func bookend(_ symbol: String, _ time: Date) -> some View {
        HStack(spacing: IterSpace.xxs) {
            Image(systemName: symbol).accessibilityHidden(true)
            Text(TimeText.time(time, in: group.timeZone)).monospacedDigit()
        }
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
        .background(IterColor.backgroundModule, in: RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous).strokeBorder(IterColor.accent.opacity(0.5), lineWidth: IterStroke.hairline))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - Stop

private struct StopCard: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.editMode) private var editMode
    let entry: TripStopEntry
    let builder: TripBuilderModel
    let plan: TripPlan
    let drive: TripDriveItem?
    let isDriveIn: Bool

    private var spot: Spot { entry.stop.spot }
    private var zone: TimeZone { spot.timeZone }
    private var isEditing: Bool { editMode?.wrappedValue.isEditing ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            if let drive { connector(drive) }
            HStack(alignment: .top, spacing: IterSpace.sm) {
                StopNumberBadge(number: entry.number)
                Button(action: open) {
                    VStack(alignment: .leading, spacing: IterSpace.xs) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(spot.name).font(IterFont.headline).foregroundStyle(IterColor.textPrimary).lineLimit(2)
                            if !spot.locality.isEmpty {
                                Text(spot.locality).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary).lineLimit(1)
                            }
                        }
                        if let window = entry.sessionWindow { score(window) }
                        if let line = scheduleLine {
                            Text(line).font(IterFont.subheadline).foregroundStyle(IterColor.textSecondary).monospacedDigit()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(ScheduleText.rowIssues(for: entry), id: \.self) { IssueLine(text: $0) }
                        if !entry.stop.note.isEmpty {
                            Text(entry.stop.note).font(IterFont.callout).foregroundStyle(IterColor.textSecondary).lineLimit(3)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            controls
        }
        .contextMenu { StopMenu(entry: entry, builder: builder, plan: plan) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Stop \(entry.number), \(spot.name)", comment: "VoiceOver: a trip stop"))
        .accessibilityAction(named: Text("Move Up", comment: "VoiceOver action")) { builder.nudgeStop(entry.id, by: -1) }
        .accessibilityAction(named: Text("Move Down", comment: "VoiceOver action")) { builder.nudgeStop(entry.id, by: 1) }
        .accessibilityAction(named: Text("Remove from Trip", comment: "VoiceOver action")) { builder.removeStop(entry.id) }
    }

    private func open() {
        navigation.open(SpotRoute(spot: spot, day: plan.day(entry.stop.dayIndex)))
    }

    private func score(_ window: LightWindow) -> some View {
        EventScore(window: window, zone: zone, timeStyle: .start, variant: .regular, isLoading: model.forecasts.isLoading(spot.coordinate))
    }

    /// "Leave 4:10 · set up by 5:52" (just the set-up time for a stop with no drive into it).
    private var scheduleLine: String? {
        guard let schedule = entry.schedule else { return nil }
        let setUp = schedule.setUpBy.map { TimeText.time($0, in: zone) }
        let leave = drive.flatMap { d in schedule.leaveBy.map { TimeText.time($0, in: d.leaveZone) } }
        switch (leave, setUp) {
        case let (leave?, setUp?):
            return String(localized: "Leave \(leave) · set up by \(setUp)", comment: "Stop schedule: when to leave and be set up")
        case let (nil, setUp?):
            return String(localized: "Set up by \(setUp)", comment: "Stop schedule: when to be set up")
        case let (leave?, nil):
            return String(localized: "Leave \(leave)", comment: "Stop schedule: when to leave")
        default:
            return nil
        }
    }

    private func connector(_ drive: TripDriveItem) -> some View {
        let tone = RailTone(drive)
        return HStack(alignment: .firstTextBaseline, spacing: IterSpace.xs) {
            Image(systemName: drive.fits ? "car.fill" : "exclamationmark.triangle.fill")
                .font(IterFont.caption)
                .foregroundStyle(tone.color)
            VStack(alignment: .leading, spacing: 0) {
                if let leg = drive.leg {
                    Text(leg.isEstimate ? "\(ConnectorText.drive(leg)) · \(ConnectorText.estimated)" : ConnectorText.drive(leg))
                        .monospacedDigit()
                } else {
                    Text("Drive time loading", comment: "Drive connector while the drive is being fetched")
                }
                if let short = drive.shortBySeconds {
                    Text(ScheduleText.driveDoesNotFit(shortBy: short)).foregroundStyle(IterColor.warning)
                } else if isDriveIn {
                    Text("From \(drive.fromName)", comment: "Under the drive into a day's first stop: where the drive starts")
                        .foregroundStyle(IterColor.textTertiary)
                }
            }
            .font(IterFont.caption)
            .foregroundStyle(IterColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, IterSpace.xxs)
        .accessibilityElement(children: .combine)
    }

    /// Session picker, and in edit mode the move-to-day menu (system reordering is within a day).
    private var controls: some View {
        HStack(spacing: IterSpace.sm) {
            Menu {
                Picker(selection: Binding(get: { entry.stop.session }, set: { builder.setSession(entry.id, to: $0) })) {
                    ForEach(entry.windows) { window in
                        Label(LightText.sessionMenuItem(window, in: zone), systemImage: LightText.symbol(window.kind)).tag(window.kind)
                    }
                    if entry.sessionWindow == nil { Text(LightText.noSession(entry.stop.session)).tag(entry.stop.session) }
                } label: { Text("Session", comment: "Accessibility label of the session menu") }
                .pickerStyle(.inline)
            } label: {
                chipLabel(entry.sessionWindow.map { LightText.sessionLabel($0, in: zone) } ?? LightText.noSession(entry.stop.session),
                          symbol: "sun.max")
            }
            if isEditing, plan.dayCount > 1 {
                Menu {
                    ForEach(0..<plan.dayCount, id: \.self) { day in
                        Button(TimeText.tripDay(index: day, day: plan.day(day))) { builder.moveStop(entry.id, toDay: day) }
                            .disabled(day == entry.stop.dayIndex)
                    }
                } label: {
                    Image(systemName: "calendar")
                        .font(IterFont.subheadline)
                        .foregroundStyle(IterColor.textPrimary)
                        .frame(width: IterSize.hitTarget, height: IterSize.hitTarget - IterSpace.sm)
                        .background(IterColor.backgroundControl, in: Capsule())
                }
                .accessibilityLabel(Text("Move to day", comment: "Edit mode: menu to move a stop to another day"))
            }
        }
        .padding(.leading, IterSize.badgeHeight + IterSpace.sm)
    }

    private func chipLabel(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .font(IterFont.subheadline)
            .foregroundStyle(IterColor.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, IterSpace.sm)
            .frame(minHeight: IterSize.hitTarget - IterSpace.sm)
            .background(IterColor.backgroundControl, in: Capsule())
    }
}

private struct StopMenu: View {
    @Environment(AppNavigation.self) private var navigation
    let entry: TripStopEntry
    let builder: TripBuilderModel
    let plan: TripPlan

    var body: some View {
        Button { navigation.open(SpotRoute(spot: entry.stop.spot, day: plan.day(entry.stop.dayIndex))) } label: {
            Label(String(localized: "Open Spot Page", comment: "Context menu"), systemImage: "mappin.and.ellipse")
        }
        Button { StopContextMenu.openInMaps(entry.stop.spot) } label: {
            Label(String(localized: "Open in Maps", comment: "Context menu"), systemImage: "map")
        }
        Divider()
        Button { builder.nudgeStop(entry.id, by: -1) } label: {
            Label(String(localized: "Move Up", comment: "Context menu"), systemImage: "arrow.up")
        }
        .disabled(!builder.canNudge(entry.id, by: -1))
        Button { builder.nudgeStop(entry.id, by: 1) } label: {
            Label(String(localized: "Move Down", comment: "Context menu"), systemImage: "arrow.down")
        }
        .disabled(!builder.canNudge(entry.id, by: 1))
        if plan.dayCount > 1 {
            Menu(String(localized: "Move to Day", comment: "Context menu submenu")) {
                ForEach(0..<plan.dayCount, id: \.self) { day in
                    Button(TimeText.tripDay(index: day, day: plan.day(day))) { builder.moveStop(entry.id, toDay: day) }
                        .disabled(day == entry.stop.dayIndex)
                }
            }
        }
        Divider()
        Button(role: .destructive) { builder.removeStop(entry.id) } label: {
            Label(String(localized: "Remove from Trip", comment: "Context menu"), systemImage: "trash")
        }
    }
}
