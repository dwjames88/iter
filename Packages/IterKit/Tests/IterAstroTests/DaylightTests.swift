import Testing
import Foundation
import IterCore
@testable import IterAstro

@Suite struct DaylightTests {
    /// 2026-03-20 12:00 UTC, two and a half hours before the March equinox.
    private let equinoxNoon = Date(timeIntervalSince1970: 1_774_008_000)
    private let juneSolstice = Date(timeIntervalSince1970: 1_782_043_200)   // 2026-06-21 12:00 UTC
    private let decemberSolstice = Date(timeIntervalSince1970: 1_797_854_400) // 2026-12-21 12:00 UTC

    @Test func subsolarPointAtEquinoxNoonUTC() {
        let p = Daylight.subsolarPoint(at: equinoxNoon)
        #expect(abs(p.latitude) < 0.5)
        #expect(abs(p.longitude) < 5)   // equation of time stays within a few degrees
    }

    @Test func subsolarPointFollowsTheSeasonsAndTheClock() {
        #expect(Daylight.subsolarPoint(at: juneSolstice).latitude > 23)
        #expect(Daylight.subsolarPoint(at: decemberSolstice).latitude < -23)
        let six = Daylight.subsolarPoint(at: equinoxNoon.addingTimeInterval(6 * 3600))
        #expect(abs(six.longitude - -90) < 5)   // the Sun moves west 15 degrees an hour
    }

    @Test func nightCoversTheAntipodeNotTheSubsolarPoint() {
        let sub = Daylight.subsolarPoint(at: equinoxNoon)
        let polys = Daylight.nightPolygons(at: equinoxNoon)
        var antiLon = sub.longitude + 180
        if antiLon > 180 { antiLon -= 360 }
        #expect(covers(polys, Coordinate(latitude: -sub.latitude, longitude: antiLon)))
        #expect(!covers(polys, sub))
        #expect(covers(polys, Coordinate(latitude: 0, longitude: 179)))
        #expect(covers(polys, Coordinate(latitude: 0, longitude: -179)))
        #expect(!covers(polys, Coordinate(latitude: 0, longitude: 0)))
    }

    @Test func geometryStaysInRangeAndNeverStripes() {
        for date in [equinoxNoon, juneSolstice, decemberSolstice, equinoxNoon.addingTimeInterval(7 * 3600),
                     equinoxNoon.addingTimeInterval(13 * 3600), equinoxNoon.addingTimeInterval(19 * 3600)] {
            for h in [0.0, -6, -12, -18] {
                let polys = Daylight.nightPolygons(at: date, sunAltitude: h)
                #expect(!polys.isEmpty)
                for poly in polys {
                    for (i, c) in poly.enumerated() {
                        #expect(c.longitude >= -180 && c.longitude <= 180 && abs(c.latitude) <= 90)
                        let next = poly[(i + 1) % poly.count]
                        // A long edge would draw a stripe across the map. The only legitimate ones lie within a few degrees
                        // of a pole (the line itself runs through it at the equinox) or run down a cut meridian.
                        let jump = abs(next.longitude - c.longitude)
                        let nearPole = abs(c.latitude) > 86 && abs(next.latitude) > 86
                        #expect(jump < 30 || nearPole || c.longitude == next.longitude, "\(c) -> \(next)")
                    }
                }
            }
        }
    }

    @Test func polygonsAgreeWithTheSunsAltitude() {
        for (date, h) in [(equinoxNoon, 0.0), (juneSolstice, 0), (decemberSolstice, -6), (equinoxNoon.addingTimeInterval(17 * 3600), -12),
                          (juneSolstice.addingTimeInterval(9 * 3600), -18)] {
            let polys = Daylight.nightPolygons(at: date, sunAltitude: h, step: 1)
            let jd = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
            var checked = 0
            for lat in stride(from: -80.0, through: 80, by: 7) {
                for lon in stride(from: -177.0, through: 177, by: 9) {
                    let alt = SolarCoordinates.altitude(unix: date.timeIntervalSince1970, latitude: lat, longitude: lon)
                    _ = jd
                    if abs(alt - h) < 1.5 { continue }   // too close to the line for a polygon with straight edges
                    #expect(covers(polys, Coordinate(latitude: lat, longitude: lon)) == (alt < h), "lat \(lat) lon \(lon) alt \(alt) h \(h)")
                    checked += 1
                }
            }
            #expect(checked > 200)
        }
    }

    @Test func solsticeNightHoldsAPole() {
        let june = Daylight.nightPolygons(at: juneSolstice)
        #expect(june.flatMap { $0 }.contains { $0.latitude <= -89 })      // the southern winter pole is in the dark
        #expect(!june.flatMap { $0 }.contains { $0.latitude >= 89 })
        let december = Daylight.nightPolygons(at: decemberSolstice)
        #expect(december.flatMap { $0 }.contains { $0.latitude >= 89 })
    }

    @Test func aCapAcrossTheAntimeridianIsCutInTwo() {
        // 12:00 UTC at the equinox puts the night centre on the antimeridian: its disc spans both edges.
        let polys = Daylight.nightPolygons(at: equinoxNoon, sunAltitude: -12)
        #expect(polys.count == 2)
        #expect(polys.contains { $0.contains { $0.longitude == 180 } } && polys.contains { $0.contains { $0.longitude == -180 } })
    }

    /// Planar even-odd test in the map's own latitude/longitude plane.
    private func covers(_ polys: [[Coordinate]], _ c: Coordinate) -> Bool {
        polys.contains { poly in
            var inside = false
            var j = poly.count - 1
            for i in poly.indices {
                let a = poly[i], b = poly[j]
                if (a.latitude > c.latitude) != (b.latitude > c.latitude),
                   c.longitude < (b.longitude - a.longitude) * (c.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude {
                    inside.toggle()
                }
                j = i
            }
            return inside
        }
    }
}
