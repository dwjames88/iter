import Foundation
import Testing
import IterCore
import IterLight
import IterData
@testable import IterFeatures

@MainActor
@Suite struct TripDayLayoutTests {
    private func score(_ value: Int) -> LightAssessment {
        .scored(LightScore(value: value, band: .good, confidence: .high, range: value...value, contributors: [],
                           source: .appleWeather, forecastFetchedAt: Date(timeIntervalSince1970: 0), leadHours: 12))
    }

    private func layout(_ trip: TripRecord, in h: TripHarness) async -> (TripDayLayout, TripBuilderModel) {
        let model = h.model(for: trip)
        await model.waitForLegs()
        return (model.layout, model)
    }

    private func stopIDs(_ group: TripDayGroup) -> [UUID] { group.stops.map(\.id) }

    @Test func stopsAreGroupedByDayInOrder() async {
        let h = TripHarness()
        let (layout, model) = await layout(h.makeTrip(), in: h)
        #expect(layout.groups.map(\.index) == [0, 1])
        #expect(stopIDs(layout.groups[0]) == model.days[0].stops.map(\.id))
        #expect(stopIDs(layout.groups[1]) == model.days[1].stops.map(\.id))
        #expect(layout.groups.map(\.stopCount) == [2, 1])
        // Day 0 reads: stop, drive, stop, add stop.
        let kinds = layout.groups[0].items.map { item -> String in
            switch item {
            case .driveIn: "driveIn"
            case .stop: "stop"
            case .drive: "drive"
            case .addStop: "addStop"
            }
        }
        #expect(kinds == ["stop", "drive", "stop", "addStop"])
    }

    @Test func theDriveInBelongsToTheNextDay() async throws {
        let h = TripHarness()
        let (layout, model) = await layout(h.makeTrip(), in: h)
        let horseshoe = model.days[1].stops[0]
        guard case .driveIn(let drive) = layout.groups[1].items.first else {
            Issue.record("day 2 should start with the drive in")
            return
        }
        #expect(drive.toStopID == horseshoe.id)
        #expect(drive.fromName == model.days[0].stops[1].stop.spot.name)
        #expect(drive.leg != nil)
        #expect(drive.leaveBy == horseshoe.schedule?.leaveBy)
        // Day 1 has no drive into it and no drive leaving it.
        let driveInsOnDayOne = layout.groups[0].items.filter { if case .driveIn = $0 { true } else { false } }
        #expect(driveInsOnDayOne.isEmpty)
        let driveCount = layout.groups[0].items.filter { $0.isDrive }.count
        #expect(driveCount == 1)
    }

    @Test func aDayWithNoStopsHasJustAddStopAndNoBestWindow() async {
        let h = TripHarness()
        let trip = h.store.createTrip(name: "Gap", startDay: TripHarness.start, dayCount: 3)
        h.store.addStop(h.spot("mesa-arch"), to: trip, day: 0, session: .goldenMorning)
        h.store.addStop(h.spot("horseshoe-bend"), to: trip, day: 2, session: .goldenEvening)
        let (layout, _) = await layout(trip, in: h)
        let empty = layout.groups[1]
        #expect(empty.items.count == 1)
        if case .addStop(let day) = empty.items[0] { #expect(day == 1) } else { Issue.record("expected addStop") }
        #expect(empty.bestWindow == nil)
        #expect(empty.stopCount == 0)
        #expect(!empty.hasConflict)
        // The drive in skips the empty day and lands on day 3.
        if case .driveIn = layout.groups[2].items.first {} else { Issue.record("day 3 should start with the drive in") }
        // You sleep where the last stop was, also across the empty day.
        #expect(layout.groups[0].overnightAfter?.spotName == h.spot("mesa-arch").name)
        #expect(layout.groups[1].overnightAfter?.spotName == h.spot("mesa-arch").name)
        #expect(layout.groups[2].overnightAfter == nil)
    }

    @Test func overnightNamesTheLastStopsPlace() async {
        let h = TripHarness()
        let (layout, model) = await layout(h.makeTrip(), in: h)
        let last = model.days[0].stops[1].stop.spot
        #expect(layout.groups[0].overnightAfter?.spotName == last.name)
        #expect(layout.groups[0].overnightAfter?.locality == last.locality)
        #expect(layout.groups[0].overnightAfter?.place == (last.locality.isEmpty ? last.name : last.locality))
        #expect(layout.groups[1].overnightAfter == nil)
    }

    @Test func theBestWindowIsTheHighestScoreThenTheFirstStop() async throws {
        let h = TripHarness()
        let (_, model) = await layout(h.makeTrip(), in: h)
        var days = model.days
        // No scores (no weather): the first stop's session window.
        let unscored = TripDayLayout.make(days: days, suggestions: [])
        #expect(unscored.groups[0].bestWindow?.stopID == days[0].stops[0].id)
        #expect(unscored.groups[0].bestWindow?.window.kind == days[0].stops[0].sessionWindow?.kind)

        // Scores on both stops: the higher one wins, whichever comes first.
        days[0].stops[0].sessionWindow?.assessment = score(40)
        days[0].stops[1].sessionWindow?.assessment = score(72)
        let scored = TripDayLayout.make(days: days, suggestions: [])
        #expect(scored.groups[0].bestWindow?.stopID == days[0].stops[1].id)
        #expect(scored.groups[0].bestWindow?.window.score == 72)

        // A tie goes to the earlier stop.
        days[0].stops[1].sessionWindow?.assessment = score(40)
        let tied = TripDayLayout.make(days: days, suggestions: [])
        #expect(tied.groups[0].bestWindow?.stopID == days[0].stops[0].id)

        // A scored window beats an unscored first stop.
        days[0].stops[0].sessionWindow?.assessment = .noForecast(.notLoaded)
        let mixed = TripDayLayout.make(days: days, suggestions: [])
        #expect(mixed.groups[0].bestWindow?.stopID == days[0].stops[1].id)
    }

    @Test func conflictsAttachToTheRightDay() async throws {
        let h = TripHarness()
        let trip = h.store.createTrip(name: "Backwards", startDay: TripHarness.start, dayCount: 2)
        // Day 0 is fine; day 1 lists a sunset stop before a sunrise stop.
        h.store.addStop(h.spot("mesa-arch"), to: trip, day: 0, session: .goldenMorning)
        h.store.addStop(h.spot("delicate-arch"), to: trip, day: 1, session: .goldenEvening)
        h.store.addStop(h.spot("mesa-arch"), to: trip, day: 1, session: .goldenMorning)
        let (layout, model) = await layout(trip, in: h)
        #expect(layout.groups[0].conflictCount == 0)
        #expect(layout.groups[1].conflictCount >= 1)
        #expect(layout.groups[1].conflictCount == model.days[1].stops.reduce(0) { $0 + $1.conflicts.count })
        #expect(!layout.groups[0].hasConflict)
        #expect(layout.groups[1].hasConflict)
        #expect(layout.groups[1].suggestion?.dayIndex == 1)
        #expect(layout.groups[0].suggestion == nil)
        // The cells carry the same flags.
        #expect(layout.overviewCells.map(\.hasConflict) == [false, true])
    }

    @Test func overviewCellsMatchTheGroups() async {
        let h = TripHarness()
        let (layout, _) = await layout(h.makeTrip(), in: h)
        let cells = layout.overviewCells
        #expect(cells.count == layout.groups.count)
        for (cell, group) in zip(cells, layout.groups) {
            #expect(cell.index == group.index)
            #expect(cell.date == group.date)
            #expect(cell.stopCount == group.stopCount)
            #expect(cell.bestWindow == group.bestWindow)
            #expect(cell.hasConflict == group.hasConflict)
        }
    }

    @Test func numberingContinuesAcrossDays() async {
        let h = TripHarness()
        let (layout, _) = await layout(h.makeTrip(), in: h)
        let numbers = layout.groups.flatMap(\.stops).map(\.number)
        #expect(numbers == [1, 2, 3])
        #expect(layout.groups[1].stops.first?.number == 3)
        #expect(layout.day(ofStop: layout.groups[1].stops[0].id) == 1)
    }

    @Test func estimatedDrivesAreNotConflicts() async {
        let h = TripHarness()
        let model = h.model(for: h.makeTrip(), drives: FakeDrives(fail: true))
        await model.waitForLegs()
        #expect(model.layout.groups[0].hasEstimatedDrive)
        #expect(model.layout.groups[0].conflictCount == 0)
    }
}
