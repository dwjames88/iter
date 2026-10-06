import SwiftUI
import MapKit
import IterCore
import IterDesign
import IterFeatures

/// The round number shared by the list and the map pins.
struct StopNumberBadge: View {
    let number: Int

    var body: some View {
        Text(number, format: .number)
            .font(IterFont.captionStrong)
            .monospacedDigit()
            .foregroundStyle(IterColor.textPrimary)
            .frame(width: IterSize.badgeHeight, height: IterSize.badgeHeight)
            .background(.quaternary, in: Circle())
            .accessibilityHidden(true)
    }
}

/// One stop: its schedule leads (when to leave, when to be set up), then the session, the light, and the stop's own notes.
struct StopRowView: View {
    @Environment(AppNavigation.self) private var navigation
    let entry: TripStopEntry
    let builder: TripBuilderModel
    @Binding var selection: UUID?

    @State private var editsBuffer = false

    private var spot: Spot { entry.stop.spot }
    private var zone: TimeZone { spot.timeZone }

    var body: some View {
        HStack(alignment: .top, spacing: IterSpace.md) {
            StopNumberBadge(number: entry.number)
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                titleLine
                if let schedule = entry.schedule, let headline = ScheduleText.headline(schedule, in: zone, leavingFrom: entry.previous?.spot.timeZone) {
                    Text(headline)
                        .font(IterFont.bodyEmphasis)
                        .monospacedDigit()
                        .foregroundStyle(IterColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                sessionLine
                ForEach(ScheduleText.rowIssues(for: entry), id: \.self) { issue in
                    IssueLine(text: issue)
                }
                StopNoteField(stopID: entry.id, note: entry.stop.note, builder: builder)
            }
        }
        .padding(.vertical, IterSpace.sm)
        .contentShape(Rectangle())
        .contextMenu { StopContextMenu(entry: entry, builder: builder, selection: $selection) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Stop \(entry.number), \(spot.name)", comment: "VoiceOver: a trip stop"))
        .accessibilityAction(named: Text("Move Up", comment: "VoiceOver action")) { builder.nudgeStop(entry.id, by: -1) }
        .accessibilityAction(named: Text("Move Down", comment: "VoiceOver action")) { builder.nudgeStop(entry.id, by: 1) }
        .accessibilityAction(named: Text("Remove from Trip", comment: "VoiceOver action")) { remove() }
    }

    private func remove() {
        if selection == entry.id { selection = nil }
        builder.removeStop(entry.id)
    }

    // MARK: Lines

    private var titleLine: some View {
        HStack(alignment: .top, spacing: IterSpace.sm) {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    navigation.open(SpotRoute(spot: spot, day: builder.plan?.day(entry.stop.dayIndex)))
                } label: {
                    Text(spot.name).font(IterFont.headline).foregroundStyle(IterColor.textPrimary).lineLimit(2)
                }
                .buttonStyle(.plain)
                .help(Text("Open spot page", comment: "Tooltip"))
                if !spot.locality.isEmpty {
                    Text(spot.locality).font(IterFont.caption).foregroundStyle(IterColor.textSecondary).lineLimit(1)
                }
            }
            Spacer(minLength: IterSpace.sm)
            if let window = entry.sessionWindow {
                LightBadge(window: window, style: .regular)
            }
        }
    }

    /// Session menu, walk-in and set-up on one line when they fit; otherwise the menu on its own line with the
    /// walk-in and set-up text under it (no flexible heights, so the row never grows blank space).
    private var sessionLine: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: IterSpace.sm) {
                sessionMenu
                walkInText
                Text(verbatim: "·").accessibilityHidden(true)
                bufferButton
            }
            .fixedSize()
            VStack(alignment: .leading, spacing: IterSpace.xxs) {
                sessionMenu
                HStack(spacing: IterSpace.sm) {
                    walkInText
                    Text(verbatim: "·").accessibilityHidden(true)
                    bufferButton
                }
                .fixedSize()
            }
            VStack(alignment: .leading, spacing: IterSpace.xxs) {
                sessionMenu
                walkInText
                bufferButton
            }
        }
        .font(IterFont.caption)
        .foregroundStyle(IterColor.textSecondary)
        .lineLimit(1)
        .popover(isPresented: $editsBuffer, arrowEdge: .bottom) { bufferEditor }
    }

    private var sessionMenu: some View {
        Picker(selection: sessionBinding) {
            ForEach(entry.windows) { window in
                Text(LightText.sessionMenuItem(window, in: zone)).tag(window.kind)
            }
            if entry.sessionWindow == nil {
                Text(LightText.noSession(entry.stop.session)).tag(entry.stop.session)
            }
        } label: {
            Text("Session", comment: "Accessibility label of the session menu")
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .controlSize(.small)
        .fixedSize()
        .help(Text("Which light to shoot here: each window with its time and score for this day", comment: "Tooltip"))
    }

    private var walkInText: some View { Text(ScheduleText.walkIn(minutes: spot.walkInMinutes)) }

    private var bufferButton: some View {
        Button { editsBuffer = true } label: {
            Text(ScheduleText.buffer(minutes: entry.stop.setUpBufferMinutes))
        }
        .buttonStyle(.link)
        .help(Text("Change how long before the window you want to be set up", comment: "Tooltip"))
    }

    private var sessionBinding: Binding<LightWindowKind> {
        Binding(get: { entry.stop.session }, set: { builder.setSession(entry.id, to: $0) })
    }

    private var bufferEditor: some View {
        Stepper(value: Binding(get: { entry.stop.setUpBufferMinutes }, set: { builder.setBuffer(entry.id, minutes: $0) }),
                in: 0...120, step: 5) {
            Text("Set up \(entry.stop.setUpBufferMinutes) min before the window", comment: "Set-up buffer editor")
                .monospacedDigit()
        }
        .padding(IterSpace.md)
    }
}

/// A conflict on a stop. Warning colour, always with its icon.
struct IssueLine: View {
    let text: String

    var body: some View {
        Label {
            Text(text).font(IterFont.caption).foregroundStyle(IterColor.warning).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").font(IterFont.caption).foregroundStyle(IterColor.warning)
        }
    }
}

/// The stop's note, edited in place and saved a moment after you stop typing (and when you leave the field).
struct StopNoteField: View {
    let stopID: UUID
    let note: String
    let builder: TripBuilderModel
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(String(localized: "Add a note", comment: "Placeholder for a stop's note"), text: $text, axis: .vertical)
            .textFieldStyle(.plain)
            .font(IterFont.callout)
            .lineLimit(1...4)
            .focused($focused)
            .onAppear { text = note }
            .onChange(of: note) { if !focused { text = note } }
            .onChange(of: focused) { if !focused { commit() } }
            .onSubmit(commit)
            .task(id: text) {
                try? await Task.sleep(for: .seconds(1))
                if !Task.isCancelled { commit() }
            }
    }

    private func commit() {
        if text != note { builder.setNote(stopID, to: text) }
    }
}

struct StopContextMenu: View {
    @Environment(AppNavigation.self) private var navigation
    let entry: TripStopEntry
    let builder: TripBuilderModel
    @Binding var selection: UUID?

    var body: some View {
        Button(String(localized: "Open Spot Page", comment: "Context menu")) {
            navigation.open(SpotRoute(spot: entry.stop.spot, day: builder.plan?.day(entry.stop.dayIndex)))
        }
        Button(String(localized: "Open in Maps", comment: "Context menu")) { Self.openInMaps(entry.stop.spot) }
        Divider()
        Button(String(localized: "Move Up", comment: "Context menu")) { builder.nudgeStop(entry.id, by: -1) }
            .disabled(!builder.canNudge(entry.id, by: -1))
        Button(String(localized: "Move Down", comment: "Context menu")) { builder.nudgeStop(entry.id, by: 1) }
            .disabled(!builder.canNudge(entry.id, by: 1))
        if let plan = builder.plan, plan.dayCount > 1 {
            Menu(String(localized: "Move to Day", comment: "Context menu submenu")) {
                ForEach(0..<plan.dayCount, id: \.self) { day in
                    Button(TimeText.tripDay(index: day, day: plan.day(day))) {
                        builder.moveStop(entry.id, toDay: day)
                    }
                    .disabled(day == entry.stop.dayIndex)
                }
            }
        }
        Divider()
        Button(String(localized: "Remove from Trip", comment: "Context menu"), role: .destructive) {
            if selection == entry.id { selection = nil }
            builder.removeStop(entry.id)
        }
    }

    static func openInMaps(_ spot: Spot) {
        let item = MKMapItem(location: CLLocation(latitude: spot.coordinate.latitude, longitude: spot.coordinate.longitude), address: nil)
        item.name = spot.name
        item.openInMaps()
    }
}

/// The line between two stops: the drive and whether it fits. Across a day boundary it is an explicit overnight break (C50).
struct ConnectorRowView: View {
    let entry: TripStopEntry

    var body: some View {
        HStack(alignment: .center, spacing: IterSpace.md) {
            rail
            if entry.isOvernightFromPrevious {
                Label {
                    Text(ConnectorText.overnight).font(IterFont.captionStrong).foregroundStyle(IterColor.textSecondary)
                } icon: {
                    Image(systemName: "moon.stars").font(IterFont.caption).foregroundStyle(IterColor.textSecondary)
                }
                Rectangle().fill(IterColor.separator).frame(height: IterStroke.hairline)
                driveText
            } else {
                driveText
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, IterSpace.xs)
        .accessibilityElement(children: .combine)
    }

    private var rail: some View {
        RoundedRectangle(cornerRadius: IterStroke.thin)
            .fill(doesNotFit ? IterColor.warning : IterColor.route)
            .frame(width: IterStroke.thick, height: IterSize.iconMedium)
            .frame(width: IterSize.badgeHeight)
            .accessibilityHidden(true)
    }

    private var doesNotFit: Bool { shortBy != nil }

    @ViewBuilder private var driveText: some View {
        if let leg = entry.schedule?.legFromPrevious {
            HStack(spacing: IterSpace.xs) {
                Image(systemName: "car.fill").font(IterFont.caption).accessibilityHidden(true)
                Text(ConnectorText.drive(leg)).monospacedDigit()
                if leg.isEstimate {
                    Text(verbatim: "·").accessibilityHidden(true)
                    Text(ConnectorText.estimated).help(Text(ConnectorText.driveEstimatedHelp))
                }
                if let short = shortBy {
                    Text(verbatim: "·").accessibilityHidden(true)
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(IterColor.warning).accessibilityHidden(true)
                    Text(ScheduleText.driveDoesNotFit(shortBy: short)).foregroundStyle(IterColor.warning)
                }
            }
            .font(IterFont.caption)
            .foregroundStyle(IterColor.textSecondary)
            .lineLimit(2)
        }
    }

    private var shortBy: TimeInterval? {
        for issue in entry.schedule?.issues ?? [] {
            if case .driveDoesNotFit(let seconds) = issue { return seconds }
        }
        return nil
    }
}
