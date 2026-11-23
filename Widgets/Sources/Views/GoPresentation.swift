import Foundation
import IterGoActivity
import IterModel
import IterUI

/// Whether countdowns tick on their own (the Live Activity and the widgets: `Text(timerInterval:)`) or are drawn as a frozen
/// string at `now` (snapshot renders and tests).
struct GoClock: Hashable, Sendable {
    var now: Date
    var isLive: Bool

    static func live(_ now: Date) -> GoClock { GoClock(now: now, isLive: true) }
    static func frozen(_ now: Date) -> GoClock { GoClock(now: now, isLive: false) }
}

/// What the Live Activity, the Dynamic Island and the widgets say, decided once from a `GoActivityContent` and the clock, so
/// every presentation agrees. Pure: no SwiftUI, no WidgetKit.
///
/// Without push (free Personal Team) the content is only as fresh as the last time the app ran, so every presentation shows
/// `ageText` once the data is older than `oldAfter` or the system marks the activity stale. Countdowns use absolute dates and
/// keep counting on their own.
struct GoPresentation: Equatable {
    static let oldAfter: TimeInterval = 15 * 60
    /// Past this the age reads "Updated 3 hr ago" instead of a clock time.
    static let clockTimeUntil: TimeInterval = 3 * 3600

    enum Tone: Equatable { case normal, warning, accent }

    struct Countdown: Equatable {
        /// "Leave in", "Arrive in"
        var label: String
        var target: Date
    }

    var content: GoActivityContent
    var clock: GoClock
    var zone: TimeZone
    var isStale: Bool

    init(_ content: GoActivityContent, clock: GoClock, zone: TimeZone = .current, isStale: Bool = false) {
        self.content = content
        self.clock = clock
        // The stop's own zone when the content carries it (every time about a stop is shown where the stop is); else `zone`.
        self.zone = content.timeZoneIdentifier.flatMap { TimeZone(identifier: $0) } ?? zone
        self.isStale = isStale
    }

    var phase: GoPhase { content.phase }
    var now: Date { clock.now }

    // MARK: Words

    /// The stop, or what the activity is about when there is none.
    var title: String {
        switch phase {
        case .idle: String(localized: "No trip running")
        case .finished: content.nextStopName ?? String(localized: "Trip complete")
        default: content.nextStopName ?? String(localized: "Next stop")
        }
    }

    var isIdle: Bool { phase == .idle }
    var isFinished: Bool { phase == .finished }
    var isPaused: Bool { phase == .paused }

    /// The one sentence that replaces the countdown, with its tone: "Leave now", "Late by 6 min", "Paused", "Trip complete".
    var status: (text: String, tone: Tone)? {
        switch phase {
        case .idle: return nil
        case .finished: return (String(localized: "Trip complete"), .normal)
        case .paused: return (String(localized: "Paused"), .normal)
        default: break
        }
        switch content.status {
        case .missed:
            return (isHistorical ? String(localized: "Window was missed") : String(localized: "Window missed"), .warning)
        case .late:
            return (lateText, .warning)
        case .leaveNow where phase != .driving && !isHistorical:
            return (String(localized: "Leave now"), .accent)
        default:
            break
        }
        // The content can be older than the clock: leave-by has passed since the status was computed.
        if phase != .driving, phase != .atStop, let leaveBy = content.leaveBy, leaveBy.timeIntervalSince(now) <= TripText.nowTolerance {
            if now.timeIntervalSince(leaveBy) > TripText.nowTolerance { return (lateText, .warning) }
            return (String(localized: "Leave now"), .accent)
        }
        return nil
    }

    /// The content is old (or the system marked it stale), so a status taken from it is history, not a current fact:
    /// "Was late by 26 min", with the age line saying "As of 13:10".
    var isHistorical: Bool { isStale || isOld }

    private var lateText: String {
        // Leave-by already passed on the clock: late by the clock, which is current whatever the content's age.
        if phase != .driving, let leaveBy = content.leaveBy, now > leaveBy {
            // On an old plan this is not a claim about the present: say what was due, not how late you are.
            if isHistorical { return String(localized: "Leave was due \(TimeText.time(leaveBy, in: zone))") }
            return TripText.lateBy(max(Double(content.lateMinutes ?? 0) * 60, now.timeIntervalSince(leaveBy)))
        }
        guard let minutes = content.lateMinutes else {
            return isHistorical ? String(localized: "Was running late") : String(localized: "Running late")
        }
        let seconds = Double(minutes) * 60
        return isHistorical ? String(localized: "Was late by \(TimeText.duration(seconds))") : TripText.lateBy(seconds)
    }

    /// The main countdown, only while its target is still ahead of the clock.
    var countdown: Countdown? {
        switch phase {
        case .idle, .finished, .paused: return nil
        case .driving:
            guard let eta = content.eta, eta > now else { return nil }
            return Countdown(label: String(localized: "Arrive in"), target: eta)
        case .atStop:
            // At a stop the clock that matters is the light: how long the window has left. Leave-by stays in `clockLine`.
            if let end = content.windowEnd, end.timeIntervalSince(now) > TripText.nowTolerance {
                let label = content.windowKind.map { String(localized: "\(LightText.name($0)) ends in") } ?? String(localized: "Window ends in")
                return Countdown(label: label, target: end)
            }
            guard let leaveBy = content.leaveBy, leaveBy.timeIntervalSince(now) > TripText.nowTolerance else { return nil }
            return Countdown(label: String(localized: "Leave in"), target: leaveBy)
        case .armed, .betweenStops:
            guard let leaveBy = content.leaveBy, leaveBy.timeIntervalSince(now) > TripText.nowTolerance else { return nil }
            return Countdown(label: String(localized: "Leave in"), target: leaveBy)
        }
    }

    /// "Leave by 17:40" or "Arrive 17:42": the same fact as the countdown in clock time.
    var clockLine: String? {
        switch phase {
        case .idle, .finished, .paused: return nil
        case .driving:
            return content.eta.map { TripText.arrive($0, in: zone) }
        case .armed, .betweenStops, .atStop:
            guard let leaveBy = content.leaveBy, leaveBy.timeIntervalSince(now) > TripText.nowTolerance else { return nil }
            return TripText.leaveBy(leaveBy, now: now, in: zone)
        }
    }

    /// "Sunset 18:14"
    var windowLine: String? {
        guard let kind = content.windowKind, let start = content.windowStart else { return nil }
        return "\(LightText.shortName(kind)) \(TimeText.time(start, in: zone))"
    }

    /// The short label beside the window symbol in the compact island.
    var shortLabel: String {
        // Old data never sounds current: no "Late", no countdown word.
        if isHistorical, !isIdle, !isFinished { return String(localized: "Old") }
        switch phase {
        case .idle: return String(localized: "Iter")
        case .finished: return String(localized: "Done")
        case .paused: return String(localized: "Paused")
        case .driving: return content.status == .late || content.status == .missed ? String(localized: "Late") : String(localized: "Arrive")
        case .armed, .betweenStops, .atStop: return status?.tone == .warning ? String(localized: "Late") : String(localized: "Leave")
        }
    }

    // MARK: Score

    var score: Int? { content.liveScore ?? content.forecastScore }
    var scoreIsLive: Bool { content.liveScore != nil }
    var isLowConfidence: Bool { content.confidence == .low }
    /// "Live" only while the reading is current; an old or offline reading says when it was taken, never "Live".
    var scoreKindWord: String? {
        guard score != nil else { return nil }
        if !scoreIsLive { return String(localized: "Forecast") }
        // Sample data is never "Live".
        if content.isSampleData == true { return String(localized: "Sample") }
        if isDim {
            let t = TimeText.time(content.dataAsOf, in: zone)
            return String(localized: "As of \(t)")
        }
        return String(localized: "Live")
    }

    /// The word above the live score in the expanded island.
    var liveColumnTitle: String { content.isSampleData == true ? String(localized: "Sample") : isDim ? String(localized: "Last reading") : String(localized: "Live") }

    /// A chip for an old reading is visibly weaker (derived from the low-confidence token, twice over).
    var chipOpacity: Double {
        var o = isLowConfidence ? IterEvent.lowConfidenceOpacity : 1
        if isDim { o *= IterEvent.lowConfidenceOpacity * IterEvent.lowConfidenceOpacity * 0.85 }
        return o
    }

    // MARK: Age

    var age: TimeInterval { max(0, now.timeIntervalSince(content.dataAsOf)) }
    var isOld: Bool { age > Self.oldAfter }
    /// The numbers should not be read as current.
    var isDim: Bool { isStale || isOld || content.isOffline }

    /// "As of 16:10", "Updated 3 hr ago", "Offline", "Offline · as of 16:10". nil when the data is fresh and online.
    var ageText: String? {
        // A finished or idle run has nothing live to be old about.
        if isIdle || isFinished { return nil }
        var parts: [String] = []
        if content.isOffline { parts.append(String(localized: "Offline")) }
        if isOld || isStale {
            if age <= Self.clockTimeUntil || (isHistorical && status?.tone == .warning) {
                let t = TimeText.time(content.dataAsOf, in: zone)
                parts.append(parts.isEmpty ? String(localized: "As of \(t)") : String(localized: "as of \(t)"))
            } else {
                let d = TimeText.duration(max(3600, (age / 3600).rounded() * 3600))
                parts.append(String(localized: "Updated \(d) ago"))
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// A duration in words, the same text `Text(date, style: .relative)` draws while it counts on its own:
    /// "2 hr, 54 min" from an hour up (minutes rounded down), "21 min, 4 sec" below it, "58 sec" under a minute.
    static func durationWords(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        let units: Set<Duration.UnitsFormatStyle.Unit> = s >= 3600 ? [.hours, .minutes] : [.minutes, .seconds]
        let rounded = s >= 3600 ? s / 60 * 60 : s
        if rounded == 0 { return Duration.seconds(0).formatted(.units(allowed: [.seconds], width: .abbreviated, zeroValueUnits: .show(length: 1))) }
        return Duration.seconds(rounded).formatted(.units(allowed: units, width: .abbreviated, maximumUnitCount: 2, zeroValueUnits: .hide))
    }

    // MARK: Accessibility

    var accessibilityText: String {
        var parts = [title]
        if let status { parts.append(status.text) }
        if let countdown { parts.append("\(countdown.label) \(Self.durationWords(countdown.target.timeIntervalSince(now)))") }
        if let clockLine { parts.append(clockLine) }
        if let windowLine { parts.append(windowLine) }
        if let score { parts.append(String(localized: "Score \(score)")) }
        if let ageText { parts.append(ageText) }
        return parts.joined(separator: ". ")
    }
}
