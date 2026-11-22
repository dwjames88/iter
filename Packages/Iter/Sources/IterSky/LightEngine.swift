import Foundation
import IterModel
import IterAstro

/// Turns sun geometry and a forecast into scored windows. Pure and deterministic: the caller supplies `now`.
public struct LightEngine: Sendable {
    public let ephemeris: any Ephemeris

    public init(ephemeris: any Ephemeris) {
        self.ephemeris = ephemeris
    }

    // MARK: Geometry

    /// The windows the sun produces at `place` on `day`, chronologically, with no weather involved. Times are instants;
    /// the day is the place's own local day, so DST days are 23 or 25 hours long and the windows still land at the
    /// almanac's local times.
    ///
    /// Rules (a window is absent when an endpoint is missing or the span would be empty):
    /// - blueMorning: civil dawn to sunrise.
    /// - goldenMorning: sunrise to the sun reaching +6 degrees. If the sun never reaches +6 (high-latitude winter),
    ///   sunrise to solar noon instead.
    /// - goldenEvening: the sun dropping to +6 until sunset. If it never reaches +6, solar noon to sunset.
    /// - blueEvening: sunset to civil dusk.
    /// - night: astronomical dusk to the earlier of three hours later and the next day's astronomical dawn.
    ///   No astronomical dusk (high-latitude summer) means no night window.
    /// - Polar night (the sun never rises): the civil-twilight blue hour around noon still exists, as
    ///   blueMorning = civil dawn to solar noon and blueEvening = solar noon to civil dusk; night as above.
    /// - Polar day (midnight sun): no sunrise or sunset, so no blue hours and no golden morning; when the sun dips
    ///   below +6 the low sun is a golden window: goldenEvening = the +6 crossing to the next day's +6 rise (capped at
    ///   8 hours). On the transition days (the sun rises but does not set that day) there is a golden morning and no
    ///   golden evening, a known limitation the tests pin.
    public func windows(for place: Place, on day: LocalDay) -> [(kind: LightWindowKind, span: TimeSpan)] {
        let sun = ephemeris.sunEvents(on: day, at: place.coordinate, in: place.timeZone)
        return geometry(sun: sun, coordinate: place.coordinate, day: day, zone: place.timeZone)
    }

    /// The span of one window, or nil when the sun does not produce it that day.
    public func sessionWindow(for place: Place, kind: LightWindowKind, on day: LocalDay) -> TimeSpan? {
        windows(for: place, on: day).first { $0.kind == kind }?.span
    }

    /// `includeNight: false` skips the night window and with it the next day's sun, for callers that never read it.
    /// `nextSun` is the next day's sun when the caller already has it; otherwise it is solved on demand, at most once.
    private func geometry(sun: SunEvents, coordinate: Coordinate, day: LocalDay, includeNight: Bool = true,
                          nextSun: SunEvents? = nil, zone: TimeZone) -> [(kind: LightWindowKind, span: TimeSpan)] {
        var out: [(kind: LightWindowKind, span: TimeSpan)] = []
        var known = nextSun
        func tomorrow() -> SunEvents {
            if let known { return known }
            let solved = ephemeris.sunEvents(on: day.adding(days: 1), at: coordinate, in: zone)
            known = solved
            return solved
        }
        func add(_ kind: LightWindowKind, _ start: Date?, _ end: Date?) {
            guard let start, let end, end > start else { return }
            out.append((kind, TimeSpan(start: start, end: end)))
        }
        func addNight() {
            if includeNight, let dusk = sun.astronomicalDusk {
                let cap = dusk.addingTimeInterval(3 * 3600)
                let nextDawn = tomorrow().astronomicalDawn
                add(.night, dusk, min(cap, nextDawn ?? cap))
            }
        }
        switch sun.kind {
        case .polarNight:
            add(.blueMorning, sun.civilDawn, sun.civilDawn.map { _ in sun.solarNoon })
            add(.blueEvening, sun.civilDusk.map { _ in sun.solarNoon }, sun.civilDusk)
            addNight()
            return out
        case .polarDay:
            if let start = sun.goldenEveningStart {
                let nextRise = tomorrow().goldenMorningEnd
                let cap = start.addingTimeInterval(8 * 3600)
                add(.goldenEvening, start, min(cap, nextRise ?? cap))
            }
            return out
        case .normal:
            break
        }
        add(.blueMorning, sun.civilDawn, sun.sunrise)
        if sun.sunrise != nil {
            add(.goldenMorning, sun.sunrise, sun.goldenMorningEnd ?? sun.solarNoon)
        }
        if sun.sunset != nil {
            add(.goldenEvening, sun.goldenEveningStart ?? sun.solarNoon, sun.sunset)
        }
        add(.blueEvening, sun.sunset, sun.civilDusk)
        addNight()
        return out
    }

    // MARK: Days

    public func dayLight(for place: Place, on day: LocalDay, inputs: ForecastSkyInputs?, unavailable: [NoDataReason] = [],
                         now: Date) -> DayLight {
        let sun = ephemeris.sunEvents(on: day, at: place.coordinate, in: place.timeZone)
        return dayLight(for: place, on: day, sun: sun, nextSun: nil, inputs: inputs, unavailable: unavailable, now: now)
    }

    /// One day from its already solved sun. `nextSun` is the following day's sun when the caller has it (it ends the
    /// night window and the midnight-sun golden evening), so consecutive days solve each day's sun once.
    private func dayLight(for place: Place, on day: LocalDay, sun: SunEvents, nextSun: SunEvents?, inputs: ForecastSkyInputs?,
                          unavailable: [NoDataReason], now: Date) -> DayLight {
        let zone = place.timeZone
        let moon = ephemeris.moonEvents(on: day, at: place.coordinate, in: zone)
        let geo = geometry(sun: sun, coordinate: place.coordinate, day: day, nextSun: nextSun, zone: zone)
        let windows = geo.map { g in lightWindow(kind: g.kind, span: g.span, place: place, inputs: inputs, unavailable: unavailable, now: now) }
        let phaseAt = geo.first { $0.kind == .night }?.span.start ?? day.noon(in: zone)
        return DayLight(day: day, coordinate: place.coordinate, timeZoneIdentifier: place.timeZoneIdentifier, sun: sun, moon: moon,
                        moonPhase: ephemeris.moonPhase(at: phaseAt), windows: windows)
    }

    /// `count` consecutive days from `day`. Each day's sun is solved once and handed to the day before it.
    private func dayLights(for place: Place, from day: LocalDay, count: Int, inputs: ForecastSkyInputs?,
                           unavailable: [NoDataReason], now: Date) -> [DayLight] {
        guard count > 0 else { return [] }
        let zone = place.timeZone
        var out: [DayLight] = []
        out.reserveCapacity(count)
        var sun = ephemeris.sunEvents(on: day, at: place.coordinate, in: zone)
        for i in 0..<count {
            let d = day.adding(days: i)
            // The last day's next sun is solved only if its geometry asks for it.
            let next = i + 1 < count ? ephemeris.sunEvents(on: d.adding(days: 1), at: place.coordinate, in: zone) : nil
            out.append(dayLight(for: place, on: d, sun: sun, nextSun: next, inputs: inputs, unavailable: unavailable, now: now))
            if let next { sun = next }
        }
        return out
    }

    public func outlook(for place: Place, from day: LocalDay, days: Int, inputs: ForecastSkyInputs?,
                        unavailable: [NoDataReason] = [], now: Date) -> [DayLight] {
        dayLights(for: place, from: day, count: days, inputs: inputs, unavailable: unavailable, now: now)
    }

    /// The best scored window for `intent` over the next `days` days. Only scored windows count (an unavailable
    /// window never wins). Ties go to higher confidence, then to the earlier window. nil if nothing is scored.
    public func bestUpcoming(for place: Place, intent: LightIntent, from day: LocalDay, days: Int, inputs: ForecastSkyInputs?,
                             unavailable: [NoDataReason] = [], now: Date) -> (day: LocalDay, window: LightWindow)? {
        var best: (day: LocalDay, window: LightWindow, score: SkyScore)?
        for dl in outlook(for: place, from: day, days: days, inputs: inputs, unavailable: unavailable, now: now) {
            for window in dl.windows where intent.windows.contains(window.kind) {
                guard let score = window.assessment.skyScore else { continue }
                if let current = best {
                    let better = score.value > current.score.value
                        || (score.value == current.score.value && score.confidence > current.score.confidence)
                        || (score.value == current.score.value && score.confidence == current.score.confidence
                            && window.span.start < current.window.span.start)
                    if !better { continue }
                }
                best = (dl.day, window, score)
            }
        }
        return best.map { ($0.day, $0.window) }
    }

    /// The next sunrise or sunset event at the place by the place's own clock: golden morning or golden evening of today
    /// through three days on, the first whose window has not ended. Polar fallback: the first daytime window not yet over.
    public func nextEvent(for place: Place, inputs: ForecastSkyInputs?, unavailable: [NoDataReason] = [],
                          now: Date) -> (day: LocalDay, window: LightWindow)? {
        // Lazy: only the sun's geometry is needed to find the window, day by day, and only the chosen window is scored
        // (no moon, no scoring of the other windows). Same answer as scanning four full `dayLight`s.
        let zone = place.timeZone
        let today = LocalDay(now, in: zone)
        var fallback: (day: LocalDay, kind: LightWindowKind, span: TimeSpan)?
        for offset in 0..<4 {
            let day = today.adding(days: offset)
            // No night window is read here, so the next day's sun is not solved for it.
            let geo = geometry(sun: ephemeris.sunEvents(on: day, at: place.coordinate, in: zone), coordinate: place.coordinate,
                               day: day, includeNight: false, zone: zone)
            if let g = geo.first(where: { ($0.kind == .goldenMorning || $0.kind == .goldenEvening) && $0.span.end > now }) {
                return (day, lightWindow(kind: g.kind, span: g.span, place: place, inputs: inputs, unavailable: unavailable, now: now))
            }
            if fallback == nil, let g = geo.first(where: { $0.kind != .night && $0.span.end > now }) {
                fallback = (day, g.kind, g.span)
            }
        }
        guard let f = fallback else { return nil }
        return (f.day, lightWindow(kind: f.kind, span: f.span, place: place, inputs: inputs, unavailable: unavailable, now: now))
    }

    /// Today's windows that have not ended (place's zone), then all of tomorrow's, chronologically.
    public func upcomingWindows(for place: Place, inputs: ForecastSkyInputs?, unavailable: [NoDataReason] = [],
                                now: Date) -> [(day: LocalDay, window: LightWindow)] {
        let today = LocalDay(now, in: place.timeZone)
        let both = dayLights(for: place, from: today, count: 2, inputs: inputs, unavailable: unavailable, now: now)
        var out: [(day: LocalDay, window: LightWindow)] = []
        out += both[0].windows.filter { $0.span.end > now }.map { (both[0].day, $0) }
        out += both[1].windows.map { (both[1].day, $0) }
        return out
    }

    /// How many outlook days to show: the days the forecast covers, at most `max`. Without a forecast, `max`.
    public func outlookDayCount(for place: Place, from day: LocalDay, inputs: ForecastSkyInputs?, max: Int) -> Int {
        guard max >= 1 else { return 0 }
        guard let hourly = inputs?.hourly, !hourly.hours.isEmpty else { return max }
        return Swift.max(1, Swift.min(max, hourly.coveredDays(from: day, in: place.timeZone)))
    }

    // MARK: Assessment

    /// One window with its assessment and its terrain-adjusted span.
    func lightWindow(kind: LightWindowKind, span: TimeSpan, place: Place, inputs: ForecastSkyInputs?,
                     unavailable: [NoDataReason], now: Date) -> LightWindow {
        let e = ForecastSkyIndex.evaluate(kind: kind, span: span, place: place, inputs: inputs, unavailable: unavailable,
                                          ephemeris: ephemeris, now: now)
        return LightWindow(kind: kind, span: span, effectiveSpan: e.effectiveSpan, assessment: e.assessment)
    }

    func assess(kind: LightWindowKind, span: TimeSpan, place: Place, inputs: ForecastSkyInputs?, unavailable: [NoDataReason] = [],
                now: Date) -> LightAssessment {
        ForecastSkyIndex.score(kind: kind, span: span, place: place, inputs: inputs, unavailable: unavailable,
                               ephemeris: ephemeris, now: now)
    }
}
