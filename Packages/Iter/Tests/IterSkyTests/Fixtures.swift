import Foundation
import IterModel
import IterAstro
@testable import IterSky

let utc = TimeZone(identifier: "UTC")!

/// A hand-written ephemeris: the same sun times every day (hours after local midnight), a fixed moon.
struct FixedEphemeris: Ephemeris {
    var sun: @Sendable (LocalDay) -> SunEvents = FixedEphemeris.standardDay
    var moonAltitude: Double = -30
    var illumination: Double = 0.0
    /// The sun's position at an instant; the default sits 10 degrees up in the east for ever (above any flat horizon).
    var sunPosition: @Sendable (Date) -> SkyPosition = { _ in SkyPosition(altitude: 10, azimuth: 90) }

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
    func sunPosition(at date: Date, coordinate: Coordinate) -> SkyPosition { sunPosition(date) }
    func moonPosition(at date: Date, coordinate: Coordinate) -> SkyPosition { SkyPosition(altitude: moonAltitude, azimuth: 180) }
    func moonPhase(at date: Date) -> MoonPhase { MoonPhase(illumination: illumination, cycle: illumination / 2) }
    func moonEvents(on day: LocalDay, at coordinate: Coordinate, in timeZone: TimeZone) -> MoonEvents { MoonEvents(day: day, rise: nil, set: nil) }
}

let testDay = LocalDay(year: 2026, month: 10, day: 12)

func makePlace(_ name: String = "place", lat: Double = 40, lon: Double = -110, zone: String = "UTC", horizon: HorizonProfile? = nil,
               best: [BestLight] = []) -> Place {
    Place(name: name, coordinate: Coordinate(latitude: lat, longitude: lon), timeZoneIdentifier: zone, category: .landscape,
          bestLight: best, origin: .user, horizon: horizon)
}

func place(_ id: String, _ lat: Double, _ lon: Double, _ zone: String) -> Place {
    makePlace(id, lat: lat, lon: lon, zone: zone)
}

let testSource: SourceID = "test.forecast"

func provenance(fetchedAt: Date, issuedAt: Date? = nil, model: String? = nil) -> Provenance {
    Provenance(source: testSource, model: model, issuedAt: issuedAt, fetchedAt: fetchedAt, licence: LicenceTag(key: "test", mayStore: true))
}

/// Weather for one hour. Visibility is in metres here (as the old tests wrote it) and converted to km on the way in.
struct Wx {
    var total: Double? = 0.3, low: Double? = 0.1, mid: Double? = 0.3, high: Double? = 0.3
    var rain: Double? = 0.0, visibility: Double? = 20_000.0
    var mm: Double?
    var aod: Double? = 0.05
    var smoke: Double?
    var rh: Double? = 50
    var wind: Double? = 1.4
    var gust: Double?
    var temp: Double? = 12
    var dew: Double?
}

func hourly(_ date: Date, _ w: Wx) -> HourlyConditions {
    HourlyConditions(time: date, cloudTotal: w.total, cloudLow: w.low, cloudMid: w.mid, cloudHigh: w.high,
                     precipChance: w.rain, precipMm: w.mm, visibilityKm: w.visibility.map { $0 / 1000 },
                     tempC: w.temp, dewpointC: w.dew, rhPercent: w.rh, windMs: w.wind, gustMs: w.gust,
                     aod550: w.aod, smokeUgm3: w.smoke)
}

/// A forecast of the given weather for every hour of `day` and the day either side, fetched at `fetchedAt`.
func forecast(day: LocalDay = testDay, fetchedAt: Date, days: Int = 1, model: String? = nil, ttl: TimeInterval = Freshness.defaultTTL,
              horizon: HorizonProfile? = nil, _ wx: @Sendable (Date) -> Wx) -> ForecastSkyInputs {
    let start = day.adding(days: -1).start(in: utc)
    let count = (days + 2) * 24
    let hours = (0..<count).map { i -> HourlyConditions in
        let date = start.addingTimeInterval(Double(i) * 3600)
        return hourly(date, wx(date))
    }
    return ForecastSkyInputs(hourly: HourlySeries(hours: hours), provenance: provenance(fetchedAt: fetchedAt, model: model), ttl: ttl,
                             horizon: horizon)
}

func uniform(_ w: Wx, fetchedAt: Date, day: LocalDay = testDay) -> ForecastSkyInputs { forecast(day: day, fetchedAt: fetchedAt) { _ in w } }

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

/// A flat 8-day forecast used by the equivalence and persistence tests, covering `from` for eight days.
func eightDayInputs(for place: Place, from start: Date) -> ForecastSkyInputs {
    let hours = (0..<(8 * 24)).map { i in
        HourlyConditions(time: start.addingTimeInterval(Double(i) * 3600), cloudTotal: 0.35, cloudLow: 0.05, cloudMid: 0.3, cloudHigh: 0.3,
                         precipChance: 0.1, visibilityKm: 20, tempC: 12, rhPercent: 50, windMs: 1.4)
    }
    return ForecastSkyInputs(hourly: HourlySeries(hours: hours), provenance: provenance(fetchedAt: start))
}
