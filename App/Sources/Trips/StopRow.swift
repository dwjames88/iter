import SwiftUI
import MapKit
import IterCore
import IterDesign
import IterFeatures

/// One stop in a day card, as the list draws it: the `StopCard` fed from the entry, with the row's behaviour around it (the
/// context menu, VoiceOver actions, the session menu, the set-up editor and the note). Leave times belong to the drive row
/// above it.
struct StopRowView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    let entry: TripStopEntry
    let builder: TripBuilderModel
    var isSelected = false
    /// Removes this stop (the list clears the selection with it).
    var onRemove: (UUID) -> Void

    @State private var editsSetUp = false

    private var spot: Spot { entry.stop.spot }
    private var zone: TimeZone { spot.timeZone }

    var body: some View {
        StopCard(time: entry.schedule?.setUpBy.map { TimeText.time($0, in: zone) },
                 timeLabel: String(localized: "Set up", comment: "Label under a stop's set-up time"),
                 number: entry.number, name: spot.name, locality: spot.locality,
                 walkText: ScheduleText.parkLine(entry.schedule, minutes: spot.walkInMinutes, in: zone),
                 setUpText: ScheduleText.setUpShort(minutes: entry.stop.setUpBufferMinutes),
                 issues: ScheduleText.rowIssues(for: entry), isSelected: isSelected,
                 onOpenSpot: { navigation.open(SpotRoute(spot: spot, day: builder.plan?.day(entry.stop.dayIndex))) },
                 editsSetUp: $editsSetUp) {
            LightWindowPicker(options: pickerOptions, selection: entry.stop.session, closedLabel: closedLabel) { builder.setSession(entry.id, to: $0) }
        } score: {
            if let window = entry.sessionWindow {
                ScoreChip(window: window, zone: zone, timeStyle: .start, size: .small, isLoading: model.forecasts.isLoading(spot.coordinate))
            }
        } note: {
            NotePlaceholder(note: entry.stop.note) { builder.setNote(entry.id, to: $0) }
        } setUpEditor: {
            setUpEditor
        }
        .contextMenu { StopContextMenu(entry: entry, builder: builder, onRemove: remove) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Stop \(entry.number), \(spot.name)", comment: "VoiceOver: a trip stop"))
        .accessibilityAction(named: Text("Move Up", comment: "VoiceOver action")) { builder.nudgeStop(entry.id, by: -1) }
        .accessibilityAction(named: Text("Move Down", comment: "VoiceOver action")) { builder.nudgeStop(entry.id, by: 1) }
        .accessibilityAction(named: Text("Remove from Trip", comment: "VoiceOver action")) { remove() }
    }

    private func remove() { onRemove(entry.id) }

    private var pickerOptions: [LightWindowPicker.Option] {
        var options = entry.windows.map {
            LightWindowPicker.Option(kind: $0.kind, title: LightText.sessionMenuItem($0, in: zone), symbol: LightText.symbol($0.kind))
        }
        if entry.sessionWindow == nil {
            options.append(.init(kind: entry.stop.session, title: LightText.noSession(entry.stop.session), symbol: LightText.symbol(entry.stop.session)))
        }
        return options
    }

    /// The closed menu names the window only; its time and score are in the chip beside it.
    private var closedLabel: String { LightText.name(entry.stop.session) }

    private var setUpEditor: some View {
        Stepper(value: Binding(get: { entry.stop.setUpBufferMinutes }, set: { builder.setBuffer(entry.id, minutes: $0) }),
                in: 0...120, step: 5) {
            Text("Set up \(entry.stop.setUpBufferMinutes) min before the window", comment: "Set-up buffer editor")
                .monospacedDigit()
        }
        .padding(IterSpace.lg)
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

struct StopContextMenu: View {
    @Environment(AppNavigation.self) private var navigation
    let entry: TripStopEntry
    let builder: TripBuilderModel
    let onRemove: () -> Void

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
            onRemove()
        }
    }

    static func openInMaps(_ spot: Spot) {
        let item = MKMapItem(location: CLLocation(latitude: spot.coordinate.latitude, longitude: spot.coordinate.longitude), address: nil)
        item.name = spot.name
        item.openInMaps()
    }
}
