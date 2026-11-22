import Foundation
import Testing
@testable import IterCore

/// `LocalDay` arithmetic and zone handling: month and year ends, leap days, clocks that skip midnight, and days
/// that never happened. Every light window and trip day is keyed on a `LocalDay`, so these must be total.
@Suite struct LocalDayArithmeticTests {
    @Test func addingDaysCrossesMonthsYearsAndLeapDays() {
        #expect(LocalDay(year: 2026, month: 1, day: 31).adding(days: 1).iso == "2026-02-01")
        #expect(LocalDay(year: 2026, month: 2, day: 28).adding(days: 1).iso == "2026-03-01")
        #expect(LocalDay(year: 2028, month: 2, day: 28).adding(days: 1).iso == "2028-02-29")
        #expect(LocalDay(year: 2028, month: 2, day: 29).adding(days: 1).iso == "2028-03-01")
        #expect(LocalDay(year: 2026, month: 12, day: 31).adding(days: 1).iso == "2027-01-01")
        #expect(LocalDay(year: 2027, month: 1, day: 1).adding(days: -1).iso == "2026-12-31")
        #expect(LocalDay(year: 2026, month: 10, day: 7).adding(days: 0).iso == "2026-10-07")
        #expect(LocalDay(year: 2026, month: 10, day: 7).adding(days: 365).iso == "2027-10-07")
        #expect(LocalDay(year: 2026, month: 10, day: 7).adding(days: -279).iso == "2026-01-01")
    }

    @Test func addingThenCountingRoundTrips() {
        let base = LocalDay(year: 2026, month: 3, day: 1)
        for n in [-400, -31, -1, 0, 1, 7, 28, 365, 1000] {
            let d = base.adding(days: n)
            #expect(base.days(until: d) == n, "\(n)")
            #expect(d.adding(days: -n) == base)
        }
        #expect(LocalDay(year: 2026, month: 12, day: 31).ordinal == 365)
        #expect(LocalDay(year: 2028, month: 12, day: 31).ordinal == 366)
        #expect(LocalDay(year: 2026, month: 1, day: 1).ordinal == 1)
    }

    @Test func arithmeticIsIndependentOfAnyZone() {
        // The day number never moves on a clock-change day, whatever the spot's zone.
        let springForward = LocalDay(year: 2026, month: 3, day: 8)
        #expect(springForward.adding(days: 1).iso == "2026-03-09")
        #expect(springForward.days(until: LocalDay(year: 2026, month: 3, day: 9)) == 1)
        let fallBack = LocalDay(year: 2026, month: 11, day: 1)
        #expect(fallBack.adding(days: 1).iso == "2026-11-02")
        #expect(fallBack.adding(days: -1).iso == "2026-10-31")
    }

    @Test func startsAndEndsOfClockChangeDays() {
        for (zone, iso, hours) in [("America/Los_Angeles", "2026-03-08", 23.0), ("America/Los_Angeles", "2026-11-01", 25),
                                   ("Europe/London", "2026-03-29", 23), ("Europe/London", "2026-10-25", 25),
                                   ("Australia/Sydney", "2026-10-04", 23), ("Australia/Sydney", "2026-04-05", 25),
                                   ("Pacific/Auckland", "2026-09-27", 23), ("Pacific/Auckland", "2026-04-05", 25),
                                   ("America/Phoenix", "2026-03-08", 24), ("Pacific/Kiritimati", "2026-03-08", 24)] {
            let tz = TimeZone(identifier: zone)!
            let day = LocalDay(iso: iso)!
            let length = day.adding(days: 1).start(in: tz).timeIntervalSince(day.start(in: tz)) / 3600
            #expect(length == hours, "\(zone) \(iso)")
            // Every instant inside the day maps back to it, the first and last second included.
            #expect(LocalDay(day.start(in: tz), in: tz) == day)
            #expect(LocalDay(day.adding(days: 1).start(in: tz).addingTimeInterval(-1), in: tz) == day)
            #expect(LocalDay(day.adding(days: 1).start(in: tz), in: tz) == day.adding(days: 1))
            #expect(LocalDay(day.noon(in: tz), in: tz) == day)
        }
    }

    @Test func nonexistentWallTimesStayOnTheirDay() {
        // 02:30 does not exist in Los Angeles on 2026-03-08, and Havana's clocks skip midnight itself.
        let la = TimeZone(identifier: "America/Los_Angeles")!
        let day = LocalDay(year: 2026, month: 3, day: 8)
        #expect(LocalDay(day.at(hour: 2, minute: 30, in: la), in: la) == day)
        let havana = TimeZone(identifier: "America/Havana")!
        let skipped = LocalDay(year: 2026, month: 3, day: 8)
        #expect(LocalDay(skipped.start(in: havana), in: havana) == skipped)
    }

    @Test func aDayTheCalendarSkippedDoesNotCrash() {
        // Samoa jumped over 30 December 2011. Asking for that day's start must not trap.
        let apia = TimeZone(identifier: "Pacific/Apia")!
        let skipped = LocalDay(year: 2011, month: 12, day: 30)
        _ = skipped.start(in: apia)
        _ = skipped.noon(in: apia)
        #expect(LocalDay(year: 2011, month: 12, day: 29).adding(days: 1) == skipped)
    }

    @Test func theSameInstantIsDifferentDaysEitherSideOfTheDateLine() {
        let instant = Date(timeIntervalSince1970: 1_791_374_400)   // 2026-10-07 12:00 UTC
        #expect(LocalDay(instant, in: TimeZone(identifier: "Pacific/Kiritimati")!).iso == "2026-10-08")   // UTC+14
        #expect(LocalDay(instant, in: TimeZone(identifier: "Pacific/Pago_Pago")!).iso == "2026-10-07")    // UTC-11
        #expect(LocalDay(instant, in: TimeZone(identifier: "Pacific/Auckland")!).iso == "2026-10-08")
        #expect(LocalDay(instant, in: TimeZone(identifier: "America/Phoenix")!).iso == "2026-10-07")
        // Pago Pago's midnight is 11:00 UTC.
        let midnight = instant.addingTimeInterval(23 * 3600)       // 2026-10-08 11:00 UTC
        #expect(LocalDay(midnight.addingTimeInterval(-1), in: TimeZone(identifier: "Pacific/Pago_Pago")!).iso == "2026-10-07")
        #expect(LocalDay(midnight, in: TimeZone(identifier: "Pacific/Pago_Pago")!).iso == "2026-10-08")
    }

    @Test func parsingRejectsImpossibleDates() {
        for bad in ["2026-02-30", "2026-02-29", "2026-04-31", "2026-13-01", "2026-00-10", "2026-10-00", "2026-10", "abc", "", "2026-10-07-01"] {
            #expect(LocalDay(iso: bad) == nil, "\(bad)")
        }
        #expect(LocalDay(iso: "2028-02-29")?.iso == "2028-02-29")
        #expect(LocalDay(iso: "2026-12-31")?.iso == "2026-12-31")
    }

    @Test func comparisonIsChronological() {
        let days = [LocalDay(year: 2027, month: 1, day: 1), LocalDay(year: 2026, month: 12, day: 31), LocalDay(year: 2026, month: 2, day: 1)]
        #expect(days.sorted().map(\.iso) == ["2026-02-01", "2026-12-31", "2027-01-01"])
    }
}
