import Foundation
import IterModel

/// Realistic sample snapshots for every state Go draws: the widget placeholder, SwiftUI previews and the snapshot renders
/// of the Go screens, the Live Activity and the widgets all use these, so every surface is checked against the same data.
/// A Moab, Utah evening (America/Denver). Times are relative to the `now` passed in.
public enum GoSample: String, CaseIterable, Sendable {
    /// No run.
    case idle
    /// Started; first departure hours away (countdown).
    case armedEarly
    /// Leave-by within 15 minutes.
    case leaveSoon
    /// Leave-by is now.
    case leaveNow
    /// Driving, arriving before set-up ("arrive 17:42 · 28 min before sunset").
    case drivingOnTime
    /// Driving, late for set-up, with the next-best stop offered.
    case drivingLate
    /// Driving, the window will be over on arrival, with the next-best stop offered.
    case drivingMissed
    /// At a stop, shooting: live sky blended with an observation, the window running, the plan fits.
    case atStopShooting
    /// At a stop, staying costs the next stop ("Leave by 18:40 to make blue hour at X").
    case atStopStayCost
    /// Just arrived automatically (geofence): "Not yet" undo for 2 minutes.
    case arrivedUndo
    /// Done with one stop, the next leave-by later today.
    case betweenStops
    /// Done for the day; the next stop is tomorrow morning (Evening Before suggestion).
    case betweenOvernight
    /// The user paused trip mode.
    case paused
    /// The run is over: a short summary.
    case finished
    /// No network: offline-estimate ETA, last good conditions with their ages, "No live data".
    case offline
    /// The app has not run for hours: every value old, the snapshot's age shown.
    case stale
    /// An official alert in force at the next stop.
    case alert
    /// Low Power Mode: refresh intervals stretched, the card says so.
    case powerSaving
    /// No window within the live horizon: the next window's forecast score with its trend.
    case nextWindowForecast

    /// The sample at `now`.
    public func snapshot(now: Date) -> GoSnapshot { GoSampleFactory.snapshot(self, now: now) }
}

// MARK: - The data

/// The five stops of "Canyonlands Weekend", in trip order. Coordinates are real; names are the places photographers go.
private enum Spot: Int {
    case deadHorse = 1, mesaArch, lodging, fisherTowers, delicateArch

    var id: UUID { UUID(uuidString: "5A3E0000-0000-4000-8000-00000000000\(rawValue)")! }
    var name: String {
        switch self {
        case .deadHorse: "Dead Horse Point"
        case .mesaArch: "Mesa Arch"
        case .lodging: "Moab lodging"
        case .fisherTowers: "Fisher Towers"
        case .delicateArch: "Delicate Arch"
        }
    }
    var locality: String {
        switch self {
        case .deadHorse: "Dead Horse Point State Park"
        case .mesaArch: "Canyonlands National Park"
        case .lodging: "Moab, UT"
        case .fisherTowers: "Fisher Towers, UT"
        case .delicateArch: "Arches National Park"
        }
    }
    var kind: StopKind { self == .lodging ? .lodging : .light }
    var dayIndex: Int { rawValue <= 3 ? 0 : 1 }
    var coordinate: Coordinate {
        switch self {
        case .deadHorse: Coordinate(latitude: 38.4837, longitude: -109.7410)
        case .mesaArch: Coordinate(latitude: 38.3873, longitude: -109.8695)
        case .lodging: Coordinate(latitude: 38.5731, longitude: -109.5493)
        case .fisherTowers: Coordinate(latitude: 38.7160, longitude: -109.3084)
        case .delicateArch: Coordinate(latitude: 38.7358, longitude: -109.5209)
        }
    }
    /// nil for the lodging.
    var session: LightWindowKind? {
        switch self {
        case .deadHorse, .delicateArch: .goldenEvening
        case .mesaArch: .blueEvening
        case .fisherTowers: .goldenMorning
        case .lodging: nil
        }
    }
    /// Minutes from the car to the camera position.
    var walkIn: Double {
        switch self {
        case .deadHorse: 10
        case .mesaArch: 8
        case .lodging: 0
        case .fisherTowers: 15
        case .delicateArch: 35
        }
    }
    /// The planned drive into this stop from the one before it (the first from Moab).
    var driveSeconds: TimeInterval {
        switch self {
        case .deadHorse: 2760
        case .mesaArch: 1140
        case .lodging: 3300
        case .fisherTowers: 1800
        case .delicateArch: 3000
        }
    }
}

private let denver = "America/Denver"
private let tripID = UUID(uuidString: "5A3E0000-0000-4000-8000-0000000000A1")!
private let runID = UUID(uuidString: "5A3E0000-0000-4000-8000-0000000000B1")!
private let moab = Coordinate(latitude: 38.5742, longitude: -109.5486)
private let station = "KCNY (Canyonlands Field)"

private func band(_ score: Int?) -> GoBand? {
    guard let score else { return nil }
    switch score {
    case 88...: return .epic
    case 74..<88: return .great
    case 58..<74: return .good
    case 40..<58: return .fair
    default: return .poor
    }
}

/// One scene's clock: `sunset` is the evening's sunset in minutes from `now` (negative once past). Every window follows from it
/// the way the engine lays them out: golden evening ends at sunset, blue evening starts 22 minutes after, tomorrow's sunrise is
/// 13 hours 15 minutes on (a 10 h 45 min day), and a session's set-up is 20 minutes before its window.
private struct Frame {
    let now: Date
    let sunset: Double

    func at(_ minutes: Double) -> Date { now.addingTimeInterval(minutes * 60) }
    func ago(_ minutes: Double) -> Date { at(-minutes) }

    func window(_ s: Spot) -> (kind: LightWindowKind, start: Double, end: Double)? {
        switch s {
        case .deadHorse: (.goldenEvening, sunset - 60, sunset)
        case .mesaArch: (.blueEvening, sunset + 22, sunset + 52)
        case .lodging: nil
        case .fisherTowers: (.goldenMorning, sunset + 795, sunset + 855)
        case .delicateArch: (.goldenEvening, sunset + 1378, sunset + 1438)
        }
    }
    func arriveBy(_ s: Spot) -> Double {
        guard let w = window(s) else { return sunset + 140 }
        return w.start - 20 - s.walkIn
    }
    /// 5 minutes plus 10 % of the drive.
    func margin(_ driveSeconds: TimeInterval) -> Double { 5 + 0.1 * driveSeconds / 60 }
    func leaveBy(_ s: Spot, drive: TimeInterval? = nil) -> Double {
        let d = drive ?? s.driveSeconds
        return arriveBy(s) - d / 60 - margin(d)
    }

    func info(_ s: Spot) -> GoStopInfo {
        let w = window(s)
        return GoStopInfo(id: s.id, number: s.rawValue, name: s.name, locality: s.locality, kind: s.kind, dayIndex: s.dayIndex,
                          coordinate: s.coordinate, timeZoneIdentifier: denver, windowKind: w?.kind, windowStart: w.map { at($0.start) },
                          windowEnd: w.map { at($0.end) }, setUpBy: w.map { at($0.start - 20) }, arriveBy: at(arriveBy(s)))
    }

    func base(_ phase: GoPhase, current: Spot? = nil, next: Spot?) -> GoSnapshot {
        GoSnapshot(generatedAt: now, tripID: tripID, tripName: "Canyonlands Weekend", runID: runID, phase: phase, current: current.map(info),
                   next: next.map(info), remainingCount: next.map { 5 - $0.rawValue } ?? 0)
    }

    func leave(_ s: Spot, drive: TimeInterval? = nil, _ status: GoLeaveStatus, late: TimeInterval? = nil, earliest: Double? = nil,
               suggested: Double? = nil) -> GoLeaveInfo {
        GoLeaveInfo(leaveBy: at(leaveBy(s, drive: drive)), status: status, lateBySeconds: late, earliestDeparture: earliest.map(at),
                    suggestedDeparture: suggested.map(at))
    }

    func sky(_ s: Spot, live: Int?, forecast: Int?, confidence: GoConfidence, trend: GoTrend, basis: GoSkyInfo.Basis, asOfAgo: Double?,
             notice: String? = nil, stale: Bool = false) -> GoSkyInfo {
        let w = window(s)
        return GoSkyInfo(stopID: s.id, windowKind: w?.kind, windowStart: w.map { at($0.start) }, windowEnd: w.map { at($0.end) }, liveScore: live,
                         forecastScore: forecast, band: band(live ?? forecast), confidence: confidence, trend: trend, basis: basis,
                         asOf: asOfAgo.map(ago), notice: notice, isStale: stale)
    }

    func observed(_ subject: GoWeatherInfo.Subject, agoMin: Double, temp: Double, cloud: Double, vis: Double, wind: Double, distance: Double) -> GoWeatherInfo {
        GoWeatherInfo(subject: subject, basis: .observation, tempC: temp, cloudTotal: cloud, visibilityKm: vis, precipChance: nil, windMs: wind,
                      stationName: station, stationDistanceKm: distance, asOf: ago(agoMin))
    }
    func forecastWx(_ subject: GoWeatherInfo.Subject, agoMin: Double, temp: Double, cloud: Double, vis: Double = 40, precip: Double = 0.03,
                    wind: Double) -> GoWeatherInfo {
        GoWeatherInfo(subject: subject, basis: .forecast, tempC: temp, cloudTotal: cloud, visibilityKm: vis, precipChance: precip, windMs: wind,
                      stationName: nil, stationDistanceKm: nil, asOf: ago(agoMin))
    }

    /// Six hourly entries from the next whole hour for `s`. `bases` gives the first entries' basis (the rest are forecast).
    func hours(for s: Spot, bases: [GoHourInfo.Basis], cloud: [Double], temp: Double, wind: Double = 3) -> [GoHourInfo] {
        let first = (now.timeIntervalSince1970 / 3600).rounded(.down) + 1
        let w = window(s)
        return (0..<6).map { i in
            let t = Date(timeIntervalSince1970: (first + Double(i)) * 3600)
            let c = cloud[i % cloud.count]
            let inWindow = w.map { t < at($0.end) && t.addingTimeInterval(3600) > at($0.start) } ?? false
            return GoHourInfo(time: t, basis: i < bases.count ? bases[i] : .forecast, cloudTotal: c, precipChance: (c * 0.12 * 100).rounded() / 100,
                              tempC: temp - 1.1 * Double(i), windMs: wind + 0.3 * Double(i), visibilityKm: (40 - c * 18).rounded(), isInWindow: inWindow)
        }
    }

    /// The remaining schedule from `spots`; the first item carries the live numbers, later ones their planned chain.
    func schedule(_ spots: [Spot], first: (leaveBy: Double?, arrival: Double?, status: GoLeaveStatus)) -> [GoScheduleItem] {
        spots.enumerated().map { i, s in
            if i == 0 { return GoScheduleItem(stop: info(s), leaveBy: first.leaveBy.map(at), arrival: first.arrival.map(at), status: first.status) }
            let l = leaveBy(s)
            return GoScheduleItem(stop: info(s), leaveBy: at(l), arrival: at(l + s.driveSeconds / 60), status: .early)
        }
    }

    /// The sources behind the numbers, best tier first.
    func details(forecastAge: Double = 20, obs: Bool = false, military: Bool = false, alerts: Bool = false, drive: Bool = false,
                 obsAge: Double = 6, stale: Bool = false) -> [GoSourceInfo] {
        var out: [GoSourceInfo] = []
        out.append(GoSourceInfo(role: "Cloud, precipitation, temperature", name: "NOAA HRRR and GFS", tier: .government, producer: "NOAA NCEP",
                                asOf: ago(forecastAge + 20), distanceKm: 3, isStale: stale))
        if obs {
            out.append(GoSourceInfo(role: "Observation", name: "KCNY METAR", tier: .government, asOf: ago(obsAge), distanceKm: 24, isStale: stale))
        }
        if military {
            out.append(GoSourceInfo(role: "Regional observation", name: "KHIF (Hill AFB) METAR", tier: .military, producer: "US Air Force",
                                    asOf: ago(obsAge + 4), distanceKm: 349, isStale: stale))
        }
        if alerts {
            out.append(GoSourceInfo(role: "Alerts", name: "National Weather Service", tier: .government, producer: "NOAA National Weather Service",
                                    asOf: ago(6), isStale: stale))
        }
        if drive {
            out.append(GoSourceInfo(role: "Drive time", name: "Apple Maps", tier: .openData, producer: "Apple", asOf: ago(1.5)))
        }
        return out.enumerated().sorted { ($0.element.tier, $0.offset) < ($1.element.tier, $1.offset) }.map(\.element)
    }
}

// MARK: - The cases

private enum GoSampleFactory {
    static func snapshot(_ sample: GoSample, now: Date) -> GoSnapshot {
        switch sample {
        case .idle: .idle(at: now)
        case .armedEarly: armedEarly(now)
        case .leaveSoon: leaveSoon(now)
        case .leaveNow: leaveNow(now)
        case .drivingOnTime: drivingOnTime(now)
        case .drivingLate: drivingLate(now)
        case .drivingMissed: drivingMissed(now)
        case .atStopShooting: atStopShooting(now)
        case .atStopStayCost: atStopStayCost(now)
        case .arrivedUndo: arrivedUndo(now)
        case .betweenStops: betweenStops(now)
        case .betweenOvernight: betweenOvernight(now)
        case .paused: paused(now)
        case .finished: finished(now)
        case .offline: offline(now)
        case .stale: stale(now)
        case .alert: alert(now)
        case .powerSaving: powerSaving(now)
        case .nextWindowForecast: nextWindowForecast(now)
        }
    }

    private static let obsHours: [GoHourInfo.Basis] = [.observation, .nowcast]
    private static let nowcastHours: [GoHourInfo.Basis] = [.nowcast, .nowcast]
    private static let clearish = [0.28, 0.22, 0.25, 0.32, 0.4, 0.45]
    private static let allSpots: [Spot] = [.deadHorse, .mesaArch, .lodging, .fisherTowers, .delicateArch]

    private static func armedEarly(_ now: Date) -> GoSnapshot {
        let f = Frame(now: now, sunset: 110)
        let l = f.leaveBy(.fisherTowers)
        var s = f.base(.armed, next: .fisherTowers)
        s.leave = f.leave(.fisherTowers, .early)
        s.drive = GoDriveInfo(arrival: f.at(l + 30), driveSeconds: 1800, driveMeters: nil, source: .planned, asOf: f.ago(15))
        s.sky = f.sky(.fisherTowers, live: nil, forecast: 64, confidence: .medium, trend: .steady, basis: .nextWindowForecast, asOfAgo: 14)
        s.weather = [f.forecastWx(.here, agoMin: 14, temp: 14.5, cloud: 0.35, wind: 3.2),
                     f.forecastWx(.stop(Spot.fisherTowers.id), agoMin: 14, temp: -0.5, cloud: 0.2, wind: 1.8)]
        s.freshness = GoFreshness(locationAsOf: f.ago(2), conditionsAsOf: f.ago(14), packBuiltAt: f.ago(300), nextRefreshAt: f.at(15))
        s.sources = ["NOAA HRRR", "NWS"]
        s.hours = f.hours(for: .fisherTowers, bases: nowcastHours, cloud: clearish, temp: 14)
        s.sourceDetails = f.details(forecastAge: 14)
        s.schedule = f.schedule([.fisherTowers, .delicateArch], first: (l, l + 30, .early))
        s.here = moab
        return s
    }

    private static func leaveSoon(_ now: Date) -> GoSnapshot {
        let f = Frame(now: now, sunset: 110)
        let l = f.leaveBy(.mesaArch, drive: 4800)
        var s = f.base(.armed, next: .mesaArch)
        s.leave = f.leave(.mesaArch, drive: 4800, .leaveSoon)
        s.drive = GoDriveInfo(arrival: f.at(l + 80), driveSeconds: 4800, driveMeters: 82_000, source: .live, asOf: f.ago(1.5))
        s.sky = f.sky(.mesaArch, live: 64, forecast: 60, confidence: .medium, trend: .steady, basis: .blended, asOfAgo: 4)
        s.weather = [f.observed(.here, agoMin: 6, temp: 9.8, cloud: 0.3, vis: 16, wind: 2.6, distance: 3),
                     f.forecastWx(.stop(Spot.mesaArch.id), agoMin: 4, temp: 7.8, cloud: 0.3, wind: 4.4)]
        s.freshness = GoFreshness(locationAsOf: f.ago(1), etaAsOf: f.ago(1.5), conditionsAsOf: f.ago(4), packBuiltAt: f.ago(190), nextRefreshAt: f.at(3))
        s.sources = ["Apple Maps", "NOAA HRRR", "KCNY METAR"]
        s.hours = f.hours(for: .mesaArch, bases: obsHours, cloud: clearish, temp: 9.5)
        s.sourceDetails = f.details(forecastAge: 4, obs: true, drive: true)
        s.schedule = f.schedule([.mesaArch, .lodging, .fisherTowers, .delicateArch], first: (l, l + 80, .leaveSoon))
        s.here = moab
        return s
    }

    private static func leaveNow(_ now: Date) -> GoSnapshot {
        let f = Frame(now: now, sunset: 110)
        let l = f.leaveBy(.mesaArch, drive: 5400)
        var s = f.base(.armed, next: .mesaArch)
        s.leave = f.leave(.mesaArch, drive: 5400, .leaveNow)
        s.drive = GoDriveInfo(arrival: f.at(90), driveSeconds: 5400, driveMeters: 91_000, source: .live, asOf: f.ago(0.5))
        s.sky = f.sky(.mesaArch, live: 66, forecast: 61, confidence: .medium, trend: .rising, basis: .blended, asOfAgo: 3)
        s.weather = [f.observed(.here, agoMin: 5, temp: 9.4, cloud: 0.28, vis: 16, wind: 2.4, distance: 3),
                     f.forecastWx(.stop(Spot.mesaArch.id), agoMin: 3, temp: 7.5, cloud: 0.27, wind: 4.2)]
        s.freshness = GoFreshness(locationAsOf: f.ago(0.5), etaAsOf: f.ago(0.5), conditionsAsOf: f.ago(3), packBuiltAt: f.ago(200), nextRefreshAt: f.at(3))
        s.sources = ["Apple Maps", "NOAA HRRR", "KCNY METAR"]
        s.hours = f.hours(for: .mesaArch, bases: obsHours, cloud: clearish, temp: 9.2)
        s.sourceDetails = f.details(forecastAge: 3, obs: true, drive: true)
        s.schedule = f.schedule([.mesaArch, .lodging, .fisherTowers, .delicateArch], first: (l, 90, .leaveNow))
        s.here = Spot.delicateArch.coordinate
        return s
    }

    private static func drivingOnTime(_ now: Date) -> GoSnapshot {
        let f = Frame(now: now, sunset: 110)
        var s = f.base(.driving, next: .deadHorse)
        s.leave = f.leave(.deadHorse, drive: 1260, .leaveNow)
        s.drive = GoDriveInfo(arrival: f.at(21), driveSeconds: 1260, driveMeters: 29_400, source: .live, asOf: f.ago(0.5))
        s.sky = f.sky(.deadHorse, live: 71, forecast: 66, confidence: .high, trend: .rising, basis: .blended, asOfAgo: 2)
        s.weather = [f.observed(.here, agoMin: 4, temp: 8.2, cloud: 0.25, vis: 20, wind: 3.4, distance: 22),
                     f.forecastWx(.stop(Spot.deadHorse.id), agoMin: 2, temp: 7.2, cloud: 0.22, wind: 4.6)]
        s.freshness = GoFreshness(locationAsOf: f.ago(0.3), etaAsOf: f.ago(0.5), conditionsAsOf: f.ago(2), packBuiltAt: f.ago(215), nextRefreshAt: f.at(3))
        s.sources = ["Apple Maps", "NOAA HRRR", "KCNY METAR"]
        s.hours = f.hours(for: .deadHorse, bases: obsHours, cloud: [0.25, 0.2, 0.22, 0.3, 0.4, 0.5], temp: 8)
        s.sourceDetails = f.details(forecastAge: 2, obs: true, military: true, drive: true, obsAge: 4)
        s.schedule = f.schedule(allSpots, first: (f.leaveBy(.deadHorse, drive: 1260), 21, .leaveNow))
        s.here = Coordinate(latitude: 38.6381, longitude: -109.7242)
        return s
    }

    private static func drivingLate(_ now: Date) -> GoSnapshot {
        let f = Frame(now: now, sunset: 110)
        var s = f.base(.driving, next: .deadHorse)
        s.leave = f.leave(.deadHorse, drive: 2700, .late, late: 900)
        s.drive = GoDriveInfo(arrival: f.at(45), driveSeconds: 2700, driveMeters: 57_000, source: .live, asOf: f.ago(1))
        s.alternative = GoAlternativeInfo(stopID: Spot.mesaArch.id, name: "Mesa Arch", windowKind: .blueEvening, windowStart: f.at(132),
                                          projectedArrival: f.at(75), makesSetUp: true)
        s.sky = f.sky(.deadHorse, live: 55, forecast: 61, confidence: .medium, trend: .falling, basis: .blended, asOfAgo: 3)
        s.weather = [f.observed(.here, agoMin: 5, temp: 9.0, cloud: 0.5, vis: 18, wind: 3.8, distance: 6),
                     f.forecastWx(.stop(Spot.deadHorse.id), agoMin: 3, temp: 7.4, cloud: 0.55, wind: 5.0)]
        s.freshness = GoFreshness(locationAsOf: f.ago(0.5), etaAsOf: f.ago(1), conditionsAsOf: f.ago(3), packBuiltAt: f.ago(240), nextRefreshAt: f.at(3))
        s.sources = ["Apple Maps", "NOAA HRRR", "KCNY METAR"]
        s.hours = f.hours(for: .deadHorse, bases: obsHours, cloud: [0.5, 0.55, 0.6, 0.62, 0.55, 0.5], temp: 8.8)
        s.sourceDetails = f.details(forecastAge: 3, obs: true, drive: true)
        s.schedule = f.schedule(allSpots, first: (f.leaveBy(.deadHorse, drive: 2700), 45, .late))
        s.here = Coordinate(latitude: 38.6008, longitude: -109.6102)
        return s
    }

    private static func drivingMissed(_ now: Date) -> GoSnapshot {
        let f = Frame(now: now, sunset: 110)
        var s = f.base(.driving, next: .deadHorse)
        s.leave = f.leave(.deadHorse, drive: 7200, .missed, late: 5400)
        s.drive = GoDriveInfo(arrival: f.at(120), driveSeconds: 7200, driveMeters: 151_000, source: .live, asOf: f.ago(1))
        s.alternative = GoAlternativeInfo(stopID: Spot.mesaArch.id, name: "Mesa Arch", windowKind: .blueEvening, windowStart: f.at(132),
                                          projectedArrival: f.at(125), makesSetUp: false)
        s.sky = f.sky(.deadHorse, live: 71, forecast: 66, confidence: .high, trend: .steady, basis: .blended, asOfAgo: 2)
        s.weather = [f.observed(.here, agoMin: 4, temp: 8.6, cloud: 0.2, vis: 24, wind: 2.8, distance: 4),
                     f.forecastWx(.stop(Spot.deadHorse.id), agoMin: 2, temp: 6.9, cloud: 0.18, wind: 4.0)]
        s.freshness = GoFreshness(locationAsOf: f.ago(0.5), etaAsOf: f.ago(1), conditionsAsOf: f.ago(2), packBuiltAt: f.ago(250), nextRefreshAt: f.at(3))
        s.sources = ["Apple Maps", "NOAA HRRR", "KCNY METAR"]
        s.hours = f.hours(for: .deadHorse, bases: obsHours, cloud: [0.2, 0.18, 0.2, 0.25, 0.3, 0.3], temp: 8.4)
        s.sourceDetails = f.details(forecastAge: 2, obs: true, drive: true, obsAge: 4)
        s.schedule = f.schedule(allSpots, first: (f.leaveBy(.deadHorse, drive: 7200), 120, .missed))
        s.here = Coordinate(latitude: 38.9950, longitude: -110.1590)
        return s
    }

    private static func atStopShooting(_ now: Date) -> GoSnapshot {
        let f = Frame(now: now, sunset: 110)
        let l = f.leaveBy(.mesaArch)
        var s = f.base(.atStop, current: .deadHorse, next: .mesaArch)
        s.leave = f.leave(.mesaArch, .early, earliest: 75)
        s.drive = GoDriveInfo(arrival: f.at(l + 19), driveSeconds: 1140, driveMeters: nil, source: .planned, asOf: f.ago(42))
        s.stay = GoStayInfo(plannedDeparture: f.at(75), latestDeparture: f.at(l), cutsShortBySeconds: nil, nextStopName: "Mesa Arch",
                            nextWindowKind: .blueEvening)
        s.sky = f.sky(.deadHorse, live: 68, forecast: 61, confidence: .high, trend: .rising, basis: .blended, asOfAgo: 3)
        s.weather = [f.observed(.here, agoMin: 7, temp: 6.4, cloud: 0.22, vis: 40, wind: 3.0, distance: 38),
                     f.forecastWx(.stop(Spot.deadHorse.id), agoMin: 3, temp: 6.8, cloud: 0.24, wind: 3.6)]
        s.freshness = GoFreshness(locationAsOf: f.ago(0.5), etaAsOf: f.ago(42), conditionsAsOf: f.ago(3), packBuiltAt: f.ago(260), nextRefreshAt: f.at(6))
        s.sources = ["NOAA HRRR", "KCNY METAR", "KHIF (Hill AFB) METAR"]
        s.hours = f.hours(for: .deadHorse, bases: obsHours, cloud: [0.24, 0.2, 0.22, 0.28, 0.35, 0.4], temp: 6.5)
        s.sourceDetails = f.details(forecastAge: 3, obs: true, military: true, obsAge: 7)
        s.schedule = f.schedule([.mesaArch, .lodging, .fisherTowers, .delicateArch], first: (l, l + 19, .early))
        s.here = Coordinate(latitude: 38.4838, longitude: -109.7412)
        return s
    }

    private static func atStopStayCost(_ now: Date) -> GoSnapshot {
        let f = Frame(now: now, sunset: 110)
        let l = f.leaveBy(.mesaArch)
        var s = f.base(.atStop, current: .deadHorse, next: .mesaArch)
        s.leave = f.leave(.mesaArch, .early)
        s.drive = GoDriveInfo(arrival: f.at(l + 19), driveSeconds: 1140, driveMeters: nil, source: .planned, asOf: f.ago(25))
        s.stay = GoStayInfo(plannedDeparture: f.at(110), latestDeparture: f.at(l), cutsShortBySeconds: (110 - l) * 60, nextStopName: "Mesa Arch",
                            nextWindowKind: .blueEvening)
        s.sky = f.sky(.deadHorse, live: 72, forecast: 66, confidence: .high, trend: .steady, basis: .blended, asOfAgo: 2)
        s.weather = [f.observed(.here, agoMin: 5, temp: 6.0, cloud: 0.2, vis: 40, wind: 2.8, distance: 38),
                     f.forecastWx(.stop(Spot.deadHorse.id), agoMin: 2, temp: 6.4, cloud: 0.2, wind: 3.4)]
        s.freshness = GoFreshness(locationAsOf: f.ago(0.5), etaAsOf: f.ago(25), conditionsAsOf: f.ago(2), packBuiltAt: f.ago(270), nextRefreshAt: f.at(6))
        s.sources = ["NOAA HRRR", "KCNY METAR"]
        s.hours = f.hours(for: .deadHorse, bases: obsHours, cloud: [0.2, 0.18, 0.2, 0.26, 0.3, 0.35], temp: 6.2)
        s.sourceDetails = f.details(forecastAge: 2, obs: true, obsAge: 5)
        s.schedule = f.schedule([.mesaArch, .lodging, .fisherTowers, .delicateArch], first: (l, l + 19, .early))
        s.here = Coordinate(latitude: 38.4838, longitude: -109.7412)
        return s
    }

    private static func arrivedUndo(_ now: Date) -> GoSnapshot {
        let f = Frame(now: now, sunset: 110)
        let l = f.leaveBy(.mesaArch)
        var s = f.base(.atStop, current: .deadHorse, next: .mesaArch)
        s.leave = f.leave(.mesaArch, .early, earliest: 70)
        s.drive = GoDriveInfo(arrival: f.at(l + 19), driveSeconds: 1140, driveMeters: nil, source: .planned, asOf: f.ago(1))
        s.stay = GoStayInfo(plannedDeparture: f.at(70), latestDeparture: f.at(l), cutsShortBySeconds: nil, nextStopName: "Mesa Arch",
                            nextWindowKind: .blueEvening)
        s.sky = f.sky(.deadHorse, live: 63, forecast: 60, confidence: .medium, trend: .steady, basis: .blended, asOfAgo: 2)
        s.weather = [f.observed(.here, agoMin: 4, temp: 7.1, cloud: 0.3, vis: 35, wind: 3.2, distance: 38),
                     f.forecastWx(.stop(Spot.deadHorse.id), agoMin: 2, temp: 7.4, cloud: 0.3, wind: 3.8)]
        s.freshness = GoFreshness(locationAsOf: f.ago(0.3), etaAsOf: f.ago(1), conditionsAsOf: f.ago(2), packBuiltAt: f.ago(255), nextRefreshAt: f.at(5))
        s.undo = GoUndoInfo(toPhase: .atStop, stopID: Spot.deadHorse.id, stopName: "Dead Horse Point", expiresAt: f.at(80.0 / 60))
        s.sources = ["NOAA HRRR", "KCNY METAR"]
        s.hours = f.hours(for: .deadHorse, bases: obsHours, cloud: [0.3, 0.28, 0.3, 0.34, 0.4, 0.45], temp: 7)
        s.sourceDetails = f.details(forecastAge: 2, obs: true, obsAge: 4)
        s.schedule = f.schedule([.mesaArch, .lodging, .fisherTowers, .delicateArch], first: (l, l + 19, .early))
        s.here = Coordinate(latitude: 38.4837, longitude: -109.7411)
        return s
    }

    private static func betweenStops(_ now: Date) -> GoSnapshot {
        let f = Frame(now: now, sunset: 110)
        let l = f.leaveBy(.mesaArch, drive: 4200)
        var s = f.base(.betweenStops, next: .mesaArch)
        s.leave = f.leave(.mesaArch, drive: 4200, .early)
        s.drive = GoDriveInfo(arrival: f.at(l + 70), driveSeconds: 4200, driveMeters: 74_000, source: .live, asOf: f.ago(2))
        s.sky = f.sky(.mesaArch, live: 67, forecast: 60, confidence: .medium, trend: .rising, basis: .blended, asOfAgo: 3)
        s.weather = [f.observed(.here, agoMin: 8, temp: 6.9, cloud: 0.25, vis: 40, wind: 3.0, distance: 38),
                     f.forecastWx(.stop(Spot.mesaArch.id), agoMin: 3, temp: 6.6, cloud: 0.27, wind: 3.5)]
        s.freshness = GoFreshness(locationAsOf: f.ago(0.5), etaAsOf: f.ago(2), conditionsAsOf: f.ago(3), packBuiltAt: f.ago(262), nextRefreshAt: f.at(5))
        s.sources = ["Apple Maps", "NOAA HRRR", "KCNY METAR"]
        s.hours = f.hours(for: .mesaArch, bases: obsHours, cloud: [0.27, 0.25, 0.3, 0.35, 0.4, 0.4], temp: 6.8)
        s.sourceDetails = f.details(forecastAge: 3, obs: true, drive: true, obsAge: 8)
        s.schedule = f.schedule([.mesaArch, .lodging, .fisherTowers, .delicateArch], first: (l, l + 70, .early))
        s.here = Spot.lodging.coordinate
        return s
    }

    private static func betweenOvernight(_ now: Date) -> GoSnapshot {
        let f = Frame(now: now, sunset: 110)
        let l = f.leaveBy(.fisherTowers)
        var s = f.base(.betweenStops, next: .fisherTowers)
        s.leave = f.leave(.fisherTowers, .early, suggested: 210)
        s.drive = GoDriveInfo(arrival: f.at(l + 30), driveSeconds: 1800, driveMeters: nil, source: .planned, asOf: f.ago(10))
        s.sky = f.sky(.fisherTowers, live: nil, forecast: 67, confidence: .medium, trend: .steady, basis: .nextWindowForecast, asOfAgo: 20)
        s.weather = [f.forecastWx(.here, agoMin: 20, temp: 14.0, cloud: 0.1, wind: 1.6),
                     f.forecastWx(.stop(Spot.fisherTowers.id), agoMin: 20, temp: -1.5, cloud: 0.2, wind: 1.9)]
        s.freshness = GoFreshness(locationAsOf: f.ago(4), etaAsOf: f.ago(10), conditionsAsOf: f.ago(20), packBuiltAt: f.ago(420), nextRefreshAt: f.at(40))
        s.sources = ["NOAA HRRR", "NWS"]
        s.hours = f.hours(for: .fisherTowers, bases: nowcastHours, cloud: [0.1, 0.12, 0.15, 0.2, 0.2, 0.18], temp: 2, wind: 1.6)
        s.sourceDetails = f.details(forecastAge: 20)
        s.schedule = f.schedule([.fisherTowers, .delicateArch], first: (l, l + 30, .early))
        s.here = Spot.lodging.coordinate
        return s
    }

    private static func paused(_ now: Date) -> GoSnapshot {
        let f = Frame(now: now, sunset: 110)
        let l = f.leaveBy(.mesaArch, drive: 4200)
        var s = f.base(.paused, next: .mesaArch)
        s.leave = f.leave(.mesaArch, drive: 4200, .early)
        s.drive = GoDriveInfo(arrival: f.at(l + 70), driveSeconds: 4200, driveMeters: nil, source: .planned, asOf: f.ago(20))
        s.sky = f.sky(.mesaArch, live: 63, forecast: 60, confidence: .medium, trend: .steady, basis: .blended, asOfAgo: 18)
        s.weather = [f.observed(.here, agoMin: 18, temp: 10.8, cloud: 0.3, vis: 16, wind: 2.2, distance: 3),
                     f.forecastWx(.stop(Spot.mesaArch.id), agoMin: 18, temp: 8.9, cloud: 0.3, wind: 4.0)]
        s.freshness = GoFreshness(locationAsOf: f.ago(9), etaAsOf: f.ago(20), conditionsAsOf: f.ago(18), packBuiltAt: f.ago(320))
        s.sources = ["NOAA HRRR", "KCNY METAR"]
        s.hours = f.hours(for: .mesaArch, bases: obsHours, cloud: clearish, temp: 10.5)
        s.sourceDetails = f.details(forecastAge: 18, obs: true, obsAge: 18)
        s.schedule = f.schedule([.mesaArch, .lodging, .fisherTowers, .delicateArch], first: (l, l + 70, .early))
        s.here = moab
        return s
    }

    private static func finished(_ now: Date) -> GoSnapshot {
        let f = Frame(now: now, sunset: -1328)
        var s = f.base(.finished, next: nil)
        func stop(_ sp: Spot, _ outcome: GoTripSummary.Outcome, _ arrived: Double?, _ left: Double?, _ score: Int?) -> GoTripSummary.Stop {
            GoTripSummary.Stop(id: sp.id, number: sp.rawValue, name: sp.name, windowKind: f.window(sp)?.kind, outcome: outcome,
                               arrivedAt: arrived.map(f.at), leftAt: left.map(f.at), score: score, timeZoneIdentifier: denver)
        }
        s.summary = GoTripSummary(startedAt: f.at(-1470), endedAt: f.at(-30), stops: [
            stop(.deadHorse, .shot, -1410, -1325, 78), stop(.mesaArch, .shot, -1312, -1270, 61), stop(.lodging, .shot, -1200, -560, nil),
            stop(.fisherTowers, .skipped, nil, nil, nil), stop(.delicateArch, .missed, nil, nil, nil)], drivenMeters: 214_000)
        s.freshness = GoFreshness(locationAsOf: f.ago(30), conditionsAsOf: f.ago(150), packBuiltAt: f.ago(1800))
        s.here = moab
        return s
    }

    private static func offline(_ now: Date) -> GoSnapshot {
        let f = Frame(now: now, sunset: 110)
        var s = f.base(.driving, next: .deadHorse)
        s.leave = f.leave(.deadHorse, drive: 1700, .leaveNow)
        s.drive = GoDriveInfo(arrival: f.at(28.3), driveSeconds: 1700, driveMeters: nil, source: .offlineEstimate, asOf: now)
        s.sky = f.sky(.deadHorse, live: nil, forecast: 60, confidence: .low, trend: .unknown, basis: .forecastOnly, asOfAgo: 52,
                      notice: "No live data", stale: true)
        s.weather = [f.observed(.here, agoMin: 52, temp: 8.8, cloud: 0.3, vis: 16, wind: 2.5, distance: 3),
                     f.forecastWx(.stop(Spot.deadHorse.id), agoMin: 52, temp: 7.0, cloud: 0.3, wind: 4.0)]
        s.freshness = GoFreshness(locationAsOf: f.ago(2), etaAsOf: f.ago(26), conditionsAsOf: f.ago(52), packBuiltAt: f.ago(230), isOffline: true,
                                  etaIsStale: true, conditionsAreStale: true, nextRefreshAt: f.at(5))
        s.sources = ["Offline estimate", "NOAA HRRR"]
        s.hours = f.hours(for: .deadHorse, bases: [], cloud: clearish, temp: 8.5)
        s.sourceDetails = f.details(forecastAge: 52, stale: true)
        s.schedule = f.schedule(allSpots, first: (f.leaveBy(.deadHorse, drive: 1700), 28.3, .leaveNow))
        s.here = Coordinate(latitude: 38.6254, longitude: -109.6932)
        return s
    }

    private static func stale(_ now: Date) -> GoSnapshot {
        let f = Frame(now: now, sunset: 120)
        let l = f.leaveBy(.deadHorse)
        var s = f.base(.betweenStops, next: .deadHorse)
        s.generatedAt = f.ago(180)
        s.leave = f.leave(.deadHorse, .early)
        s.drive = GoDriveInfo(arrival: f.at(l + 46), driveSeconds: 2760, driveMeters: nil, source: .planned, asOf: f.ago(185))
        s.sky = f.sky(.deadHorse, live: 66, forecast: 62, confidence: .medium, trend: .steady, basis: .blended, asOfAgo: 182, stale: true)
        s.weather = [f.observed(.here, agoMin: 182, temp: 11.0, cloud: 0.28, vis: 16, wind: 2.3, distance: 3),
                     f.forecastWx(.stop(Spot.deadHorse.id), agoMin: 182, temp: 9.0, cloud: 0.3, wind: 4.0)]
        s.freshness = GoFreshness(locationAsOf: f.ago(181), etaAsOf: f.ago(185), conditionsAsOf: f.ago(182), packBuiltAt: f.ago(500), etaIsStale: true,
                                  conditionsAreStale: true, nextRefreshAt: f.ago(165))
        s.sources = ["NOAA HRRR", "KCNY METAR"]
        s.hours = Frame(now: f.ago(180), sunset: 290).hours(for: .deadHorse, bases: obsHours, cloud: clearish, temp: 15)
        s.sourceDetails = f.details(forecastAge: 182, obs: true, obsAge: 182, stale: true)
        s.schedule = f.schedule(allSpots, first: (l, l + 46, .early))
        s.here = moab
        return s
    }

    private static func alert(_ now: Date) -> GoSnapshot {
        let f = Frame(now: now, sunset: 110)
        var s = f.base(.driving, next: .deadHorse)
        s.leave = f.leave(.deadHorse, drive: 1500, .leaveNow)
        s.drive = GoDriveInfo(arrival: f.at(25), driveSeconds: 1500, driveMeters: 33_000, source: .live, asOf: f.ago(1))
        s.sky = f.sky(.deadHorse, live: 47, forecast: 63, confidence: .medium, trend: .falling, basis: .blended, asOfAgo: 2,
                      notice: "Wind and blowing dust lower the score")
        s.weather = [f.observed(.here, agoMin: 4, temp: 11.5, cloud: 0.45, vis: 9, wind: 9.8, distance: 6),
                     f.forecastWx(.stop(Spot.deadHorse.id), agoMin: 2, temp: 9.4, cloud: 0.5, vis: 12, precip: 0.05, wind: 12.5)]
        s.alerts = [GoAlertInfo(id: "urn:oid:2.49.0.1.840.0.sample.wind", event: "Wind Advisory",
                                headline: "Wind Advisory in effect until 6:00 PM MST for Grand and San Juan counties", severity: "Moderate", ends: f.at(210)),
                    GoAlertInfo(id: "urn:oid:2.49.0.1.840.0.sample.redflag", event: "Red Flag Warning",
                                headline: "Red Flag Warning for the Canyonlands region: low humidity and strong winds", severity: "Severe", ends: f.at(300))]
        s.freshness = GoFreshness(locationAsOf: f.ago(0.5), etaAsOf: f.ago(1), conditionsAsOf: f.ago(2), packBuiltAt: f.ago(245), nextRefreshAt: f.at(3))
        s.sources = ["Apple Maps", "NOAA HRRR", "KCNY METAR", "NWS"]
        s.hours = f.hours(for: .deadHorse, bases: obsHours, cloud: [0.45, 0.5, 0.55, 0.5, 0.45, 0.4], temp: 10.5, wind: 10)
        s.sourceDetails = f.details(forecastAge: 2, obs: true, alerts: true, drive: true, obsAge: 4)
        s.schedule = f.schedule(allSpots, first: (f.leaveBy(.deadHorse, drive: 1500), 25, .leaveNow))
        s.here = Coordinate(latitude: 38.6102, longitude: -109.6204)
        return s
    }

    private static func powerSaving(_ now: Date) -> GoSnapshot {
        let f = Frame(now: now, sunset: 110)
        var s = f.base(.driving, next: .mesaArch)
        s.leave = f.leave(.mesaArch, drive: 2400, .early)
        s.drive = GoDriveInfo(arrival: f.at(40), driveSeconds: 2400, driveMeters: 52_000, source: .live, asOf: f.ago(6))
        s.sky = f.sky(.mesaArch, live: 61, forecast: 62, confidence: .medium, trend: .steady, basis: .blended, asOfAgo: 9)
        s.weather = [f.observed(.here, agoMin: 11, temp: 9.3, cloud: 0.35, vis: 20, wind: 3.1, distance: 12),
                     f.forecastWx(.stop(Spot.mesaArch.id), agoMin: 9, temp: 7.6, cloud: 0.35, wind: 4.4)]
        s.freshness = GoFreshness(locationAsOf: f.ago(2), etaAsOf: f.ago(6), conditionsAsOf: f.ago(9), packBuiltAt: f.ago(240), isPowerSaving: true,
                                  nextRefreshAt: f.at(9))
        s.sources = ["Apple Maps", "NOAA HRRR", "KCNY METAR"]
        s.hours = f.hours(for: .mesaArch, bases: obsHours, cloud: [0.35, 0.33, 0.35, 0.4, 0.45, 0.5], temp: 9)
        s.sourceDetails = f.details(forecastAge: 9, obs: true, drive: true, obsAge: 11)
        s.schedule = f.schedule([.mesaArch, .lodging, .fisherTowers, .delicateArch], first: (f.leaveBy(.mesaArch, drive: 2400), 40, .early))
        s.here = Coordinate(latitude: 38.5911, longitude: -109.6012)
        return s
    }

    private static func nextWindowForecast(_ now: Date) -> GoSnapshot {
        let f = Frame(now: now, sunset: 110)
        let l = f.leaveBy(.delicateArch)
        var s = f.base(.betweenStops, next: .delicateArch)
        s.leave = f.leave(.delicateArch, .early)
        s.drive = GoDriveInfo(arrival: f.at(l + 50), driveSeconds: 3000, driveMeters: nil, source: .planned, asOf: f.ago(30))
        s.sky = f.sky(.delicateArch, live: nil, forecast: 71, confidence: .medium, trend: .rising, basis: .nextWindowForecast, asOfAgo: 25)
        s.weather = [f.observed(.here, agoMin: 25, temp: 15.0, cloud: 0.15, vis: 40, wind: 2.0, distance: 24),
                     f.forecastWx(.stop(Spot.delicateArch.id), agoMin: 25, temp: 8.2, cloud: 0.2, wind: 2.8)]
        s.freshness = GoFreshness(locationAsOf: f.ago(6), etaAsOf: f.ago(30), conditionsAsOf: f.ago(25), packBuiltAt: f.ago(900), nextRefreshAt: f.at(30))
        s.sources = ["NOAA HRRR", "KCNY METAR"]
        s.hours = f.hours(for: .delicateArch, bases: obsHours, cloud: [0.15, 0.18, 0.2, 0.22, 0.25, 0.3], temp: 15)
        s.sourceDetails = f.details(forecastAge: 25, obs: true, obsAge: 25)
        s.schedule = f.schedule([.delicateArch], first: (l, l + 50, .early))
        s.here = Coordinate(latitude: 38.7143, longitude: -109.3116)
        return s
    }
}
