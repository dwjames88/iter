import Foundation
import IterCore
@testable import IterLight

let utc = TimeZone(identifier: "UTC")!

/// A hand-written ephemeris: the same sun times every day (hours after local midnight), a fixed moon.
struct FixedEphemeris: Ephemeris {
    var sun: @Sendable (LocalDay) -> SunEvents = FixedEphemeris.standardDay
    var moonAltitude: Double = -30
    var illumination: Double = 0.0

    static func at(_ day: LocalDay, _ hour: Double) -> Date {
        day.start(in: utc).addingTimeInterval(hour * 3600)
    }

    /// Mid-latitude equinox-like day: sunrise 06:12, sunset 18:20, night 20:10 to 23:10.
    static let standardDay: @Sendable (LocalDay) -> SunEvents = { d in
        SunEvents(day: d, kind: .normal, solarNoon: at(d, 12.0),
                  astronomicalDawn: at(d, 4.5), nauticalDawn: at(d, 5.17), civilDawn: at(d, 5.67),
                  sunrise: at(d, 6.2), goldenMorningEnd: at(d, 7.0), goldenEveningStart: at(d, 17.5),
                  sunset: at(d, 18.333), civilDusk: at(d, 18.833), nauticalDusk: at(d, 19.5), astronomicalDusk: at(d, 20.167))
    }

    func sunEvents(on day: LocalDay, at coordinate: Coordinate, in timeZone: TimeZone) -> SunEvents { sun(day) }
    func sunPosition(at date: Date, coordinate: Coordinate) -> SkyPosition { SkyPosition(altitude: 10, azimuth: 90) }
    func moonPosition(at date: Date, coordinate: Coordinate) -> SkyPosition { SkyPosition(altitude: moonAltitude, azimuth: 180) }
    func moonPhase(at date: Date) -> MoonPhase { MoonPhase(illumination: illumination, cycle: illumination / 2) }
    func moonEvents(on day: LocalDay, at coordinate: Coordinate, in timeZone: TimeZone) -> MoonEvents { MoonEvents(day: day, rise: nil, set: nil) }
}

let testDay = LocalDay(year: 2026, month: 10, day: 12)

func makeSpot(_ id: String = "spot", lat: Double = 40, lon: Double = -110, walk: Int? = 10, best: [BestLight] = []) -> Spot {
    Spot(id: id, name: id, locality: "", coordinate: Coordinate(latitude: lat, longitude: lon), timeZoneIdentifier: "UTC",
         category: .landscape, bestLight: best, walkInMinutes: walk, origin: .user)
}

struct Wx {
    var total = 0.3, low: Double? = 0.1, mid: Double? = 0.3, high: Double? = 0.3
    var rain = 0.0, visibility = 20_000.0
}

/// A forecast of identical weather for every hour of `day` and the day either side, fetched at `fetchedAt`.
func forecast(day: LocalDay = testDay, fetchedAt: Date, days: Int = 1, _ wx: @Sendable (Date) -> Wx) -> Forecast {
    let start = day.adding(days: -1).start(in: utc)
    let count = (days + 2) * 24
    let hours = (0..<count).map { i -> HourlyConditions in
        let date = start.addingTimeInterval(Double(i) * 3600)
        let w = wx(date)
        return HourlyConditions(date: date, cloudCover: w.total, cloudLow: w.low, cloudMid: w.mid, cloudHigh: w.high,
                                precipitationChance: w.rain, visibilityMeters: w.visibility, windSpeedKph: 5, temperatureC: 12,
                                humidity: 0.5, symbolName: "sun.max", condition: "clear")
    }
    return Forecast(coordinate: Coordinate(latitude: 40, longitude: -110), hours: hours, days: [], fetchedAt: fetchedAt, source: .appleWeather)
}

func uniform(_ w: Wx, fetchedAt: Date, day: LocalDay = testDay) -> Forecast { forecast(day: day, fetchedAt: fetchedAt) { _ in w } }

/// Noon of the day before: all test windows are in the future, lead about 18-36 h.
var now0: Date { FixedEphemeris.at(testDay.adding(days: -1), 12) }

struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
