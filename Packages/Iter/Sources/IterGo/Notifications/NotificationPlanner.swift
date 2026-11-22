import Foundation
import IterModel
import IterPlan

/// Decides which notifications should exist. Pure: plain data in, a `NotificationPlan` out (BLUEPRINT §10.4, D9, D12).
///
/// Without push and without the time-sensitive entitlement, everything the user must hear while the app is suspended is
/// scheduled ahead as a local notification with a stable id (so a re-plan replaces it); only what cannot be known ahead
/// (traffic pushed leave-by into the past, a late arrival, a conditions change) is delivered at once, and quietly.
public enum NotificationPlanner {
    /// iOS keeps 64 pending requests; stay under it.
    public static let maxPending = 50
    /// At most one immediate notification per this many seconds.
    public static let immediateGap: TimeInterval = 90
    public static let lateThreshold: TimeInterval = 5 * 60
    public static let stayCheckLead: TimeInterval = 15 * 60
    /// A pending request that moved by less than this, with the same text, is left alone.
    public static let keepTolerance: TimeInterval = 60
    public static let conditionsQuietPeriod: TimeInterval = 3600

    private struct Candidate {
        var priority: Int
        var request: GoNotificationRequest
        var shortLine: String
        var conditionsStop: UUID?
    }

    public static func plan(_ input: NotificationPlanInput, ledger old: NotificationLedger) -> NotificationPlan {
        switch input.phase {
        case .idle, .finished:
            return NotificationPlan(pending: [], immediate: [], ledger: NotificationLedger(), removeAll: true)
        case .paused:
            var kept = old
            kept.scheduled = [:]
            return NotificationPlan(pending: [], immediate: [], ledger: kept, removeAll: true)
        case .armed, .driving, .atStop, .betweenStops:
            break
        }

        let now = input.now
        var ledger = old
        ledger.settle(now: now)

        let next = input.nextStop
        let driving = input.phase == .driving
        let target: UUID? = driving ? (input.targetStopID ?? next?.stopID) : nil
        let stayConflict = input.phase == .atStop && input.stay?.cutsShortBySeconds != nil
        let drivingToNext = driving && next != nil && target == next?.stopID
        let fallbackZone = next?.timeZone ?? TimeZone(identifier: "UTC") ?? .current

        // MARK: pending

        var wanted: [GoNotificationRequest] = []
        for alarm in input.alarms where alarm.fireAt > now {
            if let target, alarm.stopID == target { continue }
            if stayConflict, alarm.stopID == next?.stopID { continue }
            // Each alarm rings once per run: a leave-by that later moves does not re-ring an alarm that already went out.
            if ledger.delivered[alarm.id] != nil { continue }
            wanted.append(request(for: alarm, input: input, zone: input.timeZones[alarm.stopID] ?? fallbackZone))
        }

        var candidates: [Candidate] = []

        if let next, input.phase == .atStop, let stay = input.stay, let cut = stay.cutsShortBySeconds, let latest = stay.latestDeparture {
            let id = GoNotificationKind.stayCheck.id(for: next.stopID)
            if ledger.delivered[id] == nil {
                let fireAt = latest.addingTimeInterval(-stayCheckLead)
                let name = stay.nextStopName ?? next.name
                let label = (stay.nextWindowKind ?? next.windowKind).map { "to make \(GoNotificationText.label($0)) at \(name)" } ?? "to make \(name)"
                let body = "Leave by \(GoNotificationText.time(latest, next.timeZone)) \(label): \(GoNotificationText.minutes(cut)) before this window ends."
                var req = make(.stayCheck, stopID: next.stopID, input: input, fireAt: fireAt > now ? fireAt : nil,
                               title: "Plan to leave for \(name)", body: body, category: GoNotificationCategory.info)
                if fireAt > now {
                    wanted.append(req)
                } else if latest > now {
                    req.fireAt = nil
                    candidates.append(Candidate(priority: 3, request: req, shortLine: "Leave by \(GoNotificationText.time(latest, next.timeZone)) for \(name)"))
                }
            }
        }

        wanted.sort { ($0.fireAt ?? .distantPast, $0.id) < ($1.fireAt ?? .distantPast, $1.id) }
        if wanted.count > maxPending { wanted = Array(wanted.prefix(maxPending)) }

        // Keep requests that barely moved and read the same.
        for index in wanted.indices {
            guard let fireAt = wanted[index].fireAt, let before = ledger.scheduled[wanted[index].id] else { continue }
            if abs(before.fireAt.timeIntervalSince(fireAt)) < keepTolerance, before.contentHash == wanted[index].contentHash {
                wanted[index].fireAt = before.fireAt
            }
        }
        ledger.scheduled = Dictionary(wanted.compactMap { r in r.fireAt.map { (r.id, NotificationLedger.Scheduled(fireAt: $0, contentHash: r.contentHash)) } },
                                      uniquingKeysWith: { first, _ in first })

        // MARK: immediate candidates

        if let arrival = input.arrival {
            let id = GoNotificationKind.arrival.id(for: arrival.stopID)
            if ledger.delivered[id] == nil {
                var info = ["stopID": arrival.stopID.uuidString]
                if let expires = arrival.undoExpiresAt { info["undoExpiresAt"] = String(expires.timeIntervalSince1970) }
                let req = make(.arrival, stopID: arrival.stopID, input: input, fireAt: nil, title: "Arrived at \(arrival.stopName)",
                               body: "Trip mode moved on to \(arrival.stopName). Tap Not yet if you are not there.",
                               category: GoNotificationCategory.arrival, extra: info)
                candidates.append(Candidate(priority: 0, request: req, shortLine: "Arrived at \(arrival.stopName)"))
            }
        }

        if let next, !stayConflict {
            let lateID = GoNotificationKind.late.id(for: next.stopID)
            let missedID = GoNotificationKind.missed.id(for: next.stopID)
            let leaveNowID = GoNotificationKind.leaveNow.id(for: next.stopID)
            let alt = next.alternativeName.map { " Alternative: \($0)." } ?? ""
            switch next.status {
            case .late:
                if let late = next.lateBySeconds, late >= lateThreshold, ledger.delivered[lateID] == nil {
                    var body = drivingToNext ? "Running \(GoNotificationText.minutes(late)) late for \(next.name)" : "Leaving now puts you \(GoNotificationText.minutes(late)) late for \(next.name)"
                    var details: [String] = []
                    if let arrive = next.projectedArrival { details.append("arrive \(GoNotificationText.time(arrive, next.timeZone))") }
                    if let setUp = next.setUpBy { details.append("set-up \(GoNotificationText.time(setUp, next.timeZone))") }
                    if !details.isEmpty { body += ": " + details.joined(separator: ", ") }
                    body += "." + alt
                    let req = make(.late, stopID: next.stopID, input: input, fireAt: nil, title: "Running late for \(next.name)", body: body,
                                   category: GoNotificationCategory.navigate)
                    candidates.append(Candidate(priority: 1, request: req, shortLine: "\(GoNotificationText.minutes(late)) late for \(next.name)"))
                }
            case .missed:
                if ledger.delivered[missedID] == nil {
                    let req = make(.missed, stopID: next.stopID, input: input, fireAt: nil, title: "Missed the light at \(next.name)",
                                   body: "The window at \(next.name) will be over before you can set up." + alt, category: GoNotificationCategory.info)
                    candidates.append(Candidate(priority: 1, request: req, shortLine: "Missed \(next.name)"))
                }
            case .leaveNow:
                let futureAlarm = input.alarms.contains { $0.id == leaveNowID && $0.fireAt > now }
                if !futureAlarm, !drivingToNext, ledger.delivered[leaveNowID] == nil {
                    let req = make(.leaveNow, stopID: next.stopID, input: input, fireAt: nil, title: "Time to leave for \(next.name)",
                                   body: leaveBody(now: true, name: next.name, leaveBy: next.leaveBy, drive: next.driveSeconds, kind: next.windowKind,
                                                   start: next.windowStart, zone: next.timeZone), category: GoNotificationCategory.navigate)
                    candidates.append(Candidate(priority: 2, request: req, shortLine: "Leave now for \(next.name)"))
                }
            default:
                break
            }
        }

        var seenStops = Set<UUID>()
        for notice in input.conditionsAlerts where seenStops.insert(notice.stopID).inserted {
            if let last = ledger.conditionsLast[notice.stopID.uuidString], now.timeIntervalSince(last) < conditionsQuietPeriod { continue }
            let zoneLabel = notice.windowKind.map { GoNotificationText.label($0).capitalizedFirst } ?? "Conditions"
            var body = "\(zoneLabel) at \(notice.stopName) now \(notice.current) (was \(notice.previous))"
            if let cause = notice.cause, !cause.isEmpty { body += ": \(cause)" }
            let req = make(.conditionsChanged, stopID: notice.stopID, input: input, fireAt: nil,
                           title: notice.current > notice.previous ? "Better light at \(notice.stopName)" : "Light changing at \(notice.stopName)",
                           body: body, category: GoNotificationCategory.info)
            candidates.append(Candidate(priority: 4, request: req, shortLine: "\(notice.stopName) now \(notice.current)", conditionsStop: notice.stopID))
        }

        // MARK: the quiet rule

        var immediate: [GoNotificationRequest] = []
        let gapOpen = ledger.lastImmediateAt.map { now.timeIntervalSince($0) >= immediateGap } ?? true
        if gapOpen, !candidates.isEmpty {
            let ordered = candidates.enumerated().sorted { ($0.element.priority, $0.offset) < ($1.element.priority, $1.offset) }.map(\.element)
            var winner = ordered[0].request
            let others = ordered.dropFirst()
            if !others.isEmpty { winner.body += "\n" + others.map(\.shortLine).joined(separator: "; ") }
            immediate = [winner]
            for c in ordered {
                ledger.delivered[c.request.id] = now
                if let stop = c.conditionsStop { ledger.conditionsLast[stop.uuidString] = now }
            }
            ledger.lastImmediateAt = now
        }

        return NotificationPlan(pending: wanted, immediate: immediate, ledger: ledger, removeAll: false)
    }

    // MARK: building

    private static func make(_ kind: GoNotificationKind, stopID: UUID, input: NotificationPlanInput, fireAt: Date?, title: String, body: String,
                             category: String, extra: [String: String] = [:]) -> GoNotificationRequest {
        var info = ["stopID": stopID.uuidString, "tripID": input.tripID.uuidString, "kind": kind.rawValue]
        info.merge(extra) { _, new in new }
        return GoNotificationRequest(id: kind.id(for: stopID), kind: kind, stopID: stopID, tripID: input.tripID, fireAt: fireAt, title: title,
                                     body: body, categoryID: category, threadID: input.tripID.uuidString, userInfo: info)
    }

    private static func request(for alarm: PlannedAlarm, input: NotificationPlanInput, zone: TimeZone) -> GoNotificationRequest {
        let kind: GoNotificationKind = alarm.kind == .leaveSoon ? .leaveSoon : .leaveNow
        let isNow = kind == .leaveNow
        let body = leaveBody(now: isNow, name: alarm.stopName, leaveBy: alarm.leaveBy, drive: alarm.driveSeconds, kind: alarm.windowKind,
                             start: alarm.windowStart, zone: zone)
        var req = make(kind, stopID: alarm.stopID, input: input, fireAt: alarm.fireAt,
                       title: isNow ? "Time to leave for \(alarm.stopName)" : "Leave soon for \(alarm.stopName)", body: body,
                       category: isNow ? GoNotificationCategory.navigate : GoNotificationCategory.info)
        req.id = alarm.id
        return req
    }

    private static func leaveBody(now: Bool, name: String, leaveBy: Date?, drive: TimeInterval?, kind: LightWindowKind?, start: Date?,
                                  zone: TimeZone) -> String {
        var s: String
        if now {
            s = "Leave now for \(name)"
        } else if let leaveBy {
            s = "Leave by \(GoNotificationText.time(leaveBy, zone)) for \(name)"
        } else {
            s = "Leave soon for \(name)"
        }
        var details: [String] = []
        if let drive { details.append("\(GoNotificationText.driveText(drive)) drive") }
        if let kind, let start { details.append("\(GoNotificationText.label(kind)) \(GoNotificationText.time(start, zone))") }
        if !details.isEmpty { s += ": " + details.joined(separator: ", ") }
        return s
    }
}

/// Wording helpers.
enum GoNotificationText {
    static func time(_ date: Date, _ zone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// "12 min", whole minutes (rounded) so seconds of ETA drift never change the text.
    static func minutes(_ seconds: TimeInterval) -> String { "\(max(0, Int((seconds / 60).rounded()))) min" }

    static func driveText(_ seconds: TimeInterval) -> String {
        let m = max(0, Int((seconds / 60).rounded()))
        return m < 60 ? "\(m) min" : "\(m / 60) h \(m % 60) min"
    }

    static func label(_ kind: LightWindowKind) -> String {
        switch kind {
        case .goldenEvening: "sunset"
        case .goldenMorning: "sunrise"
        case .blueEvening, .blueMorning: "blue hour"
        case .night: "night sky"
        }
    }
}

extension String {
    fileprivate var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
