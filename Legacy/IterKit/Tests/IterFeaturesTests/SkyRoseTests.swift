import Foundation
import CoreGraphics
import Testing
import IterCore
import IterAstro
@testable import IterFeatures

private let denver = TimeZone(identifier: "America/Denver")!
private let oslo = TimeZone(identifier: "Europe/Oslo")!
private let mesa = Coordinate(latitude: 38.389, longitude: -109.8677)
private let tromsoCoord = Coordinate(latitude: 69.65, longitude: 18.96)

private func rose(on day: LocalDay, at coordinate: Coordinate, in zone: TimeZone, facing: Double?) -> SkyRose {
    let astro = Astronomy()
    func samples(_ body: CelestialBody) -> [SkyRose.Sample] {
        astro.path(of: body, on: day, at: coordinate, in: zone, everyMinutes: 10).map { SkyRose.Sample(date: $0.date, position: $0.position) }
    }
    return SkyRose.make(sun: samples(.sun), moon: samples(.moon),
                        sunEvents: astro.sunEvents(on: day, at: coordinate, in: zone),
                        moonEvents: astro.moonEvents(on: day, at: coordinate, in: zone), facing: facing,
                        ephemeris: astro, coordinate: coordinate,
                        dayStart: day.start(in: zone), dayEnd: day.adding(days: 1).start(in: zone))
}

private let oct6 = LocalDay(year: 2026, month: 10, day: 6)
private let jun21 = LocalDay(year: 2026, month: 6, day: 21)
private let dec10 = LocalDay(year: 2026, month: 12, day: 10)

private func near(_ a: CGPoint, _ b: CGPoint, _ tol: CGFloat) -> Bool { hypot(a.x - b.x, a.y - b.y) <= tol }

@Suite struct SkyRoseTests {
    // MARK: Projection

    @Test func projectionPlacesTheCardinalPoints() {
        let p = RoseProjection(center: CGPoint(x: 100, y: 100), radius: 80)
        #expect(near(p.point(azimuth: 0, altitude: 0), CGPoint(x: 100, y: 20), 1e-9))
        #expect(near(p.point(azimuth: 90, altitude: 0), CGPoint(x: 180, y: 100), 1e-9))
        #expect(near(p.point(azimuth: 180, altitude: 0), CGPoint(x: 100, y: 180), 1e-9))
        #expect(near(p.point(azimuth: 123, altitude: 90), CGPoint(x: 100, y: 100), 1e-9))
        #expect(near(p.point(azimuth: 270, altitude: -10), CGPoint(x: 20, y: 100), 1e-9))
        #expect(near(p.point(azimuth: 0, altitude: 45), CGPoint(x: 100, y: 60), 1e-9))
    }

    @Test func rotationPutsTheChosenBearingStraightUp() {
        let p = RoseProjection(center: CGPoint(x: 100, y: 100), radius: 80, rotation: 190)
        #expect(near(p.point(azimuth: 190, altitude: 0), CGPoint(x: 100, y: 20), 1e-9))
        #expect(near(p.point(azimuth: 280, altitude: 0), CGPoint(x: 180, y: 100), 1e-9))
    }

    @Test func positionRoundTripsThroughPoint() {
        for rotation in [0.0, 190] {
            let p = RoseProjection(center: CGPoint(x: 150, y: 120), radius: 100, rotation: rotation)
            for az in stride(from: 0.0, to: 360, by: 17) {
                for alt in stride(from: 0.0, through: 89, by: 7) {
                    let back = p.position(at: p.point(azimuth: az, altitude: alt))
                    #expect(abs(back.altitude - alt) < 1e-6)
                    if alt > 0 { #expect(SkyRose.angularDifference(back.azimuth, az) < 1e-6) }
                }
            }
        }
    }

    @Test func angularDifferenceWraps() {
        #expect(SkyRose.angularDifference(350, 10) == 20)
        #expect(SkyRose.angularDifference(0, 180) == 180)
        #expect(SkyRose.angularDifference(90, 90) == 0)
    }

    // MARK: Astronomy agreement

    @Test(arguments: [oct6, jun21])
    func drawnEventsMatchTheEphemeris(day: LocalDay) throws {
        let astro = Astronomy()
        let r = rose(on: day, at: mesa, in: denver, facing: 263)
        let sun = astro.sunEvents(on: day, at: mesa, in: denver)
        let rise = try #require(sun.sunrise), set = try #require(sun.sunset)
        let riseEvent = try #require(r.event(.sunrise)), setEvent = try #require(r.event(.sunset))
        #expect(SkyRose.angularDifference(riseEvent.position.azimuth, astro.sunPosition(at: rise, coordinate: mesa).azimuth) < 1)
        #expect(SkyRose.angularDifference(setEvent.position.azimuth, astro.sunPosition(at: set, coordinate: mesa).azimuth) < 1)
        let firstArc = try #require(r.sunArcs.first), lastArc = try #require(r.sunArcs.last)
        #expect(SkyRose.angularDifference(try #require(firstArc.first).position.azimuth, riseEvent.position.azimuth) < 1)
        #expect(SkyRose.angularDifference(try #require(lastArc.last).position.azimuth, setEvent.position.azimuth) < 1)
        let noon = try #require(r.event(.solarNoon))
        let noonAlt = astro.sunPosition(at: sun.solarNoon, coordinate: mesa).altitude
        let maxAlt = try #require(r.sunArcs.flatMap { $0 }.map(\.position.altitude).max())
        #expect(abs(noon.position.altitude - noonAlt) < 1)
        #expect(abs(noon.position.altitude - maxAlt) < 1)
        // The rim angle of the sunrise marker is its azimuth.
        let p = RoseProjection(center: .zero, radius: 100)
        let pt = p.point(azimuth: riseEvent.position.azimuth, radius: p.radius)
        let screen = atan2(Double(pt.x), Double(-pt.y)) * 180 / .pi
        #expect(SkyRose.angularDifference(screen, riseEvent.position.azimuth) < 1)
    }

    @Test func mesaArchOctoberSixMatchesReference() throws {
        let r = rose(on: oct6, at: mesa, in: denver, facing: 263)
        let rise = try #require(r.event(.sunrise)), set = try #require(r.event(.sunset)), noon = try #require(r.event(.solarNoon))
        #expect((95...99).contains(rise.position.azimuth))
        #expect((261...264).contains(set.position.azimuth))
        #expect((45...47).contains(noon.position.altitude))
    }

    // MARK: Facts

    @Test func factsAgainstFacing() throws {
        let inside = rose(on: oct6, at: mesa, in: denver, facing: 263)
        let evening = oct6.at(hour: 18, in: denver)
        guard case .inside(let e) = inside.fact(at: evening) else { Issue.record("expected inside"); return }
        #expect(e.kind == .sunset)

        let outside = rose(on: oct6, at: mesa, in: denver, facing: 190)
        guard case .outside(let e2, let by) = outside.fact(at: evening) else { Issue.record("expected outside"); return }
        #expect(abs(by - (SkyRose.angularDifference(e2.position.azimuth, 190) - 35)) < 1e-9)
        #expect(by > 30 && by < 45)

        guard case .outside(let e3, _) = outside.fact(at: oct6.at(hour: 8, in: denver)) else { Issue.record("expected outside"); return }
        #expect(e3.kind == .sunrise)

        let none = rose(on: oct6, at: mesa, in: denver, facing: nil)
        guard case .noView = none.fact(at: evening) else { Issue.record("expected noView"); return }
    }

    @Test func polarNightHasNoSunriseOrSunset() {
        let r = rose(on: dec10, at: tromsoCoord, in: oslo, facing: 200)
        #expect(r.sunKind == .polarNight)
        #expect(r.fact(at: dec10.at(hour: 8, in: oslo)) == .noSunrise)
        #expect(r.fact(at: dec10.at(hour: 20, in: oslo)) == .noSunset)
        #expect(r.sunArcs.isEmpty)
    }

    // MARK: Hit testing

    @Test func nearestTimeFindsTheSunOnItsPath() throws {
        let r = rose(on: oct6, at: mesa, in: denver, facing: nil)
        let astro = Astronomy()
        let proj = RoseProjection(center: CGPoint(x: 200, y: 200), radius: 160)
        for hour in [7.6, 9.0, 12.5, 15.0, 17.7] {
            let t = oct6.start(in: denver).addingTimeInterval(hour * 3600 + 17)
            let pos = astro.sunPosition(at: t, coordinate: mesa)
            let pt = proj.point(azimuth: pos.azimuth, altitude: pos.altitude)
            let hit = try #require(r.nearestTime(to: pt, projection: proj, maxDistance: 24))
            #expect(hit.body == .sun)
            #expect(abs(hit.date.timeIntervalSince(t)) < 60)
        }
    }

    @Test func nearestTimeReturnsNilWhenFarFromThePaths() throws {
        let polar = rose(on: dec10, at: tromsoCoord, in: oslo, facing: nil)
        let proj = RoseProjection(center: CGPoint(x: 200, y: 200), radius: 200)
        #expect(polar.nearestTime(to: proj.center, projection: proj, maxDistance: 24) == nil)

        let r = rose(on: oct6, at: mesa, in: denver, facing: nil)
        let noon = try #require(r.event(.solarNoon))
        let onPath = proj.point(azimuth: noon.position.azimuth, altitude: noon.position.altitude)
        #expect(r.nearestTime(to: onPath, projection: proj, maxDistance: 24) != nil)
        // 50 pt off the path, straight out toward the rim from the noon point (the moon is not there).
        let off = CGPoint(x: onPath.x, y: onPath.y - 50)
        let result = r.nearestTime(to: off, projection: proj, maxDistance: 24)
        #expect(result == nil || result?.body == .moon)
    }

    // MARK: Moon arcs

    @Test func moonArcsStayAboveTheHorizonAndSplitAtCrossings() throws {
        // A day in October 2026 when the moon is already up at the start of the day.
        var found: LocalDay?
        for d in 1...30 {
            let day = LocalDay(year: 2026, month: 10, day: d)
            let samples = Astronomy().path(of: .moon, on: day, at: mesa, in: denver, everyMinutes: 10)
            if let first = samples.first, first.position.altitude > 0 { found = day; break }
        }
        let day = try #require(found)
        let r = rose(on: day, at: mesa, in: denver, facing: nil)
        #expect(r.moonArcs.allSatisfy { arc in arc.allSatisfy { $0.position.altitude >= -1e-6 } })
        // Runs of consecutive above-horizon samples.
        var runs = 0
        var inRun = false
        for s in r.moon {
            let up = s.position.altitude > 0
            if up && !inRun { runs += 1 }
            inRun = up
        }
        #expect(r.moonArcs.count == runs)
        #expect(r.moonArcs.first?.first?.date == r.moon.first?.date)
        for arc in r.moonArcs {
            #expect(arc.count >= 2)
            #expect(zip(arc, arc.dropFirst()).allSatisfy { $0.date <= $1.date })
        }
    }
}
