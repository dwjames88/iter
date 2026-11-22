import Foundation
import IterModel
import Testing

@testable import IterUI

private let us = Locale(identifier: "en_US")
private let gb = Locale(identifier: "en_GB")
private let de = Locale(identifier: "de_DE")
private let denver = TimeZone(identifier: "America/Denver")!
private let utc = TimeZone(identifier: "UTC")!

/// ICU puts narrow no-break spaces in en_US times; compare with plain spaces.
private func plain(_ s: String) -> String {
    s.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
}

/// 2026-10-06 12:45 UTC = 06:45 in Denver (MDT, UTC-6).
private let base = Date(timeIntervalSince1970: 1_791_290_700)

@Suite("Text.Time")
struct TimeTextTests {
    @Test func timesFollowLocaleClock() {
        #expect(plain(TimeText.time(base, in: denver, locale: us)) == "6:45 AM")
        #expect(TimeText.time(base, in: denver, locale: gb) == "06:45")
        #expect(TimeText.time(base, in: denver, locale: de) == "06:45")
        #expect(TimeText.time(base, in: utc, locale: gb) == "12:45")
    }

    @Test func ranges() {
        let span = TimeSpan(start: base, end: base.addingTimeInterval(35 * 60))
        #expect(TimeText.timeRange(span, in: denver, locale: gb) == "06:45–07:20")
        #expect(TimeText.timeRange(span, in: denver, locale: de) == "06:45–07:20")
        #expect(plain(TimeText.timeRange(span, in: denver, locale: us)) == "6:45 AM–7:20 AM")
    }

    @Test func relativeDays() {
        let today = LocalDay(year: 2026, month: 10, day: 6)
        #expect(TimeText.relativeDay(today, today: today, locale: us) == "Today")
        #expect(TimeText.relativeDay(today.adding(days: 1), today: today, locale: us) == "Tomorrow")
        #expect(TimeText.relativeDay(today.adding(days: -1), today: today, locale: us) == "Yesterday")
        #expect(TimeText.relativeDay(today.adding(days: 3), today: today, locale: gb) == "Fri 9 Oct")
        #expect(TimeText.relativeDay(today.adding(days: 3), today: today, locale: us) == "Fri, Oct 9")
    }

    @Test func dayForms() {
        let d = LocalDay(year: 2026, month: 10, day: 6)
        #expect(TimeText.weekday(d, locale: us) == "Tue")
        #expect(TimeText.dayNumber(d, locale: us) == "6")
        #expect(TimeText.longDay(d, locale: gb) == "Tuesday 6 October")
        #expect(TimeText.longDay(d, locale: us) == "Tuesday, October 6")
    }

    @Test func durations() {
        #expect(TimeText.duration(80 * 60, width: .wide, locale: us) == "1 hour, 20 minutes")
        #expect(TimeText.duration(80 * 60, locale: us) == "1 hr, 20 min")
        #expect(TimeText.duration(80 * 60, width: .narrow, locale: us) == "1h 20m")
        #expect(TimeText.duration(45 * 60, locale: us) == "45 min")
        #expect(TimeText.duration(3600, locale: us) == "1 hr")
        #expect(TimeText.duration(10, locale: us) == "0 min")
        #expect(TimeText.duration(80 * 60, locale: de) == "1 Std., 20 Min.")
    }

    @Test func distances() {
        #expect(plain(TimeText.distance(kilometers: 312, locale: us)) == "194 mi")
        #expect(plain(TimeText.distance(kilometers: 312, locale: de)) == "312 km")
        #expect(plain(TimeText.distance(meters: 312_000, locale: de)) == "312 km")
    }

    @Test func zoneNote() {
        let now = base
        #expect(TimeText.zoneNote(for: denver, now: now, local: denver, locale: us) == nil)
        let note = TimeText.zoneNote(for: denver, now: now, local: TimeZone(identifier: "America/Los_Angeles")!, locale: us)
        #expect(note?.hasSuffix("1 hr ahead of you") == true)
    }
}

@Suite("Text.Light")
struct LightTextTests {
    @Test func namesAndSymbolsForAllWindows() {
        let table: [(LightWindowKind, String, String, String)] = [
            (.goldenMorning, "Sunrise", "Sunrise", "sunrise.fill"),
            (.goldenEvening, "Sunset", "Sunset", "sunset.fill"),
            (.blueMorning, "Morning Blue Hour", "Blue AM", "sun.haze.fill"),
            (.blueEvening, "Evening Blue Hour", "Blue PM", "moon.haze.fill"),
            (.night, "Night", "Night", "moon.stars.fill"),
        ]
        #expect(table.count == LightWindowKind.allCases.count)
        for (kind, name, short, symbol) in table {
            #expect(LightText.name(kind) == name)
            #expect(LightText.shortName(kind) == short)
            #expect(LightText.symbol(kind) == symbol)
        }
    }

    @Test func intentsAndBestLight() {
        #expect(LightText.symbol(LightIntent.blueHour) == "moon.haze.fill")
        #expect(LightText.symbol(LightIntent.sunrise) == "sunrise.fill")
        #expect(LightText.name(LightIntent.blueHour) == "Blue Hour")
        #expect(Set(BestLight.allCases.map { LightText.name($0) }).count == 6)
    }

    @Test func scores() {
        #expect(LightText.headline(.goldenEvening, score: 38, locale: us) == "Sunset · 38")
        #expect(LightText.headline(.goldenEvening, score: nil, locale: us) == "Sunset")
        #expect(LightText.range(55...75, locale: us) == "55–75")
        #expect(LightText.range(60...60, locale: us) == nil)
        #expect(LightText.accessibilityDescription(.night, score: 12, locale: us) == "Night, Light Index 12")
    }

    @Test func places() {
        #expect(LightText.name(PlaceOrigin.user) == "Added by You")
        #expect(Set(PlaceCategory.allCases.map { LightText.symbol($0) }).count == PlaceCategory.allCases.count)
        #expect(PlaceCategory.allCases.allSatisfy { !LightText.name($0).isEmpty })
    }
}

@Suite("Text.Data")
struct DataTextTests {
    private func age(_ seconds: TimeInterval) -> String {
        DataText.ageText(of: base, now: base.addingTimeInterval(seconds), locale: us)
    }

    @Test func ageBoundaries() {
        #expect(age(0) == "Updated just now")
        #expect(age(59) == "Updated just now")
        #expect(age(60) == "Updated 1 min ago")
        #expect(age(12 * 60 + 30) == "Updated 12 min ago")
        #expect(age(3599) == "Updated 59 min ago")
        #expect(age(3600) == "1 hr old")
        #expect(age(3 * 3600 + 100) == "3 hr old")
        #expect(age(6 * 3600 - 1) == "5 hr old")
        #expect(age(6 * 3600) == "Stale")
        #expect(age(-30) == "Updated just now")
    }

    @Test func days() {
        let text = DataText.ageText(of: base, now: base.addingTimeInterval(2 * 86_400), staleAfter: 7 * 86_400, locale: us)
        #expect(text == "2 days old")
    }

    @Test func tiers() {
        #expect(DataText.phrase(.military) == "Military-origin data")
        #expect(DataText.phrase(.government) == "Government data")
        #expect(DataText.phrase(.openData) == "Open data")
        #expect(DataText.phrase(.userKey) == "Your key")
        #expect(DataText.phrase(.device) == "This device")
        #expect(DataText.name(.military) == "Military Origin")
        #expect(SourceTier.allCases.allSatisfy { !DataText.name($0).isEmpty })
        #expect(DataText.originMarker(.military) == "Military-origin data")
        #expect(SourceTier.allCases.filter { DataText.originMarker($0) != nil } == [.military])
    }

    @Test func provenanceLine() {
        let prov = Provenance(source: "noaa.gfs", model: "GFS", fetchedAt: base, licence: LicenceTag(key: "pd", mayStore: true))
        let now = base.addingTimeInterval(12 * 60)
        #expect(DataText.provenanceLine(prov, now: now, locale: us) == "GFS · Updated 12 min ago")
        var bare = prov
        bare.model = nil
        #expect(DataText.provenanceLine(bare, now: now, locale: us) == "Updated 12 min ago")
    }
}

@Suite("Text.Trip")
struct TripTextTests {
    private let departure = base.addingTimeInterval(3600)

    @Test func leaveBy() {
        #expect(TripText.leaveBy(departure, now: base, in: denver, locale: gb) == "Leave by 07:45")
        #expect(plain(TripText.leaveBy(departure, now: base, in: denver, locale: us)) == "Leave by 7:45 AM")
        #expect(TripText.leaveBy(departure, now: departure.addingTimeInterval(-60), in: denver, locale: gb) == "Leave Now")
        #expect(TripText.leaveBy(departure, now: departure.addingTimeInterval(60), in: denver, locale: gb) == "Leave Now")
        #expect(TripText.leaveBy(departure, now: departure.addingTimeInterval(6 * 60), in: denver, locale: gb) == "Late by 6 min")
        #expect(TripText.leaveBy(departure, now: departure.addingTimeInterval(61), in: denver, locale: gb) == "Late by 2 min")
    }

    @Test func arrive() {
        #expect(TripText.arrive(departure, in: denver, locale: de) == "Arrive 07:45")
        #expect(TripText.eta(arrival: departure, deadline: nil, in: denver, locale: gb) == "Arrive 07:45")
        #expect(TripText.eta(arrival: departure, deadline: departure.addingTimeInterval(60), in: denver, locale: gb) == "Arrive 07:45")
        #expect(TripText.eta(arrival: departure, deadline: departure.addingTimeInterval(-6 * 60), in: denver, locale: gb) == "Arrive 07:45 · 6 min after the light starts")
    }

    @Test func lateByLongHours() {
        #expect(TripText.lateBy(80 * 60, locale: us) == "Late by 1 hr, 20 min")
        #expect(TripText.lateBy(5, locale: us) == "Late by 1 min")
    }

    @Test func driveLine() {
        #expect(plain(TripText.drive(seconds: 80 * 60, meters: 312_000, locale: us)) == "1 hr, 20 min · 194 mi")
        #expect(plain(TripText.drive(seconds: 80 * 60, meters: 312_000, locale: gb)) == "1 hr, 20 min · 194 mi")
    }
}

@Suite("Text.Inflected")
struct InflectedCountTests {
    @Test func counts() {
        let en = Locale(identifier: "en")
        #expect(InflectedCount.stops(1, locale: en) == "1 stop")
        #expect(InflectedCount.stops(3, locale: en) == "3 stops")
        #expect(InflectedCount.days(2, locale: en) == "2 days")
        #expect(InflectedCount.places(1, locale: en) == "1 place")
        #expect(InflectedCount.trips(0, locale: en) == "0 trips")
    }
}
