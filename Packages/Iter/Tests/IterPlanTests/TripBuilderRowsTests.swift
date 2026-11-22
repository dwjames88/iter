import Foundation
import Testing
import IterModel
@testable import IterPlan

// Ported from IterFeaturesTests/TripBuilderRowsTests (10 tests, all carry) onto the pure builders.

@Suite struct TripBuilderRowsTests {
    let h = TripHarness()

    private func tag(_ row: TripBuilderRow) -> String {
        switch row.kind {
        case .dayHeader: "header"
        case .suggestion: "suggestion"
        case .conflicts: "conflicts"
        case .stop: "stop"
        case .drive: "drive"
        case .footer: "footer"
        case .transfer: "transfer"
        }
    }

    @Test func singleDay() {
        let trip = h.trip(days: 1, [(h.mesa, 0, .goldenMorning)])
        let rows = TripBuilderRow.make(h.build(trip).layout)
        #expect(rows.map(tag) == ["header", "stop", "footer"])
        #expect(rows.map(\.position) == [.first, .middle, .last])
        #expect(rows.map(\.id).first == "header-0")
        #expect(rows.last?.id == "addStop-0")
        if case .footer(let day, let overnight) = rows[2].kind { #expect(day == 0 && overnight == nil) } else { Issue.record("footer") }
    }

    @Test func crossDayDriveBecomesATransferBeforeTheCard() {
        let layout = h.build(h.makeTrip()).layout
        let rows = TripBuilderRow.make(layout)
        // Day 0: header, stop, inline drive, stop, footer. Then transfer, day 1: header, stop, footer.
        #expect(rows.map(tag) == ["header", "stop", "drive", "stop", "footer", "transfer", "header", "stop", "footer"])
        let transfer = rows[5]
        #expect(transfer.id == "transfer-1")
        #expect(transfer.day == 1)
        #expect(transfer.position == nil)
        guard case .transfer(let drive, let overnight) = transfer.kind else { Issue.record("transfer"); return }
        #expect(drive?.toStopID == layout.groups[1].stops[0].id)
        #expect(overnight == layout.groups[0].overnightAfter)
        #expect(overnight != nil)
        // The overnight shows in the transfer, not the footer.
        if case .footer(_, let footerOvernight) = rows[4].kind { #expect(footerOvernight == nil) } else { Issue.record("footer") }
        // The drive in is not inside day 1's card.
        #expect(!rows[6...].contains { if case .drive = $0.kind { true } else { false } })
    }

    @Test func theTransferRowCarriesTheTimingTheNoteAndTheDestinationOvernight() {
        var trip = h.makeTrip()
        trip.stops[2].driveNote = "Fuel in Kanab"
        trip.transferTimings[1] = .eveningBefore
        let b = h.build(trip)
        let rows = TripBuilderRow.make(b.layout)
        guard case .transfer(let drive, let overnight) = rows[5].kind else { Issue.record("transfer"); return }
        #expect(drive?.transferTiming == .eveningBefore)
        #expect(drive?.note == "Fuel in Kanab")
        #expect(overnight?.placeName == b.days[1].stops[0].stop.place.name)
        #expect(overnight == b.layout.groups[0].overnightAfter)
        // The inline drive of day 0 has no timing.
        if case .drive(let inline) = rows[2].kind { #expect(inline.transferTiming == nil) } else { Issue.record("drive") }
    }

    @Test func aMiddleDayWithNoStopsKeepsTheOvernightInItsFooter() {
        let trip = h.trip(days: 3, [(h.mesa, 0, .goldenMorning), (h.horseshoe, 2, .goldenEvening)])
        let rows = TripBuilderRow.make(h.build(trip).layout)
        #expect(rows.map(tag) == ["header", "stop", "footer", "header", "footer", "transfer", "header", "stop", "footer"])
        // Day 0 is followed by a day with no drive in: its footer keeps the overnight.
        if case .footer(_, let overnight) = rows[2].kind { #expect(overnight?.afterDay == 0) } else { Issue.record("footer") }
        // The empty day is followed by the transfer: overnight moves there.
        if case .footer(_, let overnight) = rows[4].kind { #expect(overnight == nil) } else { Issue.record("footer") }
        if case .transfer(_, let overnight) = rows[5].kind { #expect(overnight?.afterDay == 1) } else { Issue.record("transfer") }
        #expect(rows[5].id == "transfer-2")
    }

    @Test func aSameDayDriveStaysInsideTheCard() {
        let rows = TripBuilderRow.make(h.build(h.makeTrip()).layout)
        #expect(rows[2].id.hasPrefix("drive-"))
        #expect(rows[2].position == .middle)
        #expect(rows[2].day == 0)
    }

    @Test func positionsAreFirstMiddleLast() {
        let rows = TripBuilderRow.make(h.build(h.makeTrip()).layout)
        #expect(rows.prefix(5).map(\.position) == [.first, .middle, .middle, .middle, .last])
        #expect(rows[6...].map(\.position) == [.first, .middle, .last])
        #expect(TripBuilderRow.Position.first.roundsTop && !TripBuilderRow.Position.first.roundsBottom)
        #expect(TripBuilderRow.Position.last.roundsBottom && !TripBuilderRow.Position.last.roundsTop)
        #expect(TripBuilderRow.Position.only.roundsTop && TripBuilderRow.Position.only.roundsBottom)
        #expect(!TripBuilderRow.Position.middle.roundsTop && !TripBuilderRow.Position.middle.roundsBottom)
    }

    @Test func idsAreStableAndUnique() {
        let layout = h.build(h.makeTrip()).layout
        let first = TripBuilderRow.make(layout).map(\.id)
        #expect(first == TripBuilderRow.make(layout).map(\.id))
        #expect(Set(first).count == first.count)
        #expect(first.contains("header-0") && first.contains("header-1"))
        for entry in layout.groups.flatMap(\.stops) { #expect(first.contains("stop-\(entry.id)")) }
    }

    @Test func overnightCarriesThePlaceCoordinate() {
        let layout = h.build(h.makeTrip()).layout
        let last = layout.groups[0].stops.last!.stop.place
        #expect(layout.groups[0].overnightAfter?.coordinate == last.coordinate)
    }

    @Test func dayPartBoundariesInANonUTCZone() {
        let zone = TimeZone(identifier: "America/Denver")!
        let day = LocalDay(year: 2026, month: 10, day: 7)
        func part(_ hour: Int, _ minute: Int) -> DayPart { DayPart.of(day.at(hour: hour, minute: minute, in: zone), in: zone) }
        #expect(part(4, 59) == .earlyMorning)
        #expect(part(5, 0) == .morning)
        #expect(part(11, 59) == .morning)
        #expect(part(12, 0) == .afternoon)
        #expect(part(16, 59) == .afternoon)
        #expect(part(17, 0) == .evening)
        #expect(part(20, 59) == .evening)
        #expect(part(21, 0) == .night)
        #expect(part(0, 0) == .earlyMorning)
        #expect(part(23, 59) == .night)
    }

    @Test func daySummariesFallBackToTheFirstStopsSession() {
        var layout = h.build(h.makeTrip()).layout
        var summaries = layout.daySummaries
        #expect(summaries.map(\.index) == [0, 1])
        #expect(summaries.map(\.stopCount) == [2, 1])
        #expect(summaries[0].primarySession == layout.groups[0].bestWindow?.window.kind)
        #expect(summaries[0].date == layout.groups[0].date)
        layout.groups[0].bestWindow = nil
        summaries = TripDaySummary.make(layout)
        #expect(summaries[0].primarySession == layout.groups[0].stops[0].stop.session)
        layout.groups[0].items = [.addStop(day: 0)]
        layout.groups[0].stopCount = 0
        #expect(TripDaySummary.make(layout)[0].primarySession == nil)
    }

    // New: the start place.
    @Test func theStartPlaceDriveBecomesATransferRowBeforeDayZero() {
        let layout = h.build(h.makeTrip(start: h.home), start: h.home).layout
        let rows = TripBuilderRow.make(layout)
        #expect(rows.map(tag) == ["transfer", "header", "stop", "drive", "stop", "footer", "transfer", "header", "stop", "footer"])
        guard case .transfer(let drive, let overnight) = rows[0].kind else { Issue.record("transfer"); return }
        #expect(drive?.fromStart == true && drive?.fromName == "Home")
        #expect(overnight == nil)
        #expect(rows[0].id == "transfer-0" && rows[0].day == 0)
        // The day card itself is unchanged.
        #expect(rows[1...5].map(\.position) == [.first, .middle, .middle, .middle, .last])
    }
}
