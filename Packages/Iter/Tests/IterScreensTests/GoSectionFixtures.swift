import Foundation
import IterModel
import IterGoActivity

/// Small inline snapshots for the section tests and renders (a Moab evening, America/Denver, 2026-06-20).
enum GoSectionFixtures {
    static let zone = TimeZone(identifier: "America/Denver")!
    static let locale = Locale(identifier: "en_GB")
    static let usLocale = Locale(identifier: "en_US")

    static func at(_ hour: Int, _ minute: Int) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        return c.date(from: DateComponents(year: 2026, month: 6, day: 20, hour: hour, minute: minute))!
    }

    static let now = at(16, 23)

    static func stop(_ number: Int, _ name: String, kind: LightWindowKind? = .goldenEvening, start: Date? = nil, end: Date? = nil,
                     setUp: Date? = nil) -> GoStopInfo {
        GoStopInfo(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\(number)")!, number: number, name: name, kind: .light,
                   dayIndex: 0, coordinate: Coordinate(latitude: 38.57, longitude: -109.55), timeZoneIdentifier: zone.identifier,
                   windowKind: kind, windowStart: start ?? at(18, 20), windowEnd: end ?? at(19, 0), setUpBy: setUp ?? at(18, 5))
    }

    static let delicate = stop(2, "Delicate Arch")
    static let deadHorse = stop(3, "Dead Horse Point", kind: .blueEvening, start: at(20, 20), end: at(20, 55), setUp: at(20, 5))

    static func sky(live: Int? = 72, forecast: Int? = 64, trend: GoTrend = .rising, basis: GoSkyInfo.Basis = .blended,
                    confidence: GoConfidence = .medium, kind: LightWindowKind = .goldenEvening) -> GoSkyInfo {
        GoSkyInfo(stopID: delicate.id, windowKind: kind, windowStart: at(18, 20), windowEnd: at(19, 0), liveScore: live,
                  forecastScore: forecast, band: live.map { $0 >= 70 ? .great : .good }, confidence: confidence, trend: trend,
                  basis: basis, asOf: at(16, 15), notice: nil, isStale: false)
    }

    static func obs(here: Bool, basis: GoWeatherInfo.Basis = .observation) -> GoWeatherInfo {
        GoWeatherInfo(subject: here ? .here : .stop(delicate.id), basis: basis, tempC: 24, cloudTotal: 0.4, visibilityKm: 16,
                      precipChance: 0.1, windMs: 5, stationName: "KCNY", stationDistanceKm: 12, asOf: at(16, 15))
    }

    static func hours() -> [GoHourInfo] {
        (0..<6).map { i in
            GoHourInfo(time: at(16 + i, 0), basis: i < 2 ? .nowcast : .forecast, cloudTotal: Double(30 + i * 8) / 100,
                       precipChance: Double(i * 5) / 100, tempC: Double(26 - i), isInWindow: i == 2)
        }
    }

    static let sources = [
        GoSourceInfo(role: "Cloud", name: "NOAA HRRR", tier: .military, producer: "US Air Force", asOf: at(16, 0), distanceKm: nil),
        GoSourceInfo(role: "Observation", name: "KCNY METAR", tier: .government, asOf: at(16, 15), distanceKm: 12),
        GoSourceInfo(role: "Drive time", name: "Apple Maps", tier: .device, asOf: at(16, 20), isStale: false),
    ]

    static func before(status: GoLeaveStatus = .early, leaveBy: Date = at(17, 5), late: TimeInterval? = nil,
                       source: GoETASource = .live, suggested: Date? = nil, earliest: Date? = nil) -> GoSnapshot {
        GoSnapshot(generatedAt: now, tripID: UUID(), tripName: "Moab", runID: UUID(), phase: .betweenStops, next: delicate,
                   remainingCount: 1,
                   leave: GoLeaveInfo(leaveBy: leaveBy, status: status, lateBySeconds: late, earliestDeparture: earliest, suggestedDeparture: suggested),
                   drive: GoDriveInfo(arrival: at(17, 53), driveSeconds: 48 * 60, driveMeters: 52_000, source: source, asOf: now),
                   sky: sky(), weather: [obs(here: true), obs(here: false)], hours: hours(), sourceDetails: sources)
    }

    static func driving(status: GoLeaveStatus = .early, late: TimeInterval? = nil, alternative: Bool = false) -> GoSnapshot {
        var s = before(status: status, late: late)
        s.phase = .driving
        s.drive = GoDriveInfo(arrival: at(17, 42), driveSeconds: 38 * 60, driveMeters: 41_000, source: .live, asOf: now)
        if alternative {
            s.alternative = GoAlternativeInfo(stopID: deadHorse.id, name: "Dead Horse Point", windowKind: .blueEvening,
                                              windowStart: at(18, 20), projectedArrival: at(18, 5), makesSetUp: true)
        }
        return s
    }

    static func atStop(cuts: TimeInterval? = nil) -> GoSnapshot {
        var s = before()
        s.phase = .atStop
        s.current = delicate
        s.next = deadHorse
        s.stay = GoStayInfo(plannedDeparture: at(18, 52), latestDeparture: cuts == nil ? nil : at(18, 40), cutsShortBySeconds: cuts,
                            nextStopName: deadHorse.name, nextWindowKind: .blueEvening)
        return s
    }
}
