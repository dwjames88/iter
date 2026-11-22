import Testing
import Foundation
import IterCore
@testable import IterAstro

/// More almanac cross-checks beyond `AstronomyTests`: three dates (14 Feb, 5 Jun, 22 Sep 2026) at five places that
/// cover a mid-latitude US spot (Flagstaff), the southern hemisphere (Cape Town, Buenos Aires) and high latitudes
/// (Anchorage, Tromso). Reference values are the USNO Astronomical Applications API,
/// `https://aa.usno.navy.mil/api/rstt/oneday?date=YYYY-MM-DD&coords=LAT,LON&tz=OFFSET`, fetched 2026-10-07 with the
/// `tz` given in each case. USNO rounds to the minute, so the sun tolerance is 1.5 minutes. A nil value means USNO
/// lists no such event that day (for example Anchorage's civil dusk on 5 Jun, which falls after local midnight).
@Suite("Almanac cross-checks")
struct AlmanacTests {
    struct Case: Sendable {
        let name: String, zone: String, lat: Double, lon: Double, day: String, offset: Int
        let civilDawn: String?, sunrise: String?, transit: String?, sunset: String?, civilDusk: String?
        let moonRise: String?, moonSet: String?
    }

    static let cases: [Case] = [
        Case(name: "Flagstaff", zone: "America/Phoenix", lat: 35.2, lon: -111.65, day: "2026-02-14", offset: -7,
             civilDawn: "06:48", sunrise: "07:14", transit: "12:41", sunset: "18:08", civilDusk: "18:34",
             moonRise: "05:41", moonSet: "15:26"),
        Case(name: "Flagstaff", zone: "America/Phoenix", lat: 35.2, lon: -111.65, day: "2026-06-05", offset: -7,
             civilDawn: "04:43", sunrise: "05:12", transit: "12:25", sunset: "19:38", civilDusk: "20:08",
             moonRise: "23:48", moonSet: "09:42"),
        Case(name: "Flagstaff", zone: "America/Phoenix", lat: 35.2, lon: -111.65, day: "2026-09-22", offset: -7,
             civilDawn: "05:49", sunrise: "06:15", transit: "12:19", sunset: "18:23", civilDusk: "18:48",
             moonRise: "16:24", moonSet: "02:05"),
        Case(name: "CapeTown", zone: "Africa/Johannesburg", lat: -33.92, lon: 18.42, day: "2026-02-14", offset: 2,
             civilDawn: "05:54", sunrise: "06:20", transit: "13:00", sunset: "19:40", civilDusk: "20:06",
             moonRise: "02:57", moonSet: "18:01"),
        Case(name: "CapeTown", zone: "Africa/Johannesburg", lat: -33.92, lon: 18.42, day: "2026-06-05", offset: 2,
             civilDawn: "07:18", sunrise: "07:45", transit: "12:45", sunset: "17:44", civilDusk: "18:12",
             moonRise: "22:13", moonSet: "11:38"),
        Case(name: "CapeTown", zone: "Africa/Johannesburg", lat: -33.92, lon: 18.42, day: "2026-09-22", offset: 2,
             civilDawn: "06:11", sunrise: "06:36", transit: "12:39", sunset: "18:43", civilDusk: "19:08",
             moonRise: "14:37", moonSet: "04:12"),
        Case(name: "BuenosAires", zone: "America/Argentina/Buenos_Aires", lat: -34.6, lon: -58.38, day: "2026-02-14", offset: -3,
             civilDawn: "06:00", sunrise: "06:27", transit: "13:08", sunset: "19:48", civilDusk: "20:14",
             moonRise: "03:15", moonSet: "18:19"),
        Case(name: "BuenosAires", zone: "America/Argentina/Buenos_Aires", lat: -34.6, lon: -58.38, day: "2026-06-05", offset: -3,
             civilDawn: "07:26", sunrise: "07:54", transit: "12:52", sunset: "17:50", civilDusk: "18:18",
             moonRise: "22:32", moonSet: "11:53"),
        Case(name: "BuenosAires", zone: "America/Argentina/Buenos_Aires", lat: -34.6, lon: -58.38, day: "2026-09-22", offset: -3,
             civilDawn: "06:18", sunrise: "06:43", transit: "12:46", sunset: "18:50", civilDusk: "19:15",
             moonRise: "14:56", moonSet: "04:28"),
        Case(name: "Anchorage", zone: "America/Anchorage", lat: 61.22, lon: -149.9, day: "2026-02-14", offset: -9,
             civilDawn: "07:58", sunrise: "08:44", transit: "13:14", sunset: "17:44", civilDusk: "18:30",
             moonRise: "09:01", moonSet: "13:28"),
        Case(name: "Anchorage", zone: "America/Anchorage", lat: 61.22, lon: -149.9, day: "2026-06-05", offset: -8,
             civilDawn: "02:28", sunrise: "04:30", transit: "13:58", sunset: "23:28", civilDusk: nil /* USNO lists 01:28, the tail of 4 Jun's evening; this day's ends after local midnight */,
             moonRise: "02:39", moonSet: "09:43"),
        Case(name: "Anchorage", zone: "America/Anchorage", lat: 61.22, lon: -149.9, day: "2026-09-22", offset: -8,
             civilDawn: "07:01", sunrise: "07:44", transit: "13:52", sunset: "19:59", civilDusk: "20:42",
             moonRise: "19:26", moonSet: "01:53"),
        Case(name: "Tromso", zone: "Europe/Oslo", lat: 69.65, lon: 18.96, day: "2026-02-14", offset: 1,
             civilDawn: "07:12", sunrise: "08:20", transit: "11:58", sunset: "15:38", civilDusk: "16:47",
             moonRise: nil, moonSet: nil),
        Case(name: "Tromso", zone: "Europe/Oslo", lat: 69.65, lon: 18.96, day: "2026-06-05", offset: 2,
             civilDawn: nil, sunrise: nil, transit: "12:43", sunset: nil, civilDusk: nil,
             moonRise: nil, moonSet: nil),
        Case(name: "Tromso", zone: "Europe/Oslo", lat: 69.65, lon: 18.96, day: "2026-09-22", offset: 2,
             civilDawn: "05:23", sunrise: "06:24", transit: "12:37", sunset: "18:48", civilDusk: "19:48",
             moonRise: "20:00", moonSet: "23:45"),
    ]

    static func at(_ day: String, _ hhmm: String, offset: Int) -> Date {
        let p = hhmm.split(separator: ":").map { Int($0)! }
        return LocalDay(iso: day)!.at(hour: p[0], minute: p[1], in: TimeZone(secondsFromGMT: offset * 3600)!)
    }

    static func gap(_ got: Date?, _ day: String, _ want: String, offset: Int) -> Double {
        guard let got else { return .infinity }
        return abs(got.timeIntervalSince(at(day, want, offset: offset))) / 60
    }

    @Test(arguments: cases)
    func sunMatchesUSNO(c: Case) {
        let tz = TimeZone(identifier: c.zone)!
        let e = Astronomy().sunEvents(on: LocalDay(iso: c.day)!, at: Coordinate(latitude: c.lat, longitude: c.lon), in: tz)
        let pairs: [(String, Date?, String?)] = [("civilDawn", e.civilDawn, c.civilDawn), ("sunrise", e.sunrise, c.sunrise),
                                                 ("noon", e.solarNoon, c.transit), ("sunset", e.sunset, c.sunset), ("civilDusk", e.civilDusk, c.civilDusk)]
        for (label, got, want) in pairs {
            guard let want else {
                if label == "civilDusk" || label == "civilDawn" || label == "sunrise" || label == "sunset" { #expect(got == nil, "\(c.name) \(c.day) \(label) should be absent") }
                continue
            }
            let err = Self.gap(got, c.day, want, offset: c.offset)
            #expect(err <= 1.5, "\(c.name) \(c.day) \(label) off by \(err) min")
        }
    }

    @Test(arguments: cases)
    func moonMatchesUSNO(c: Case) {
        let tz = TimeZone(identifier: c.zone)!
        let e = Astronomy().moonEvents(on: LocalDay(iso: c.day)!, at: Coordinate(latitude: c.lat, longitude: c.lon), in: tz)
        for (label, got, want) in [("rise", e.rise, c.moonRise), ("set", e.set, c.moonSet)] {
            guard let want else { #expect(got == nil, "\(c.name) \(c.day) moon\(label) should be absent"); continue }
            let err = Self.gap(got, c.day, want, offset: c.offset)
            #expect(err <= 3, "\(c.name) \(c.day) moon\(label) off by \(err) min")
        }
    }
}
