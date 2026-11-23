import Foundation
import IterModel
import IterSources
import IterSky
import IterAstro
import IterConditions

/// Pure functions from a `SkyReport` (and the clock and ephemeris) to the values `ConditionsModel` publishes.
enum ConditionsDerivation {
    // MARK: Status

    static func status(_ report: SkyReport?, now: Date) -> ConditionsStatus {
        guard let r = report else { return .loading }
        switch r.forecast {
        case .none(let reasons):
            if reasons.contains(.outsideCoverage) { return .outOfCoverage }
            if r.tier != .complete || r.loading.contains(where: { if case .forecast = $0 { true } else { false } }) { return .loading }
            for reason in reasons { if case .offline(let last) = reason { return .offline(lastGood: last, age: last.map { now.timeIntervalSince($0) }) } }
            if reasons.isEmpty, !r.daylight.windows.isEmpty, r.daylight.windows.allSatisfy({ $0.assessment == .unavailable(.inThePast) }) { return .pastDay }
            return .unavailable(reasons)
        case .fresh, .stale:
            if r.offlineNote != nil || r.pack != nil {
                let fetched = r.forecast.provenance?.fetchedAt
                return .offline(lastGood: fetched, age: fetched.map { max(0, now.timeIntervalSince($0)) })
            }
            if case .stale(_, let age) = r.forecast { return .stale(age: age.timeInterval) }
            if let stale = r.daylight.windows.compactMap(\.assessment.skyScore).first(where: \.isStale) { return .stale(age: stale.age) }
            switch r.tier {
            case .quick: return .quick
            case .nearTerm: return .nearTerm
            case .complete: return .complete
            }
        }
    }

    // MARK: Scores

    static func score(_ s: SkyScore, kind: LightWindowKind, tier: ForecastTier) -> HeadlineScore {
        HeadlineScore(kind: kind, value: s.value, band: s.band, confidence: s.confidence, confidenceValue: s.confidenceValue, range: s.range,
                      tier: tier, isStale: s.isStale)
    }

    /// The place's intent window if it is scored, else the best scored window left on the day.
    static func headline(_ r: SkyReport, intent: LightIntent) -> HeadlineScore? {
        if let w = r.daylight.headline(for: intent), let s = w.assessment.skyScore { return score(s, kind: w.kind, tier: r.tier) }
        return bestWindow(r.daylight).map { score($0.score, kind: $0.kind, tier: r.tier) }
    }

    /// The highest-scored window of a day; ties go to the earlier window.
    static func bestWindow(_ d: DayLight) -> (kind: LightWindowKind, score: SkyScore)? {
        var best: (kind: LightWindowKind, score: SkyScore)?
        for w in d.windows.sorted(by: { $0.span.start < $1.span.start }) {
            guard let s = w.assessment.skyScore else { continue }
            if best == nil || s.value > best!.score.value { best = (w.kind, s) }
        }
        return best
    }

    static func windows(_ r: SkyReport) -> [WindowDetail] {
        r.daylight.windows.map { w in
            let s = w.assessment.skyScore
            var lost: TimeInterval?
            if let notes = s?.notes {
                for n in notes { if case .terrainEndsWindowEarly(let by) = n { lost = by } }
            }
            if lost == nil, let e = w.effectiveSpan, w.span.duration - e.duration >= 30 { lost = w.span.duration - e.duration }
            var unavailable: SkyUnavailable?
            if case .unavailable(let u) = w.assessment { unavailable = u }
            return WindowDetail(kind: w.kind, span: w.span, effectiveSpan: w.effectiveSpan, score: s?.value, band: s?.band, confidence: s?.confidence,
                                confidenceValue: s?.confidenceValue, range: s?.range, causes: s?.confidenceCauses ?? [],
                                contributors: s?.contributors ?? [], notes: s?.notes ?? [], flags: s?.flags ?? [], unavailable: unavailable,
                                isStale: s?.isStale ?? false, source: s?.source, terrainLostSeconds: lost)
        }
    }

    // MARK: Outlook

    static func opacity(confidenceValue: Double?) -> Double {
        guard let c = confidenceValue else { return 0.35 }
        return 0.35 + 0.65 * min(1, max(0, c))
    }

    static func outlookRow(day: LocalDay, today: LocalDay, selected: LocalDay, state: ConditionsLoadState?) -> OutlookRow {
        var row = OutlookRow(day: day, isToday: day == today, isSelected: day == selected, load: .loading, opacity: 0.35)
        guard let report = state?.report else { return row }
        if let best = bestWindow(report.daylight) {
            row.load = .ready
            row.bestKind = best.kind
            row.score = best.score.value
            row.band = best.score.band
            row.confidence = best.score.confidence
            row.confidenceValue = best.score.confidenceValue
            row.opacity = opacity(confidenceValue: best.score.confidenceValue)
        } else if report.tier == .complete {
            row.load = .unavailable
        }
        return row
    }

    /// The highest score over the rows; ties go to the sooner day.
    static func whenToGo(_ rows: [OutlookRow]) -> WhenToGo? {
        var best: OutlookRow?
        for row in rows.sorted(by: { $0.day < $1.day }) {
            guard let s = row.score else { continue }
            if best == nil || s > best!.score! { best = row }
        }
        guard let b = best, let kind = b.bestKind, let score = b.score, let band = b.band, let confidence = b.confidence else { return nil }
        return WhenToGo(day: b.day, kind: kind, score: score, band: band, confidence: confidence,
                        isProvisional: rows.contains { $0.load == .loading })
    }

    // MARK: Timeline and hours

    static func timeline(report: SkyReport?, place: Place, day: LocalDay, ephemeris: any Ephemeris) -> LightTimeline {
        let zone = place.timeZone
        let start = day.start(in: zone), end = day.adding(days: 1).start(in: zone)
        var sun: [SunSample] = []
        var t = start
        while t <= end {
            sun.append(SunSample(time: t, altitude: ephemeris.sunPosition(at: t, coordinate: place.coordinate).altitude))
            t = t.addingTimeInterval(1800)
        }
        let spans: [WindowSpan]
        if let r = report {
            spans = r.daylight.windows.map { WindowSpan(kind: $0.kind, span: $0.span, effectiveSpan: $0.effectiveSpan, score: $0.score) }
        } else {
            spans = LightEngine(ephemeris: ephemeris).windows(for: place, on: day).map { WindowSpan(kind: $0.kind, span: $0.span, effectiveSpan: nil, score: nil) }
        }
        let events = report?.daylight.sun ?? ephemeris.sunEvents(on: day, at: place.coordinate, in: zone)
        return LightTimeline(dayStart: start, dayEnd: end, sun: sun, clouds: clouds(report, start: start, end: end), windows: spans,
                             sunrise: events.sunrise, sunset: events.sunset)
    }

    static func clouds(_ r: SkyReport?, start: Date, end: Date) -> [CloudHour] {
        guard let series = r?.forecast.value else { return [] }
        return series.hours.filter { $0.time >= start && $0.time < end }.map {
            CloudHour(time: $0.time, low: $0.cloudLow, mid: $0.cloudMid, high: $0.cloudHigh, total: $0.cloudTotal)
        }
    }

    static func hours(_ r: SkyReport?, day: LocalDay, zone: TimeZone) -> [HourRow] {
        guard let series = r?.forecast.value else { return [] }
        let start = day.start(in: zone), end = day.adding(days: 1).start(in: zone)
        return series.hours.filter { $0.time >= start && $0.time < end }.map { h in
            HourRow(time: h.time, tempC: h.tempC, cloudTotal: h.cloudTotal, cloudLow: h.cloudLow, cloudMid: h.cloudMid, cloudHigh: h.cloudHigh,
                    precipChance: h.precipChance, precipMm: h.precipMm, windMs: h.windMs, gustMs: h.gustMs, windDirDeg: h.windDirDeg,
                    rhPercent: h.rhPercent, visibilityKm: h.visibilityKm, smokeUgm3: h.smokeUgm3)
        }
    }

    // MARK: Observations, alerts, smoke, aurora, horizon

    static func observation(_ r: SkyReport?, now: Date) -> StationObservation? {
        guard let r else { return nil }
        if let reports = r.stationReports.value, let nearest = reports.min(by: { $0.value.distanceKm < $1.value.distanceKm }) {
            let s = nearest.value
            var label = nearest.provenance.origin?.label ?? (s.isMilitary ? "Military airfield" : "Government (aviation weather)")
            if s.isMilitary, !label.contains("Military") { label = "Military airfield: " + label }
            let age = max(0, now.timeIntervalSince(s.observedAt))
            return StationObservation(stationID: s.stationID, stationName: s.stationName ?? s.stationID, distanceKm: s.distanceKm, observedAt: s.observedAt,
                                      ageSeconds: age, isMilitary: s.isMilitary, originLabel: label, flightCategory: s.flightCategory,
                                      weather: s.weather, conditions: s.observation.conditions, rawMETAR: s.rawMETAR, isOld: age > 5400)
        }
        if let list = r.observations.value, let first = list.first {
            let o = first.value
            let age = max(0, now.timeIntervalSince(o.time))
            return StationObservation(stationID: nil, stationName: o.stationName, distanceKm: first.provenance.distanceKm, observedAt: o.time, ageSeconds: age,
                                      isMilitary: first.provenance.origin?.tier == .military,
                                      originLabel: first.provenance.origin?.label ?? "Government", flightCategory: nil, weather: [],
                                      conditions: o.conditions, rawMETAR: nil, isOld: age > 5400)
        }
        return nil
    }

    static func severityRank(_ s: WeatherAlert.Severity) -> Int {
        switch s {
        case .extreme: 0
        case .severe: 1
        case .moderate: 2
        case .minor: 3
        case .unknown: 4
        }
    }

    static func alerts(_ r: SkyReport?) -> [AlertRow] {
        (r?.alerts.value ?? []).sorted { (severityRank($0.severity), $0.id) < (severityRank($1.severity), $1.id) }.map {
            AlertRow(id: $0.id, event: $0.event, headline: $0.headline, severity: $0.severity, onset: $0.onset, ends: $0.ends, sender: $0.senderName, url: $0.url)
        }
    }

    static func smoke(_ r: SkyReport?) -> SmokeInfo {
        guard let r else { return SmokeInfo(density: nil, nearSurfaceMaxUgm3: nil, nearSurfaceSource: nil, opticalDepthMax: nil, notes: []) }
        var notes: [String] = []
        if case .none(let reasons) = r.smoke.analysis, !reasons.isEmpty { notes.append("Smoke analysis: " + reasons.map(ConditionsText.phrase).joined(separator: "; ")) }
        return SmokeInfo(density: r.smoke.analysis.value?.density, nearSurfaceMaxUgm3: r.smoke.nearSurfaceMaxUgm3,
                         nearSurfaceSource: r.smoke.nearSurfaceSource, opticalDepthMax: r.smoke.opticalDepth?.values.map(\.value).max(), notes: notes)
    }

    static func aurora(_ r: SkyReport?) -> AuroraInfo? {
        guard let a = r?.aurora.value else { return nil }
        return AuroraInfo(probabilityPercent: a.probabilityPercent, peakKp: a.kp.map(\.value).max(), kp: a.kp, isStale: r?.aurora.isStale ?? false,
                          sourceLabel: r?.aurora.provenance?.origin?.label)
    }

    static func horizon(_ r: SkyReport?) -> HorizonInfo {
        guard let r else { return HorizonInfo(load: .loading, profile: nil, tallestDegrees: nil, shortened: []) }
        let shortened = r.daylight.windows.compactMap { w -> HorizonInfo.Shortened? in
            guard let e = w.effectiveSpan, w.span.duration - e.duration >= 30 else { return nil }
            return HorizonInfo.Shortened(kind: w.kind, natural: w.span, effective: e, lostSeconds: w.span.duration - e.duration)
        }
        if let profile = r.horizon.value {
            return HorizonInfo(load: .known, profile: profile, tallestDegrees: profile.elevationsDegrees.max(), shortened: shortened)
        }
        return HorizonInfo(load: r.loading.contains(.horizon) ? .loading : .unavailable, profile: nil, tallestDegrees: nil, shortened: shortened)
    }

    static func comparison(_ r: SkyReport?) -> ComparisonInfo? {
        guard let c = r?.comparison else { return nil }
        return ComparisonInfo(sourceName: c.sourceName, maxCloudDifference: c.maxCloudDifference, disagrees: (c.maxCloudDifference ?? 0) > 0.30,
                              fetchedAt: c.provenance.fetchedAt)
    }

    /// Named gaps. Light pollution and seeing have no source today: once the report has settled they always appear, with the
    /// reason, never as a number.
    static func gaps(_ r: SkyReport?) -> [GapRow] {
        guard let r else { return [] }
        var rows = r.gaps.map { GapRow(subject: $0.subject, title: ConditionsText.title($0.subject), reasons: $0.reasons.map(ConditionsText.phrase)) }
        let settled = !r.loading.contains(.lightAndSeeing)
        if settled {
            for (subject, value) in [(GapSubject.lightPollution, r.bortle), (.seeing, r.seeing)] where value == nil && !rows.contains(where: { $0.subject == subject }) {
                rows.append(GapRow(subject: subject, title: ConditionsText.title(subject), reasons: [ConditionsText.phrase(.notProvidedBySource)]))
            }
        }
        return rows
    }

    // MARK: Compass

    static func compassDay(place: Place, day: LocalDay, ephemeris: any Ephemeris) -> CompassDay {
        let zone = place.timeZone
        let sun = ephemeris.sunEvents(on: day, at: place.coordinate, in: zone)
        let moon = ephemeris.moonEvents(on: day, at: place.coordinate, in: zone)
        func sunPoint(_ d: Date?) -> EventPoint? { d.map { EventPoint(time: $0, azimuth: ephemeris.sunPosition(at: $0, coordinate: place.coordinate).azimuth) } }
        func moonPoint(_ d: Date?) -> EventPoint? { d.map { EventPoint(time: $0, azimuth: ephemeris.moonPosition(at: $0, coordinate: place.coordinate).azimuth) } }
        var milky: MilkyWayInfo?
        if let night = LightEngine(ephemeris: ephemeris).windows(for: place, on: day).first(where: { $0.kind == .night }) {
            let v = GalacticCentre.visibility(over: night.span, at: place.coordinate, ephemeris: ephemeris)
            milky = MilkyWayInfo(isVisible: v.isVisible, peakAltitude: v.peakAltitude, peakAzimuth: v.peakAzimuth, peakTime: v.peakTime,
                                 coreUpInDark: v.coreUpInDark, bestWindow: v.bestWindow)
        }
        let phase = ephemeris.moonPhase(at: sun.solarNoon)
        return CompassDay(sunrise: sunPoint(sun.sunrise), sunset: sunPoint(sun.sunset), solarNoon: sun.solarNoon, moonrise: moonPoint(moon.rise),
                          moonset: moonPoint(moon.set), moonIllumination: phase.illumination, moonPhaseName: phase.name, milkyWay: milky)
    }

    static func readout(at time: Date, place: Place, ephemeris: any Ephemeris) -> CompassReadout {
        CompassReadout(time: time, sun: ephemeris.sunPosition(at: time, coordinate: place.coordinate),
                       moon: ephemeris.moonPosition(at: time, coordinate: place.coordinate),
                       milkyWayCore: GalacticCentre.position(at: time, coordinate: place.coordinate))
    }
}
