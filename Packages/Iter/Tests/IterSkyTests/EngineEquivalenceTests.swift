import Foundation
import Testing
import IterModel
import IterAstro
@testable import IterSky

/// The shortcuts in `LightEngine` (nextEvent skips the night window, outlook solves each day's sun once) must give
/// exactly what the plain day-by-day path gives. The reference below is the straightforward definition, built only on
/// `windows(for:on:)` (full geometry) and `dayLight(for:on:)` (one day at a time).
@Suite struct EngineEquivalenceTests {
    let engine = LightEngine(ephemeris: Astronomy())

    static let spots: [Place] = [
        place("moab", 38.57, -109.55, "America/Denver"), place("phoenix", 33.45, -112.07, "America/Phoenix"),
        place("hobart", -42.88, 147.33, "Australia/Hobart"), place("auckland", -36.85, 174.76, "Pacific/Auckland"),
        place("quito", -0.18, -78.47, "America/Guayaquil"), place("london", 51.5, -0.12, "Europe/London"),
        place("tromso", 69.65, 18.96, "Europe/Oslo"), place("longyearbyen", 78.22, 15.65, "Arctic/Longyearbyen"),
        place("kiritimati", 1.87, -157.4, "Pacific/Kiritimati"),
    ]

    /// The lead's definition of the next event: scan four full days, first golden window not yet over, else the first
    /// daytime window not yet over.
    func referenceNextEvent(_ spot: Place, inputs: ForecastSkyInputs?, now: Date) -> (day: LocalDay, window: LightWindow)? {
        let today = LocalDay(now, in: spot.timeZone)
        var fallback: (LocalDay, LightWindowKind, TimeSpan)?
        for offset in 0..<4 {
            let day = today.adding(days: offset)
            let geo = engine.windows(for: spot, on: day)
            if let g = geo.first(where: { $0.kind.isGolden && $0.span.end > now }) {
                return (day, engine.lightWindow(kind: g.kind, span: g.span, place: spot, inputs: inputs, unavailable: [], now: now))
            }
            if fallback == nil, let g = geo.first(where: { $0.kind != .night && $0.span.end > now }) { fallback = (day, g.kind, g.span) }
        }
        guard let f = fallback else { return nil }
        return (f.0, engine.lightWindow(kind: f.1, span: f.2, place: spot, inputs: inputs, unavailable: [], now: now))
    }

    static let instants: [Date] = {
        // Spread over a year, including solstices, equinoxes, DST changes and the polar transitions, at awkward hours.
        let isos = ["2026-01-03", "2026-03-08", "2026-03-20", "2026-03-29", "2026-04-05", "2026-05-18", "2026-06-21", "2026-07-26",
                    "2026-09-27", "2026-10-04", "2026-10-25", "2026-11-01", "2026-11-27", "2026-12-21"]
        let hours: [Double] = [0.2, 5.5, 9.0, 13.3, 17.7, 21.1, 23.9]
        return isos.flatMap { iso in hours.map { LocalDay(iso: iso)!.start(in: TimeZone(identifier: "UTC")!).addingTimeInterval($0 * 3600) } }
    }()

    @Test func nextEventMatchesTheFullDayScan() {
        var checked = 0
        for spot in Self.spots {
            let zone = spot.timeZone
            for now in Self.instants {
                let f = eightDayInputs(for: spot, from: now.addingTimeInterval(-6 * 3600))
                for inputs in [nil, f] {
                    let want = referenceNextEvent(spot, inputs: inputs, now: now)
                    let got = engine.nextEvent(for: spot, inputs: inputs, now: now)
                    #expect(got?.day == want?.day, "\(spot.name) \(now) day")
                    #expect(got?.window == want?.window, "\(spot.name) \(LocalDay(now, in: zone)) \(now)")
                    checked += 1
                }
            }
        }
        #expect(checked == Self.spots.count * Self.instants.count * 2)
    }

    @Test func outlookMatchesDayByDay() {
        for spot in Self.spots {
            for iso in ["2026-03-06", "2026-05-15", "2026-06-19", "2026-10-02", "2026-11-29"] {
                let day = LocalDay(iso: iso)!
                let now = day.noon(in: spot.timeZone)
                let f = eightDayInputs(for: spot, from: now.addingTimeInterval(-6 * 3600))
                for inputs in [nil, f] {
                    let want = (0..<6).map { engine.dayLight(for: spot, on: day.adding(days: $0), inputs: inputs, now: now) }
                    let got = engine.outlook(for: spot, from: day, days: 6, inputs: inputs, now: now)
                    #expect(got == want, "\(spot.name) \(iso)")
                    #expect(engine.outlook(for: spot, from: day, days: 1, inputs: inputs, now: now) == [want[0]])
                }
            }
        }
    }

    @Test func upcomingWindowsMatchTwoSingleDays() {
        for spot in Self.spots {
            for now in Self.instants.prefix(40) {
                let today = LocalDay(now, in: spot.timeZone)
                let a = engine.dayLight(for: spot, on: today, inputs: nil, now: now)
                let b = engine.dayLight(for: spot, on: today.adding(days: 1), inputs: nil, now: now)
                let want = a.windows.filter { $0.span.end > now }.map { ($0.kind, $0.span) } + b.windows.map { ($0.kind, $0.span) }
                let got = engine.upcomingWindows(for: spot, inputs: nil, now: now).map { ($0.window.kind, $0.window.span) }
                #expect(got.count == want.count && zip(got, want).allSatisfy { $0 == $1 }, "\(spot.name) \(now)")
            }
        }
    }

    @Test func outlookOfZeroDaysIsEmpty() {
        let now = Date(timeIntervalSince1970: 1_791_000_000)
        #expect(engine.outlook(for: Self.spots[0], from: LocalDay(year: 2026, month: 10, day: 7), days: 0, inputs: nil, now: now).isEmpty)
        #expect(engine.outlook(for: Self.spots[0], from: LocalDay(year: 2026, month: 10, day: 7), days: -3, inputs: nil, now: now).isEmpty)
    }
}
