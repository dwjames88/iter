import SwiftUI
import IterFeatures
import IterModel
import IterUI

/// One stop card with its light-window menu, set-up popover, kind menu, note and score chip.
struct StopRowView: View {
    let stop: BuildStop
    let day: Int
    let isSelected: Bool
    let loadingScores: Bool
    let model: BuildModel
    @Environment(AppNavigator.self) private var navigator
    @State private var editsSetUp = false

    var body: some View {
        StopCard(time: stop.time.map { TimeText.time($0, in: stop.timeZone) },
                 timeLabel: stop.timeLabel == .setUp ? String(localized: "Set up", comment: "Under a stop's set-up time")
                                                      : String(localized: "Arrive", comment: "Under a lodging or waypoint's arrival time"),
                 number: stop.number, name: stop.name, locality: stop.locality, walkText: walkText, setUpText: setUpText,
                 issues: stop.issues.map { $0.message() }, isSelected: isSelected,
                 onOpenSpot: { navigator.open(.place(stop.placeID)) }, editsSetUp: $editsSetUp) {
            pickerRow
        } score: {
            scoreChip
        } note: {
            DebouncedText(value: stop.note, save: { model.setNote(stop.id, to: $0) }) { text, commit in
                NotePlaceholder(text: text, onCommit: commit)
            }
        } setUpEditor: {
            StopTimingEditor(stop: stop, model: model)
        }
        .contextMenu { menu }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Stop \(stop.number), \(stop.name)", comment: "VoiceOver: a stop's number and name"))
        .id("stop-\(stop.id)")
    }

    // MARK: Text

    private var walkText: String {
        switch stop.kind {
        case .light: TripBuilderText.parkLine(parkAt: stop.parkAt, walkMinutes: stop.walkInMinutes, in: stop.timeZone)
        case .lodging: String(localized: "Lodging", comment: "Stop kind")
        case .waypoint: String(localized: "Waypoint", comment: "Stop kind")
        }
    }

    private var setUpText: String {
        if stop.kind == .light { return TripBuilderText.setUpShort(minutes: stop.setUpBufferMinutes) }
        if stop.dwellMinutes > 0 { return String(localized: "\(stop.dwellMinutes) min stop", comment: "How long you stay at a waypoint") }
        return stop.kind == .lodging ? String(localized: "Overnight", comment: "A lodging stop with no set stay")
                                     : String(localized: "Quick stop", comment: "A waypoint with no set stay")
    }

    // MARK: Pieces

    @ViewBuilder private var pickerRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if stop.kind == .light {
                    LightWindowPicker(options: stop.options.map { .init(kind: $0.kind, start: $0.start, end: $0.end, score: $0.score) },
                                      selection: Binding(get: { stop.session }, set: { model.setSession(stop.id, to: $0) }),
                                      zone: stop.timeZone)
                } else {
                    ArrivalField(stop: stop, model: model)
                }
                kindMenu
            }
            if stop.kind == .light, let until = stop.shootUntil {
                Text("Shoot until \(TimeText.time(until, in: stop.timeZone))", comment: "A light stop: when you are free to leave")
                    .font(BuilderType.body)
                    .foregroundStyle(IterColor.textTertiary)
            }
        }
    }

    private var kindMenu: some View {
        Menu {
            Picker(selection: Binding(get: { stop.kind }, set: { model.setKind(stop.id, $0) })) {
                ForEach(StopKind.allCases, id: \.self) { kind in
                    Label(Self.name(kind), systemImage: Self.symbol(kind)).tag(kind)
                }
            } label: { Text("Kind", comment: "Accessibility label of the stop kind menu") }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Image(systemName: Self.symbol(stop.kind)).font(BuilderType.body)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text("Kind", comment: "Accessibility label of the stop kind menu"))
        .accessibilityValue(Text(Self.name(stop.kind)))
        .help(Text("Light stop, lodging or waypoint", comment: "Tooltip of the stop kind menu"))
    }

    static func name(_ kind: StopKind) -> String {
        switch kind {
        case .light: String(localized: "Light", comment: "Stop kind: a place you shoot")
        case .lodging: String(localized: "Lodging", comment: "Stop kind")
        case .waypoint: String(localized: "Waypoint", comment: "Stop kind")
        }
    }

    static func symbol(_ kind: StopKind) -> String {
        switch kind {
        case .light: "camera"
        case .lodging: "bed.double.fill"
        case .waypoint: "mappin.and.ellipse"
        }
    }

    @ViewBuilder private var scoreChip: some View {
        if stop.kind == .light, let window = stop.options.first(where: { $0.kind == stop.session }) {
            ScoreChip(kind: window.kind, start: window.start, score: stop.score, zone: stop.timeZone, size: .small, timeStyle: .start,
                      isLoading: stop.score == nil && loadingScores)
        }
    }

    // MARK: Menu

    @ViewBuilder private var menu: some View {
        let dayStops = StopMoves.dayStops(in: model.rows)
        Button { if let move = StopMoves.up(stop.id, dayStops: dayStops) { model.moveStop(stop.id, toDay: move.day, index: move.index) } } label: {
            Label(String(localized: "Move Up", comment: "Menu item"), systemImage: "arrow.up")
        }
        .disabled(StopMoves.up(stop.id, dayStops: dayStops) == nil)
        Button { if let move = StopMoves.down(stop.id, dayStops: dayStops) { model.moveStop(stop.id, toDay: move.day, index: move.index) } } label: {
            Label(String(localized: "Move Down", comment: "Menu item"), systemImage: "arrow.down")
        }
        .disabled(StopMoves.down(stop.id, dayStops: dayStops) == nil)
        Menu {
            ForEach(model.dayItems) { item in
                Button { model.moveStop(stop.id, toDay: item.index, index: nil) } label: {
                    Text("\(TripBuilderText.dayName(index: item.index)), \(TripBuilderText.weekdayName(item.date))")
                }
                .disabled(item.index == day)
            }
        } label: {
            Label(String(localized: "Move to Day", comment: "Menu item"), systemImage: "calendar")
        }
        Divider()
        Button { navigator.open(.place(stop.placeID)) } label: {
            Label(String(localized: "Open Place Page", comment: "Menu item"), systemImage: "mappin.and.ellipse")
        }
        Divider()
        Button(role: .destructive) { model.removeStop(stop.id) } label: {
            Label(String(localized: "Remove", comment: "Menu item"), systemImage: "trash")
        }
    }
}

/// Set-up time before the window, and how long you stay ("shoot until"). Both are saved as you change them.
struct StopTimingEditor: View {
    let stop: BuildStop
    let model: BuildModel

    private static let dwellChoices = [0, 15, 30, 45, 60, 90, 120, 180]

    var body: some View {
        Form {
            if stop.kind == .light {
                Stepper(value: Binding(get: { stop.setUpBufferMinutes }, set: { model.setBuffer(stop.id, minutes: $0) }), in: 0...120, step: 5) {
                    Text("Set up \(stop.setUpBufferMinutes) min before the window", comment: "Stepper: minutes to be set up before the light window starts")
                }
            }
            Picker(selection: Binding(get: { stop.dwellMinutes }, set: { model.setDwell(stop.id, minutes: $0) })) {
                Text(stop.kind == .light ? "Until the window ends" : "No set time", comment: "Dwell choice: stay for the whole window").tag(0)
                ForEach(Self.dwellChoices.dropFirst(), id: \.self) { minutes in
                    Text(Self.dwellName(minutes)).tag(minutes)
                }
                if !Self.dwellChoices.contains(stop.dwellMinutes) { Text(Self.dwellName(stop.dwellMinutes)).tag(stop.dwellMinutes) }
            } label: {
                Text(stop.kind == .light ? "Shoot for" : "Stay for", comment: "Dwell picker label")
            }
            if let until = stop.shootUntil {
                LabeledContent {
                    Text(TimeText.time(until, in: stop.timeZone)).monospacedDigit()
                } label: {
                    Text(stop.kind == .light ? "Free to leave at" : "Leave at", comment: "When the stop ends")
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
        .tint(nil)
    }

    static func dwellName(_ minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
    }
}

/// A lodging or waypoint's arrival time: a compact time field that sets a fixed arrival, with a way back to automatic.
struct ArrivalField: View {
    let stop: BuildStop
    let model: BuildModel

    private static let utc = TimeZone(identifier: "UTC") ?? .gmt

    var body: some View {
        HStack(spacing: 8) {
            DatePicker(selection: Binding(get: { date }, set: { set($0) }), displayedComponents: .hourAndMinute) {
                Text("Arrive at", comment: "Accessibility label of a lodging's arrival time")
            }
            .labelsHidden()
            .datePickerStyle(.compact)
            .environment(\.timeZone, Self.utc)
            .fixedSize()
            if stop.fixedArrival != nil {
                Button { model.setFixedArrival(stop.id, to: nil) } label: { Text("Automatic", comment: "Button: clear a fixed arrival time") }
                    .buttonStyle(.borderless)
                    .font(BuilderType.control)
            }
        }
    }

    private var local: LocalTime {
        if let fixed = stop.fixedArrival { return fixed }
        guard let time = stop.time else { return LocalTime(hour: 12, minute: 0) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = stop.timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        return LocalTime(hour: parts.hour ?? 12, minute: parts.minute ?? 0)
    }

    private var date: Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        return calendar.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: local.hour, minute: local.minute)) ?? .distantPast
    }

    private func set(_ date: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.utc
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        model.setFixedArrival(stop.id, to: LocalTime(hour: parts.hour ?? 12, minute: parts.minute ?? 0))
    }
}
