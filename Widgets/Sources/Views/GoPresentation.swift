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
        self.zone = zone
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
            return (String(localized: "Window missed"), .warning)
        case .late:
            return (lateText, .warning)
        case .leaveNow where phase != .driving:
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

    private var lateText: String {
        var seconds = content.lateMinutes.map { Double($0) * 60 }
        if phase != .driving, let leaveBy = content.leaveBy, now > leaveBy {
            seconds = max(seconds ?? 0, now.timeIntervalSince(leaveBy))
        }
        guard let seconds else { return String(localized: "Running late") }
        return TripText.lateBy(seconds)
    }

    /// The main countdown, only while its target is still ahead of the clock.
    var countdown: Countdown? {
        switch phase {
        case .idle, .finished, .paused: return nil
        case .driving:
            guard let eta = content.eta, eta > now else { return nil }
            return Countdown(label: String(localized: "Arrive in"), target: eta)
        case .armed, .betweenStops, .atStop:
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
        switch phase {
        case .idle: String(localized: "Iter")
        case .finished: String(localized: "Done")
        case .paused: String(localized: "Paused")
        case .driving: content.status == .late || content.status == .missed ? String(localized: "Late") : String(localized: "Arrive")
        case .armed, .betweenStops, .atStop:
            status?.tone == .warning ? String(localized: "Late") : String(localized: "Leave")
        }
    }

    // MARK: Score

    var score: Int? { content.liveScore ?? content.forecastScore }
    var scoreIsLive: Bool { content.liveScore != nil }
    var isLowConfidence: Bool { content.confidence == .low }
    var scoreKindWord: String? {
        guard score != nil else { return nil }
        return scoreIsLive ? String(localized: "Live") : String(localized: "Forecast")
    }

    // MARK: Age

    var age: TimeInterval { max(0, now.timeIntervalSince(content.dataAsOf)) }
    var isOld: Bool { age > Self.oldAfter }
    /// The numbers should not be read as current.
    var isDim: Bool { isStale || isOld || content.isOffline }

    /// "As of 16:10", "Updated 3 hr ago", "Offline", "Offline · as of 16:10". nil when the data is fresh and online.
    var ageText: String? {
        var parts: [String] = []
        if content.isOffline { parts.append(String(localized: "Offline")) }
        if isOld || isStale {
            if age <= Self.clockTimeUntil {
                let t = TimeText.time(content.dataAsOf, in: zone)
                parts.append(parts.isEmpty ? String(localized: "As of \(t)") : String(localized: "as of \(t)"))
            } else {
                let d = TimeText.duration(max(3600, (age / 3600).rounded() * 3600))
                parts.append(String(localized: "Updated \(d) ago"))
            }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// A countdown frozen at `now`: "1:24:10", "24:10".
    static func frozen(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds.rounded(.down)))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
    }

    // MARK: Accessibility

    var accessibilityText: String {
        var parts = [title]
        if let status { parts.append(status.text) }
        if let countdown { parts.append("\(countdown.label) \(Self.frozen(countdown.target.timeIntervalSince(now)))") }
        if let clockLine { parts.append(clockLine) }
        if let windowLine { parts.append(windowLine) }
        if let score { parts.append(String(localized: "Score \(score)")) }
        if let ageText { parts.append(ageText) }
        return parts.joined(separator: ". ")
    }
}
