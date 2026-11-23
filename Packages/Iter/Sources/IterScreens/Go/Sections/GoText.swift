import Foundation
import IterModel
import IterGoActivity
import IterUI

/// Every sentence the Go sections show, as pure functions of the snapshot, so tests check words without rendering.
/// Times are in the stop's own zone; `locale` is explicit so tests are deterministic.
public enum GoText {
    // MARK: Zones and small helpers

    public static func zone(for stop: GoStopInfo?) -> TimeZone {
        stop.flatMap { TimeZone(identifier: $0.timeZoneIdentifier) } ?? .current
    }

    /// The stop the conditions are about: the one `sky.stopID` names (the current stop while shooting, else the next), falling
    /// back to the one you are heading to, then the one you are at.
    public static func subjectStop(_ s: GoSnapshot) -> GoStopInfo? {
        if let id = s.sky?.stopID {
            if let c = s.current, c.id == id { return c }
            if let n = s.next, n.id == id { return n }
        }
        return s.next ?? s.current
    }

    static func time(_ d: Date, _ zone: TimeZone, _ locale: Locale) -> String { TimeText.time(d, in: zone, locale: locale) }

    /// Whole minutes, at least one: "6 min", "1 hr, 5 min".
    static func minutes(_ seconds: TimeInterval, _ locale: Locale) -> String {
        TimeText.duration(max(60, seconds), locale: locale)
    }

    /// "in 42 min", "in 1 hr, 5 min".
    public static func inTime(_ seconds: TimeInterval, locale: Locale = .current) -> String {
        let d = minutes(seconds, locale)
        return String(localized: "in \(d)", locale: locale, comment: "Countdown: in 42 min")
    }

    /// "8 min ago", "3 hr ago", "just now".
    public static func ago(_ date: Date, now: Date, locale: Locale = .current) -> String {
        let s = now.timeIntervalSince(date)
        if s < 60 { return String(localized: "just now", locale: locale, comment: "Data age under a minute") }
        let d = TimeText.duration(s, locale: locale)
        return String(localized: "\(d) ago", locale: locale, comment: "Data age, e.g. 8 min ago")
    }

    // MARK: Hero kind

    public enum HeroKind: Hashable, Sendable { case beforeDeparture, driving, atStop, paused }

    public static func heroKind(_ s: GoSnapshot) -> HeroKind? {
        switch s.phase {
        case .armed, .betweenStops: s.next == nil ? nil : .beforeDeparture
        case .driving: s.next == nil ? nil : .driving
        case .atStop: s.current == nil ? nil : .atStop
        case .paused: .paused
        case .idle, .finished: nil
        }
    }

    // MARK: Before departure

    /// "Leave by 17:05" (the very large line), or "Leave when ready" when no time binds the stop.
    public static func leaveHeadline(_ s: GoSnapshot, locale: Locale = .current) -> String {
        guard let by = s.leave?.leaveBy else { return String(localized: "Leave when ready", locale: locale, comment: "Hero: no departure time binds the stop") }
        let t = time(by, zone(for: s.next), locale)
        return String(localized: "Leave by \(t)", locale: locale, comment: "Hero: latest departure")
    }

    public enum LeaveTone: Hashable, Sendable { case normal, now, late }

    /// How old a snapshot must be before the hero stops sounding certain.
    public static let oldAfter: TimeInterval = 15 * 60

    /// When the values on the card were last good, if that is longer ago than `oldAfter`: the snapshot's own time, or a stale ETA's.
    public static func staleSince(_ s: GoSnapshot, now: Date) -> Date? {
        if now.timeIntervalSince(s.generatedAt) >= oldAfter { return s.generatedAt }
        if s.freshness.etaIsStale, let a = s.freshness.etaAsOf ?? s.drive?.asOf, now.timeIntervalSince(a) >= oldAfter { return a }
        return nil
    }

    /// First line of the hero when its numbers are old: "As of 13:30 · 3 hr old".
    public static func staleBanner(_ s: GoSnapshot, now: Date, locale: Locale = .current) -> String? {
        guard let since = staleSince(s, now: now) else { return nil }
        let t = time(since, zone(for: subjectStop(s)), locale)
        let d = TimeText.duration(now.timeIntervalSince(since), locale: locale)
        return String(localized: "As of \(t) · \(d) old", locale: locale, comment: "Hero: the values on this card are old")
    }

    /// The countdown under the headline and its tone: "in 42 min", "Leave now", "6 min late", "26 min past leave-by".
    /// The words come from `now` against the stored leave-by, never from an old status.
    public static func leaveCountdown(_ s: GoSnapshot, now: Date, locale: Locale = .current) -> (text: String, tone: LeaveTone)? {
        guard let leave = s.leave else { return nil }
        let fresh = staleSince(s, now: now) == nil
        if leave.status == .missed, fresh {
            return (String(localized: "Window over", locale: locale, comment: "Hero: the light is gone"), .late)
        }
        if let by = leave.leaveBy {
            let delta = by.timeIntervalSince(now)
            if delta > TripText.nowTolerance { return (inTime(delta, locale: locale), .normal) }
            if delta >= -TripText.nowTolerance { return (String(localized: "Leave now", locale: locale, comment: "Hero: leave now"), .now) }
            if leave.status == .late, fresh {
                let m = minutes(leave.lateBySeconds ?? -delta, locale)
                return (String(localized: "\(m) late", locale: locale, comment: "Hero: 6 min late"), .late)
            }
            let m = minutes(-delta, locale)
            return (String(localized: "\(m) past leave-by", locale: locale, comment: "Hero: leave-by has passed"), .late)
        }
        switch leave.status {
        case .leaveNow: return (String(localized: "Leave now", locale: locale), .now)
        case .late:
            let m = minutes(leave.lateBySeconds ?? 60, locale)
            return (String(localized: "\(m) late", locale: locale), .late)
        default: return nil
        }
    }

    /// "Live traffic", "Planned drive", "Offline estimate".
    public static func etaQuality(_ source: GoETASource, locale: Locale = .current) -> String {
        switch source {
        case .live: String(localized: "Live traffic", locale: locale, comment: "ETA quality")
        case .planned: String(localized: "Planned drive", locale: locale, comment: "ETA quality")
        case .offlineEstimate: String(localized: "Offline estimate", locale: locale, comment: "ETA quality")
        }
    }

    public static func etaQualitySymbol(_ source: GoETASource) -> String {
        switch source {
        case .live: "car.fill"
        case .planned: "map"
        case .offlineEstimate: "wifi.slash"
        }
    }

    /// "1 hr, 20 min · 94 mi", or the duration alone when the distance is unknown.
    public static func driveLine(_ drive: GoDriveInfo, locale: Locale = .current) -> String {
        if let m = drive.driveMeters { return TripText.drive(seconds: drive.driveSeconds, meters: m, locale: locale) }
        return TimeText.duration(drive.driveSeconds, locale: locale)
    }

    /// "Arrive 17:53 · 28 min before sunset", "Arrive 17:53 · 6 min after set-up", or just "Arrive 17:53" with no window.
    public static func arrivalAgainstLight(_ s: GoSnapshot, locale: Locale = .current) -> String? {
        guard let next = s.next, let arrival = s.drive?.arrival else { return nil }
        let z = zone(for: next)
        let base = TripText.arrive(arrival, in: z, locale: locale)
        guard let kind = next.windowKind, let rel = relationToLight(arrival: arrival, next: next, kind: kind, locale: locale) else { return base }
        return "\(base) · \(rel)"
    }

    static func relationToLight(arrival: Date, next: GoStopInfo, kind: LightWindowKind, locale: Locale) -> String? {
        let name = LightText.name(kind).lowercased()
        if let setUp = next.setUpBy, arrival.timeIntervalSince(setUp) > TripText.nowTolerance {
            let m = minutes(arrival.timeIntervalSince(setUp), locale)
            return String(localized: "\(m) after set-up", locale: locale, comment: "Arrival after the set-up time")
        }
        guard let start = next.windowStart ?? next.setUpBy else { return nil }
        let delta = start.timeIntervalSince(arrival)
        if delta > TripText.nowTolerance {
            let m = minutes(delta, locale)
            return String(localized: "\(m) before \(name)", locale: locale, comment: "Arrival before the light window, e.g. 28 min before sunset")
        }
        return String(localized: "In time for \(name)", locale: locale, comment: "Arrival just in time for the light window")
    }

    /// "Drive tonight: leave after 20:10".
    public static func eveningBefore(_ s: GoSnapshot, locale: Locale = .current) -> String? {
        guard let d = s.leave?.suggestedDeparture else { return nil }
        let t = time(d, zone(for: s.next), locale)
        return String(localized: "Drive tonight: leave after \(t)", locale: locale, comment: "Evening Before transfer suggestion")
    }

    /// "Free to leave from 17:40".
    public static func earliestDeparture(_ s: GoSnapshot, now: Date, locale: Locale = .current) -> String? {
        guard let d = s.leave?.earliestDeparture, d > now else { return nil }
        let t = time(d, zone(for: s.current ?? s.next), locale)
        return String(localized: "Earliest you can leave: \(t)", locale: locale, comment: "Earliest departure hint")
    }

    /// The status word beside the card heading. An old snapshot claims nothing ("On time" is never said from old data);
    /// it only says so when leave-by has passed.
    public static func statusWord(_ s: GoSnapshot, now: Date, locale: Locale = .current) -> (text: String, symbol: String, tone: LeaveTone)? {
        guard let status = s.leave?.status else { return nil }
        if staleSince(s, now: now) != nil {
            if let by = s.leave?.leaveBy, now.timeIntervalSince(by) > TripText.nowTolerance {
                return (String(localized: "Past leave-by", locale: locale), "exclamationmark.triangle.fill", .late)
            }
            return nil
        }
        switch status {
        case .early: return (String(localized: "On time", locale: locale), "checkmark.circle", .normal)
        case .leaveSoon: return (String(localized: "Leave soon", locale: locale), "clock", .normal)
        case .leaveNow: return (String(localized: "Leave now", locale: locale), "car.fill", .now)
        case .late: return (String(localized: "Running late", locale: locale), "exclamationmark.triangle.fill", .late)
        case .missed: return (String(localized: "Missed", locale: locale), "exclamationmark.triangle.fill", .late)
        case .atStop, .unscheduled: return nil
        }
    }

    // MARK: Driving

    /// "Arrive 17:42" (the very large line).
    public static func arriveHeadline(_ s: GoSnapshot, locale: Locale = .current) -> String {
        guard let a = s.drive?.arrival else { return String(localized: "Arrival unknown", locale: locale, comment: "Hero: no ETA") }
        return TripText.arrive(a, in: zone(for: s.next), locale: locale)
    }

    /// "in 38 min".
    public static func arriveCountdown(_ s: GoSnapshot, now: Date, locale: Locale = .current) -> String? {
        guard let a = s.drive?.arrival else { return nil }
        let delta = a.timeIntervalSince(now)
        if delta < -TripText.nowTolerance {
            let m = minutes(-delta, locale)
            return String(localized: "\(m) past ETA", locale: locale, comment: "Driving: the estimate has passed")
        }
        if delta <= TripText.nowTolerance { return String(localized: "Arriving now", locale: locale) }
        return inTime(delta, locale: locale)
    }

    /// On time / late / missed against the light.
    public static func drivingStatus(_ s: GoSnapshot, locale: Locale = .current) -> (text: String, symbol: String, tone: LeaveTone) {
        let kindName = s.next?.windowKind.map { LightText.name($0) }
        switch s.leave?.status {
        case .missed:
            let n = kindName ?? String(localized: "The light", locale: locale)
            return (String(localized: "\(n) over on arrival", locale: locale, comment: "Driving: the window will be over"), "exclamationmark.triangle.fill", .late)
        case .late:
            let m = minutes(s.leave?.lateBySeconds ?? 60, locale)
            return (String(localized: "\(m) after set-up", locale: locale, comment: "Driving: arrive after the set-up time"), "exclamationmark.triangle.fill", .late)
        default:
            if let line = arrivalAgainstLight(s, locale: locale), let rel = line.components(separatedBy: " · ").dropFirst().first {
                return (rel.prefix(1).uppercased() + rel.dropFirst(), "checkmark.circle", .normal)
            }
            return (String(localized: "On time", locale: locale), "checkmark.circle", .normal)
        }
    }

    /// "Next best: Dead Horse Point" and "Evening Blue Hour 18:20 · arrive 18:05".
    public static func alternative(_ s: GoSnapshot, locale: Locale = .current) -> (title: String, detail: String)? {
        guard let alt = s.alternative else { return nil }
        let z = zone(for: s.next)
        let title = String(localized: "Next best: \(alt.name)", locale: locale, comment: "Driving: the alternative stop")
        let arrive = time(alt.projectedArrival, z, locale)
        let start = time(alt.windowStart, z, locale)
        let detail: String
        if let k = alt.windowKind {
            let n = LightText.name(k)
            detail = String(localized: "\(n) \(start) · arrive \(arrive)", locale: locale, comment: "Alternative stop: window, start and arrival")
        } else {
            detail = String(localized: "Light \(start) · arrive \(arrive)", locale: locale)
        }
        return (title, detail)
    }

    // MARK: At a stop

    /// "Sunset · 23 min left", "Sunset · over" or nil with no window.
    public static func windowLeft(_ s: GoSnapshot, now: Date, locale: Locale = .current) -> String? {
        guard let kind = s.current?.windowKind ?? s.sky?.windowKind else { return nil }
        let name = LightText.name(kind)
        guard let end = s.current?.windowEnd ?? s.sky?.windowEnd else { return name }
        let left = end.timeIntervalSince(now)
        if left <= 30 { return String(localized: "\(name) · over", locale: locale, comment: "At a stop: the light window has ended") }
        let m = minutes(left, locale)
        return String(localized: "\(name) · \(m) left", locale: locale, comment: "At a stop: time left in the window")
    }

    /// The cost of staying. `warns` only when it cuts this window short.
    public static func stayCost(_ s: GoSnapshot, locale: Locale = .current) -> (text: String, warns: Bool)? {
        guard let stay = s.stay else { return nil }
        let z = zone(for: s.current ?? s.next)
        if let cut = stay.cutsShortBySeconds, cut >= 60, let latest = stay.latestDeparture {
            let t = time(latest, z, locale)
            let m = minutes(cut, locale)
            if let name = stay.nextStopName {
                if let k = stay.nextWindowKind {
                    let w = LightText.name(k).lowercased()
                    return (String(localized: "Leave by \(t) to make \(w) at \(name), \(m) before this window ends", locale: locale,
                                   comment: "Stay cost: leaving early for the next stop"), true)
                }
                return (String(localized: "Leave by \(t) to make \(name), \(m) before this window ends", locale: locale), true)
            }
            return (String(localized: "Leave by \(t) to make the next stop, \(m) before this window ends", locale: locale), true)
        }
        if let planned = stay.plannedDeparture {
            let t = time(planned, z, locale)
            return (String(localized: "Shoot until \(t) as planned", locale: locale, comment: "Stay cost: the plan fits"), false)
        }
        return nil
    }

    // MARK: Paused

    public static let pausedTitle = String(localized: "Trip mode paused")

    /// What is next while paused: "Next: Delicate Arch · leave by 17:05".
    public static func pausedDetail(_ s: GoSnapshot, locale: Locale = .current) -> String? {
        if let next = s.next {
            if let by = s.leave?.leaveBy {
                let t = time(by, zone(for: next), locale)
                return String(localized: "Next: \(next.name) · leave by \(t)", locale: locale, comment: "Paused: what is next")
            }
            return String(localized: "Next: \(next.name)", locale: locale)
        }
        if let cur = s.current { return String(localized: "At \(cur.name)", locale: locale) }
        return nil
    }

    // MARK: Conditions

    public static func conditionsTitle(_ s: GoSnapshot, locale: Locale = .current) -> String {
        if let n = subjectStop(s)?.name { return String(localized: "Conditions at \(n)", locale: locale, comment: "Section title") }
        return String(localized: "Conditions", locale: locale)
    }

    public static func bandWord(_ b: GoBand, locale: Locale = .current) -> String {
        switch b {
        case .poor: String(localized: "Poor", locale: locale, comment: "Sky band")
        case .fair: String(localized: "Fair", locale: locale, comment: "Sky band")
        case .good: String(localized: "Good", locale: locale, comment: "Sky band")
        case .great: String(localized: "Great", locale: locale, comment: "Sky band")
        case .epic: String(localized: "Epic", locale: locale, comment: "Sky band")
        }
    }

    /// "Rising", "Steady", "Falling"; nil when unknown.
    public static func trendWord(_ t: GoTrend, locale: Locale = .current) -> String? {
        switch t {
        case .rising: String(localized: "Rising", locale: locale, comment: "Sky trend")
        case .steady: String(localized: "Steady", locale: locale, comment: "Sky trend")
        case .falling: String(localized: "Falling", locale: locale, comment: "Sky trend")
        case .unknown: nil
        }
    }

    public static func trendSymbol(_ t: GoTrend) -> String? {
        switch t {
        case .rising: "arrow.up.right"
        case .steady: "arrow.right"
        case .falling: "arrow.down.right"
        case .unknown: nil
        }
    }

    /// A sky reading older than this is no longer "live".
    public static let skyOldAfter: TimeInterval = 30 * 60

    public static func skyIsOld(_ sky: GoSkyInfo, now: Date) -> Bool {
        guard sky.basis != .nextWindowForecast, sky.basis != .noData else { return false }
        if sky.isStale { return true }
        if let a = sky.asOf, now.timeIntervalSince(a) >= skyOldAfter { return true }
        return false
    }

    /// "Live Sky Index"; "Last Sky Reading" when old (never "Live" over old data); "Forecast Sky Index" beyond the live horizon.
    public static func skyTitle(_ sky: GoSkyInfo, now: Date, locale: Locale = .current) -> String {
        if sky.basis == .nextWindowForecast { return String(localized: "Forecast Sky Index", locale: locale) }
        if skyIsOld(sky, now: now) { return String(localized: "Last Sky Reading", locale: locale) }
        return String(localized: "Live Sky Index", locale: locale)
    }

    /// "As of 13:30 · 3 hr old" for an old reading.
    public static func skyAgeLine(_ s: GoSnapshot, now: Date, locale: Locale = .current) -> String? {
        guard let sky = s.sky, skyIsOld(sky, now: now), let a = sky.asOf else { return nil }
        let t = time(a, zone(for: subjectStop(s)), locale)
        let d = TimeText.duration(now.timeIntervalSince(a), locale: locale)
        return String(localized: "As of \(t) · \(d) old", locale: locale)
    }

    /// The observation the live index leans on: the next stop's, else any.
    static func observation(_ s: GoSnapshot) -> GoWeatherInfo? {
        let obs = s.weather.filter { $0.basis == .observation }
        if let id = subjectStop(s)?.id, let m = obs.first(where: { $0.subject == .stop(id) }) { return m }
        return obs.first
    }

    /// What the number rests on.
    public static func skyBasis(_ s: GoSnapshot, now: Date, locale: Locale = .current) -> String {
        guard let sky = s.sky else { return String(localized: "No live data", locale: locale) }
        switch sky.basis {
        case .blended, .observationOnly:
            if let o = observation(s) {
                var parts = [String(localized: "Based on \(o.stationName ?? "nearby") observation", locale: locale, comment: "Sky basis")]
                if let km = o.stationDistanceKm {
                    let d = TimeText.distance(kilometers: km, locale: locale)
                    parts.append(String(localized: "\(d) away", locale: locale))
                }
                parts.append(ago(o.asOf, now: now, locale: locale))
                return parts.joined(separator: " · ")
            }
            var line = String(localized: "Based on observation", locale: locale)
            if let a = sky.asOf { line += " · " + ago(a, now: now, locale: locale) }
            return line
        case .forecastOnly:
            return String(localized: "Forecast only, no recent observation", locale: locale)
        case .nextWindowForecast:
            guard let kind = sky.windowKind else { return String(localized: "Next window: forecast", locale: locale) }
            let name = LightText.name(kind)
            let day = dayWord(sky.windowStart, now: now, zone: zone(for: subjectStop(s)), locale: locale)
            let when = day.map { "\(name) \($0)" } ?? name
            var line = String(localized: "Next window: \(when)", locale: locale, comment: "Sky basis for a later window")
            if let f = sky.forecastScore {
                var tail = String(localized: "forecast \(f)", locale: locale)
                if let w = trendWord(sky.trend, locale: locale)?.lowercased() { tail += ", \(w)" }
                line += " · " + tail
            }
            return line
        case .noData:
            return sky.notice ?? String(localized: "No live data", locale: locale)
        }
    }

    /// "today" / "tomorrow" / weekday, nil when it cannot be said.
    static func dayWord(_ date: Date?, now: Date, zone: TimeZone, locale: Locale) -> String? {
        guard let date else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let a = cal.startOfDay(for: now), b = cal.startOfDay(for: date)
        let days = cal.dateComponents([.day], from: a, to: b).day ?? 0
        switch days {
        case 0: return String(localized: "today", locale: locale)
        case 1: return String(localized: "tomorrow", locale: locale)
        default: return date.formatted(Date.FormatStyle(locale: locale, calendar: cal, timeZone: zone).weekday(.wide))
        }
    }

    /// "Forecast 58" beside a live score.
    public static func forecastBeside(_ sky: GoSkyInfo, locale: Locale = .current) -> String? {
        guard sky.basis != .nextWindowForecast, sky.liveScore != nil, let f = sky.forecastScore else { return nil }
        return String(localized: "Forecast \(f)", locale: locale)
    }

    // Weather

    public static func temperature(_ c: Double, locale: Locale = .current) -> String {
        Measurement(value: c, unit: UnitTemperature.celsius)
            .formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))).locale(locale))
    }

    public static func windSpeed(_ ms: Double, locale: Locale = .current) -> String {
        Measurement(value: ms, unit: UnitSpeed.metersPerSecond)
            .formatted(.measurement(width: .abbreviated, usage: .general, numberFormatStyle: .number.precision(.fractionLength(0))).locale(locale))
    }

    public static func percent(_ f: Double) -> String { "\(Int((min(max(f, 0), 1) * 100).rounded()))%" }

    public struct WeatherFacts: Equatable, Sendable {
        public var temperature: String?
        public var cloud: String?
        public var wind: String?
        public var visibility: String?
        public var precip: String?
    }

    public static func facts(_ w: GoWeatherInfo, locale: Locale = .current) -> WeatherFacts {
        WeatherFacts(temperature: w.tempC.map { temperature($0, locale: locale) }, cloud: w.cloudTotal.map(percent),
                     wind: w.windMs.map { windSpeed($0, locale: locale) },
                     visibility: w.visibilityKm.map { TimeText.distance(kilometers: $0, locale: locale) },
                     precip: w.precipChance.map(percent))
    }

    /// "Here" or the stop's name.
    public static func weatherSubject(_ w: GoWeatherInfo, in s: GoSnapshot, locale: Locale = .current) -> String {
        switch w.subject {
        case .here: return String(localized: "Where you are", locale: locale)
        case .stop(let id):
            let name = [s.next, s.current].compactMap { $0 }.first { $0.id == id }?.name
            return name.map { String(localized: "At \($0)", locale: locale) } ?? String(localized: "At the stop", locale: locale)
        }
    }

    /// "Observed at KCNY · 12 km away · 8 min ago" or "Forecast for this hour".
    public static func weatherSource(_ w: GoWeatherInfo, now: Date, locale: Locale = .current) -> String {
        switch w.basis {
        case .forecast:
            return String(localized: "Forecast for this hour", locale: locale)
        case .observation:
            var parts = [String(localized: "Observed at \(w.stationName ?? "a nearby station")", locale: locale)]
            if let km = w.stationDistanceKm {
                let d = TimeText.distance(kilometers: km, locale: locale)
                parts.append(String(localized: "\(d) away", locale: locale))
            }
            parts.append(ago(w.asOf, now: now, locale: locale))
            return parts.joined(separator: " · ")
        }
    }

    // Hours

    public struct HourColumn: Equatable, Sendable, Identifiable {
        public var id: Date
        public var label: String
        public var cloud: String
        public var precip: String
        public var temperature: String
        public var inWindow: Bool
        public var basis: GoHourInfo.Basis
    }

    /// "17:00" in 24-hour locales, "5 PM" in 12-hour ones (six columns must fit 393 pt).
    public static func hourLabel(_ d: Date, zone: TimeZone, locale: Locale) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = cal.dateComponents([.hour, .minute], from: d)
        let h = c.hour ?? 0, m = c.minute ?? 0
        if locale.hourCycle == .zeroToEleven || locale.hourCycle == .oneToTwelve {
            let h12 = h % 12 == 0 ? 12 : h % 12
            let ap = h < 12 ? "AM" : "PM"
            return m == 0 ? "\(h12) \(ap)" : String(format: "%d:%02d %@", h12, m, ap)
        }
        return String(format: "%02d:%02d", h, m)
    }

    public static let maxHourColumns = 6

    public static func hourColumns(_ s: GoSnapshot, locale: Locale = .current) -> [HourColumn] {
        let z = zone(for: subjectStop(s))
        return (s.hours ?? []).prefix(maxHourColumns).map { h in
            HourColumn(id: h.time, label: hourLabel(h.time, zone: z, locale: locale),
                       cloud: h.cloudTotal.map(percent) ?? "–", precip: h.precipChance.map(percent) ?? "–",
                       temperature: h.tempC.map { temperature($0, locale: locale) } ?? "–", inWindow: h.isInWindow, basis: h.basis)
        }
    }

    /// "Nowcast until 18:00, forecast after", "Nowcast", "Forecast".
    public static func hourBasisNote(_ s: GoSnapshot, locale: Locale = .current) -> String? {
        let hours = Array((s.hours ?? []).prefix(maxHourColumns))
        guard !hours.isEmpty else { return nil }
        let lead = hours.prefix { $0.basis != .forecast }
        if lead.isEmpty { return String(localized: "Forecast", locale: locale) }
        if lead.count == hours.count { return String(localized: "Nowcast", locale: locale) }
        let z = zone(for: subjectStop(s))
        let last = hourLabel(hours[lead.count].time, zone: z, locale: locale)
        return String(localized: "Nowcast until \(last), forecast after", locale: locale)
    }

    // Sources

    public struct SourceWords: Equatable, Sendable {
        public var primary: String
        public var tier: String
        public var isMilitary: Bool
        public var isStale: Bool
    }

    /// "Observation · KCNY METAR · 12 km away · 8 min ago" and the tier ("Military-origin data · US Air Force").
    public static func sourceWords(_ src: GoSourceInfo, now: Date, zone: TimeZone, locale: Locale = .current) -> SourceWords {
        var parts = [src.role, src.name]
        if let km = src.distanceKm { parts.append(String(localized: "\(TimeText.distance(kilometers: km, locale: locale)) away", locale: locale)) }
        if let a = src.asOf {
            if src.isStale {
                let t = time(a, zone, locale)
                parts.append(String(localized: "Stale, as of \(t)", locale: locale))
            } else {
                parts.append(ago(a, now: now, locale: locale))
            }
        } else if src.isStale {
            parts.append(String(localized: "Stale", locale: locale))
        }
        var tier = DataText.phrase(src.tier)
        if let p = src.producer, !p.isEmpty { tier += " · \(p)" }
        return SourceWords(primary: parts.joined(separator: " · "), tier: tier, isMilitary: src.isMilitary, isStale: src.isStale)
    }

    // MARK: Alerts

    public enum AlertLevel: Hashable, Sendable { case warning, danger }

    public static func alertLevel(_ severity: String) -> AlertLevel {
        switch severity.lowercased() {
        case "extreme", "severe": .danger
        default: .warning
        }
    }

    public static func alertSymbol(_ level: AlertLevel) -> String {
        level == .danger ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill"
    }

    /// "Severe · until 21:00".
    public static func alertDetail(_ a: GoAlertInfo, zone: TimeZone, locale: Locale = .current) -> String {
        guard let end = a.ends else { return a.severity }
        let t = time(end, zone, locale)
        return String(localized: "\(a.severity) · until \(t)", locale: locale, comment: "Alert severity and end time")
    }

    // MARK: Freshness

    public struct FreshnessLine: Equatable, Sendable {
        public var symbol: String
        public var text: String
        /// Offline and stale values read in the warning ink (always with their symbol).
        public var warns: Bool
    }

    /// Snapshot age at which the card says so.
    public static let oldSnapshotAfter: TimeInterval = 20 * 60

    public static func freshnessLines(_ s: GoSnapshot, now: Date, locale: Locale = .current) -> [FreshnessLine] {
        guard s.phase != .idle, s.phase != .finished else { return [] }
        let f = s.freshness
        let z = zone(for: subjectStop(s))
        var out: [FreshnessLine] = []
        if f.isOffline {
            let from = f.conditionsAsOf ?? f.etaAsOf ?? s.generatedAt
            let t = time(from, z, locale)
            out.append(FreshnessLine(symbol: "wifi.slash", text: String(localized: "Offline · showing values from \(t)", locale: locale), warns: true))
        }
        if s.drive?.source == .offlineEstimate {
            out.append(FreshnessLine(symbol: "wifi.slash", text: String(localized: "Offline estimate", locale: locale), warns: true))
        }
        if f.etaIsStale, let a = f.etaAsOf ?? s.drive?.asOf {
            let age = ago(a, now: now, locale: locale)
            out.append(FreshnessLine(symbol: "clock.badge.exclamationmark", text: String(localized: "Drive time updated \(age)", locale: locale), warns: true))
        }
        if f.conditionsAreStale, let a = f.conditionsAsOf {
            let age = ago(a, now: now, locale: locale)
            out.append(FreshnessLine(symbol: "clock.badge.exclamationmark", text: String(localized: "Conditions updated \(age)", locale: locale), warns: true))
        }
        if f.locationIsStale, let a = f.locationAsOf {
            let age = ago(a, now: now, locale: locale)
            out.append(FreshnessLine(symbol: "location.slash", text: String(localized: "Location updated \(age)", locale: locale), warns: true))
        }
        if f.isPowerSaving {
            out.append(FreshnessLine(symbol: "battery.50percent", text: String(localized: "Saving power: updates every 10 min", locale: locale), warns: false))
        }
        if now.timeIntervalSince(s.generatedAt) >= oldSnapshotAfter {
            let d = TimeText.duration(now.timeIntervalSince(s.generatedAt), locale: locale)
            out.append(FreshnessLine(symbol: "clock", text: String(localized: "Updated \(d) ago", locale: locale), warns: now.timeIntervalSince(s.generatedAt) >= 3600))
        }
        return out
    }
}
