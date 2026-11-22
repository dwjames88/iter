import Foundation
import IterModel
import Testing

@testable import IterUI

private let us = Locale(identifier: "en_US")
private let gb = Locale(identifier: "en_GB")
private let phoenix = TimeZone(identifier: "America/Phoenix")!
private let day = LocalDay(year: 2026, month: 10, day: 6)

private func plain(_ s: String) -> String {
    s.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
}

@Suite("TripBuilder.Text")
struct TripBuilderTextTests {
    @Test func driveLines() {
        // 2 hr 19 min, 101 mi (162,543 m).
        #expect(TripBuilderText.driveLine(seconds: 139 * 60, meters: 162_543, locale: us) == "2 hr, 19 min • 101 mi")
        #expect(TripBuilderText.driveLine(seconds: 139 * 60, meters: 162_543, locale: gb) == "2 hrs, 19 min • 101 mi")
        #expect(TripBuilderText.drivingTotal(seconds: 574 * 60, meters: 788_000, locale: us) == "9 hr, 34 min • 490 mi")
    }

    @Test func dayCardPhrases() {
        #expect(TripBuilderText.dayName(index: 1, locale: us) == "Day 2")
        #expect(TripBuilderText.weekdayName(day, locale: us) == "Tuesday")
        #expect(TripBuilderText.dayCardDate(day, locale: us) == "Tuesday, Oct 6")
        #expect(TripBuilderText.stopCountTitle(0, locale: us) == "No Stops")
        #expect(TripBuilderText.stopCountTitle(1, locale: us) == "1 Stop")
        #expect(TripBuilderText.stopCountTitle(2, locale: us) == "2 Stops")
        #expect(TripBuilderText.tripSize(days: 4, stops: 6, locale: us) == "4 days • 6 stops")
        #expect(TripBuilderText.dayTotals(stops: 0, drivingSeconds: 0, locale: us) == "No stops yet")
        #expect(TripBuilderText.dayTotals(stops: 1, drivingSeconds: 30, locale: us) == "1 stop")
        #expect(TripBuilderText.dayTotals(stops: 2, drivingSeconds: 326 * 60, locale: us) == "2 stops • 5 hr, 26 min of driving")
    }

    @Test func sunAndOvernight() {
        let rise = day.at(hour: 6, minute: 25, in: phoenix)
        #expect(TripBuilderText.sunTime(.goldenMorning, at: rise, in: phoenix, locale: gb) == "Sunrise at 06:25")
        #expect(TripBuilderText.sunTime(.goldenEvening, at: day.at(hour: 18, minute: 1, in: phoenix), in: phoenix, locale: gb) == "Sunset at 18:01")
        #expect(TripBuilderText.overnightNear("Page, AZ", locale: us) == "Overnight near Page, AZ")
    }

    @Test func driveWarningAndStopLine() {
        #expect(TripBuilderText.driveDoesntFit(shortBy: 25 * 60, locale: us) == "Drive doesn't fit: 25 min short")
        let park = day.at(hour: 16, minute: 42, in: phoenix)
        #expect(TripBuilderText.parkLine(parkAt: park, walkMinutes: 25, in: phoenix, locale: gb) == "Park at 16:42 • 25 min walk in")
        #expect(TripBuilderText.parkLine(parkAt: nil, walkMinutes: 25, in: phoenix, locale: gb) == "25 min walk in")
        #expect(TripBuilderText.parkLine(parkAt: park, walkMinutes: nil, in: phoenix, locale: gb) == "Walk-in unknown")
        #expect(TripBuilderText.setUpShort(minutes: 20, locale: us) == "20 min setup")
        #expect(TripBuilderText.transferTimingName(.morning, locale: us) == "Morning")
        #expect(TripBuilderText.transferTimingName(.eveningBefore, locale: us) == "Evening Before")
    }
}

@Suite("TripBuilder.Components")
struct TripBuilderComponentTests {
    @Test func findHotelsURL() {
        let url = FindHotelsButton.url(latitude: 36.9, longitude: -111.45)
        #expect(url?.absoluteString == "maps://?q=Hotels&sll=36.9,-111.45")
        #expect(url?.scheme == "maps")
        #expect(FindHotelsButton(latitude: 1, longitude: 2).url?.absoluteString == "maps://?q=Hotels&sll=1.0,2.0")
    }

    @Test func metaItems() {
        let last = day.adding(days: 3)
        #expect(TripMetaItem.dates(from: day, to: last, locale: us).text == "Tue, Oct 6 – Fri, Oct 9")
        #expect(TripMetaItem.dates(from: day, to: day, locale: us).text == "Tue, Oct 6")
        #expect(TripMetaItem.size(days: 4, stops: 6, locale: us).text == "4 days • 6 stops")
        #expect(TripMetaItem.driving(seconds: 574 * 60, meters: 788_000, locale: us).text == "9 hr, 34 min • 490 mi")
        #expect(TripMetaItem.driving(seconds: 1, meters: 1).symbol == "car.fill")
    }

    @Test func metaRowArrangements() {
        #expect(TripMetaRow.arrangements(itemCount: 3) == [[[0, 1, 2]], [[0, 1], [2]], [[0], [1], [2]]])
        #expect(TripMetaRow.arrangements(itemCount: 2) == [[[0, 1]], [[0, 1]], [[0], [1]]])
        #expect(TripMetaRow.arrangements(itemCount: 1) == [[[0]], [[0]], [[0]]])
    }

    @Test func daySelectorItem() {
        let item = DaySelectorItem(DaySummary(index: 0, date: day, stopCount: 2, session: .goldenEvening), locale: us)
        #expect(item.dayName == "Day 1")
        #expect(item.weekday == "Tuesday")
        #expect(item.stops == "2 Stops")
        #expect(item.session == "Sunset")
        #expect(item.spoken == "Day 1, Tuesday, October 6, 2 stops, Sunset")
        let empty = DaySelectorItem(DaySummary(index: 2, date: day.adding(days: 2), stopCount: 0, session: .goldenEvening), locale: us)
        #expect(empty.session == nil)
        #expect(empty.spoken == "Day 3, Thursday, October 8, no stops")
    }

    @Test func dayCardPositions() {
        #expect(DayCardPosition.first.roundsTop && !DayCardPosition.first.roundsBottom)
        #expect(!DayCardPosition.middle.roundsTop && !DayCardPosition.middle.roundsBottom)
        #expect(!DayCardPosition.last.roundsTop && DayCardPosition.last.roundsBottom)
        #expect(DayCardPosition.only.roundsTop && DayCardPosition.only.roundsBottom)
    }

    @Test func lightWindowOptionTitle() {
        let start = day.at(hour: 18, minute: 12, in: phoenix)
        let option = LightWindowPicker.Option(kind: .goldenEvening, start: start, end: start.addingTimeInterval(36 * 60), score: 64)
        #expect(plain(option.title(in: phoenix, locale: us)) == "Sunset · 6:12 PM–6:48 PM · 64")
        #expect(LightWindowPicker.Option(kind: .goldenMorning, start: start, end: start.addingTimeInterval(1800))
            .title(in: phoenix, locale: gb) == "Sunrise · 18:12–18:42")
    }

    @Test func builderMetrics() {
        #expect(BuilderMetrics.cardCorner == GlassGeometry.cardCorner)
        #expect(BuilderMetrics.innerCorner == 22)
        #expect(BuilderMetrics.panelInset == 16 && BuilderMetrics.sectionGap == 24)
    }
}
