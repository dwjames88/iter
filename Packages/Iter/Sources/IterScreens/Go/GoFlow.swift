import Foundation
import SwiftUI
import IterModel
import IterGo
import IterGoActivity
import IterFeatures
import IterUI

// The pure decisions behind the Go screens: which screen a phase gets, where the permission row sits, whether the undo
// banner shows, how the schedule groups by day. No SwiftUI state, so `GoFlowTests` covers them without rendering.

enum GoFlow {
    /// Which of the sheet's three bodies a phase gets.
    enum Screen: Hashable {
        case start, running, finished
    }

    /// `finishedDismissed`: the user tapped Done on the summary, so the start view comes back.
    static func screen(for phase: GoPhase, finishedDismissed: Bool = false) -> Screen {
        switch phase {
        case .idle: .start
        case .finished: finishedDismissed ? .start : .finished
        case .armed, .driving, .atStop, .betweenStops, .paused: .running
        }
    }

    enum PermissionPlacement: Hashable {
        case aboveHero, belowHero
    }

    /// Nothing works without location, so asking for it leads. Every other row waits below the hero card.
    static func permissionPlacement(_ step: GoPermissionStep) -> PermissionPlacement {
        if case .locationWhenInUse = step { return .aboveHero }
        return .belowHero
    }

    /// The undo banner shows while the undo exists and has not expired.
    static func undoIsVisible(_ undo: GoUndoInfo?, now: Date) -> Bool {
        guard let undo else { return false }
        return undo.expiresAt > now
    }

    /// Whole seconds left on the undo, never negative.
    static func undoSecondsLeft(_ undo: GoUndoInfo, now: Date) -> Int {
        max(0, Int(undo.expiresAt.timeIntervalSince(now).rounded(.up)))
    }

    /// "1:40"
    static func clockText(seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// What the banner says happened.
    static func undoSentence(_ undo: GoUndoInfo) -> String {
        let name = undo.stopName
        switch undo.toPhase {
        case .atStop: return name.map { "Arrived at \($0)" } ?? "Arrived"
        case .driving: return name.map { "Heading to \($0)" } ?? "On the road"
        case .betweenStops: return name.map { "Done at \($0)" } ?? "Done here"
        case .paused: return "Trip paused"
        case .armed: return "Trip started"
        case .finished: return "Trip finished"
        case .idle: return "Trip ended"
        }
    }

    // MARK: Schedule

    /// The stops still to do: the snapshot's schedule, else the next stop on its own.
    static func scheduleItems(_ snapshot: GoSnapshot) -> [GoScheduleItem] {
        if let schedule = snapshot.schedule, !schedule.isEmpty { return schedule }
        guard let next = snapshot.next else { return [] }
        return [GoScheduleItem(stop: next, leaveBy: snapshot.leave?.leaveBy, arrival: snapshot.drive?.arrival, status: snapshot.leave?.status)]
    }

    struct ScheduleDay: Identifiable, Hashable {
        var dayIndex: Int
        var items: [GoScheduleItem]
        var id: Int { dayIndex }
    }

    /// Consecutive stops of one trip day, in trip order.
    static func groupByDay(_ items: [GoScheduleItem]) -> [ScheduleDay] {
        var days: [ScheduleDay] = []
        for item in items {
            if let last = days.last, last.dayIndex == item.stop.dayIndex {
                days[days.count - 1].items.append(item)
            } else {
                days.append(ScheduleDay(dayIndex: item.stop.dayIndex, items: [item]))
            }
        }
        return days
    }

    /// The heading of a day group: "Today", "Tomorrow", otherwise "Tue, Oct 13". The first group's calendar day is read from
    /// its first stop's own time; later groups count on from it by trip day. `now` is read in the first stop's zone.
    static func dayHeading(group: ScheduleDay, first: ScheduleDay, now: Date, locale: Locale = .current) -> String {
        guard let firstStop = first.items.first?.stop else { return "" }
        let zone = zone(firstStop)
        let today = LocalDay(now, in: zone)
        let anchorDate = firstStop.windowStart ?? firstStop.arriveBy ?? first.items.first?.leaveBy ?? now
        let anchor = LocalDay(anchorDate, in: zone)
        let day = anchor.adding(days: group.dayIndex - first.dayIndex)
        return TimeText.relativeDay(day, today: today, locale: locale)
    }

    static func zone(_ stop: GoStopInfo) -> TimeZone { TimeZone(identifier: stop.timeZoneIdentifier) ?? .current }

    // MARK: Trips

    /// "Tue, Oct 6" or "Tue, Oct 6 – Thu, Oct 8".
    static func dateSpan(_ trip: GoTripChoice, locale: Locale = .current) -> String {
        let first = TimeText.day(trip.startDay, locale: locale)
        guard trip.dayCount > 1 else { return first }
        return "\(first) – \(TimeText.day(trip.startDay.adding(days: trip.dayCount - 1), locale: locale))"
    }

    struct TripDay: Identifiable, Hashable {
        var dayIndex: Int
        var stops: [GoTripChoice.StopChoice]
        var id: Int { dayIndex }
    }

    /// A trip's stops grouped by trip day, days ascending, stops in number order.
    static func stopsByDay(_ trip: GoTripChoice) -> [TripDay] {
        let grouped = Dictionary(grouping: trip.stops, by: \.dayIndex)
        return grouped.keys.sorted().map { TripDay(dayIndex: $0, stops: grouped[$0]!.sorted { $0.number < $1.number }) }
    }

    /// The stop id to send to `start`: nil when it is the trip's first stop (the default).
    static func startStopID(selected: UUID?, in trip: GoTripChoice) -> UUID? {
        guard let selected, selected != trip.stops.min(by: { $0.number < $1.number })?.id else { return nil }
        return selected
    }

    // MARK: Permission copy

    struct PermissionCopy: Hashable {
        enum Action: Hashable { case allowWhenInUse, allowAlways, allowNotifications, openSettings }
        var symbol: String
        var sentence: String
        var button: String
        var action: Action
    }

    static func permissionCopy(_ step: GoPermissionStep) -> PermissionCopy {
        switch step {
        case .locationWhenInUse:
            PermissionCopy(symbol: "location", sentence: "Iter uses your location to time each drive and notice when you arrive.",
                           button: "Allow Location", action: .allowWhenInUse)
        case .locationAlways(let reason):
            PermissionCopy(symbol: "location.fill", sentence: reason, button: "Allow Always", action: .allowAlways)
        case .notifications:
            PermissionCopy(symbol: "bell", sentence: "Iter can tell you when it is time to leave, even with your phone locked.",
                           button: "Allow Notifications", action: .allowNotifications)
        case .openSettings(let topic):
            switch topic {
            case .location:
                PermissionCopy(symbol: "location.slash", sentence: "Location is off for Iter, so drive times and arrivals cannot update.",
                               button: "Open Settings", action: .openSettings)
            case .notifications:
                PermissionCopy(symbol: "bell.slash", sentence: "Notifications are off, so you will not get a leave-by alert.",
                               button: "Open Settings", action: .openSettings)
            }
        case .liveActivitiesOff:
            PermissionCopy(symbol: "lock", sentence: "Live Activities are off, so the Lock Screen card will not appear.",
                           button: "Open Settings", action: .openSettings)
        }
    }
}

// MARK: - Shared card

/// A solid content card: `background/content`, the floating cards' corner, a hairline. Local equivalent of IterUI's
/// `goCard()` (internal there); same look, no glass.
struct GoScreenCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(IterSpace.md + IterSpace.xs)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(IterColor.backgroundContent, in: RoundedRectangle(cornerRadius: GlassGeometry.cardCorner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: GlassGeometry.cardCorner, style: .continuous)
                    .strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline)
            }
    }
}

extension View {
    func goScreenCard() -> some View { modifier(GoScreenCard()) }
}

/// Where the night-view preference lives (the sheet's menu and the map both read it).
enum GoNightView {
    static let key = "go.nightView"
}

extension View {
    /// The one prominent button of a screen: system `.glassProminent`. `flat` (offscreen renders only, set by tests through
    /// `goFlatButtons`) swaps in the bordered-prominent style, because system glass blanks offscreen.
    @ViewBuilder func goProminentButton(flat: Bool) -> some View {
        if flat { buttonStyle(.borderedProminent).tint(IterColor.accent) } else { buttonStyle(.glassProminent) }
    }
}
