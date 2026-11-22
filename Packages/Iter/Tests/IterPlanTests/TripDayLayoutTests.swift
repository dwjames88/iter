import Foundation
import Testing
import IterModel
import IterSky
@testable import IterPlan

// Ported from IterFeaturesTests/TripDayLayoutTests (10 tests; 9 carry, `overviewCellsMatchTheGroups` does not: the overview
// cells were dropped as test-only dead code). They run on the pure builders instead of the old TripBuilderModel.

@Suite struct TripDayLayoutTests {
    let h = TripHarness()

    private func stopIDs(_ group: TripDayGroup) -> [UUID] { group.stops.map(\.id) }

    @Test func stopsAreGroupedByDayInOrder() {
        let b = h.build(h.makeTrip())
        let layout = b.layout
        #expect(layout.groups.map(\.index) == [0, 1])
        #expect(stopIDs(layout.groups[0]) == b.days[0].stops.map(\.id))
        #expect(stopIDs(layout.groups[1]) == b.days[1].stops.map(\.id))
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

    @Test func theDriveInBelongsToTheNextDay() {
        let b = h.build(h.makeTrip())
        let horseshoe = b.days[1].stops[0]
        guard case .driveIn(let drive) = b.layout.groups[1].items.first else {
            Issue.record("day 2 should start with the drive in")
            return
        }
        #expect(drive.toStopID == horseshoe.id)
        #expect(drive.fromName == b.days[0].stops[1].stop.place.name)
        #expect(!drive.fromStart)
        #expect(drive.leg != nil)
        #expect(drive.leaveBy == horseshoe.schedule?.leaveBy)
        // Day 1 has no drive in (no start place) and no drive leaving it.
        let driveInsOnDayOne = b.layout.groups[0].items.filter { if case .driveIn = $0 { true } else { false } }
        #expect(driveInsOnDayOne.isEmpty)
        #expect(b.layout.groups[0].items.filter { $0.isDrive }.count == 1)
    }

    @Test func aDayWithNoStopsHasJustAddStopAndNoBestWindow() {
        let trip = h.trip(days: 3, [(h.mesa, 0, .goldenMorning), (h.horseshoe, 2, .goldenEvening)])
        let layout = h.build(trip).layout
        let empty = layout.groups[1]
        #expect(empty.items.count == 1)
        if case .addStop(let day) = empty.items[0] { #expect(day == 1) } else { Issue.record("expected addStop") }
        #expect(empty.bestWindow == nil)
        #expect(empty.stopCount == 0)
        #expect(!empty.hasConflict)
        // The drive in skips the empty day and lands on day 3.
        if case .driveIn = layout.groups[2].items.first {} else { Issue.record("day 3 should start with the drive in") }
        // You sleep where the last stop was, also across the empty day.
        #expect(layout.groups[0].overnightAfter?.placeName == h.mesa.name)
        #expect(layout.groups[1].overnightAfter?.placeName == h.mesa.name)
        #expect(layout.groups[2].overnightAfter == nil)
    }

    @Test func overnightNamesTheLastStopsPlace() {
        let b = h.build(h.makeTrip())
        let last = b.days[0].stops[1].stop.place
        #expect(b.layout.groups[0].overnightAfter?.placeName == last.name)
        #expect(b.layout.groups[0].overnightAfter?.locality == last.locality)
        #expect(b.layout.groups[0].overnightAfter?.place == (last.locality.isEmpty ? last.name : last.locality))
        #expect(b.layout.groups[1].overnightAfter == nil)
    }

    @Test func driveItemsCarryTheTimingAndTheNote() {
        var trip = h.makeTrip()
        trip.stops[1].driveNote = "Coffee"
        trip.stops[2].driveNote = "Sleep near Page"
        trip.transferTimings[1] = .eveningBefore
        let layout = h.build(trip).layout
        guard case .drive(let same)? = layout.groups[0].items.dropFirst().first else { Issue.record("drive"); return }
        #expect(same.note == "Coffee")
        #expect(same.transferTiming == nil)
        guard case .driveIn(let transfer)? = layout.groups[1].items.first else { Issue.record("driveIn"); return }
        #expect(transfer.note == "Sleep near Page")
        #expect(transfer.transferTiming == .eveningBefore)
    }

    @Test func theBestWindowIsTheHighestScoreThenTheFirstStop() {
        var days = h.build(h.makeTrip()).days
        // No scores (no weather): the first stop's session window.
        let unscored = TripDayLayout.make(days: days, suggestions: [])
        #expect(unscored.groups[0].bestWindow?.stopID == days[0].stops[0].id)
        #expect(unscored.groups[0].bestWindow?.window.kind == days[0].stops[0].sessionWindow?.kind)

        // Scores on both stops: the higher one wins, whichever comes first.
        days[0].stops[0].sessionWindow?.assessment = scored(40)
        days[0].stops[1].sessionWindow?.assessment = scored(72)
        let scoredLayout = TripDayLayout.make(days: days, suggestions: [])
        #expect(scoredLayout.groups[0].bestWindow?.stopID == days[0].stops[1].id)
        #expect(scoredLayout.groups[0].bestWindow?.window.score == 72)

        // A tie goes to the earlier stop.
        days[0].stops[1].sessionWindow?.assessment = scored(40)
        let tied = TripDayLayout.make(days: days, suggestions: [])
        #expect(tied.groups[0].bestWindow?.stopID == days[0].stops[0].id)

        // A scored window beats an unscored first stop.
        days[0].stops[0].sessionWindow?.assessment = .unavailable(.notLoaded)
        let mixed = TripDayLayout.make(days: days, suggestions: [])
        #expect(mixed.groups[0].bestWindow?.stopID == days[0].stops[1].id)
    }

    @Test func conflictsAttachToTheRightDay() {
        // Day 0 is fine; day 1 lists a sunset stop before a sunrise stop.
        let trip = h.trip(days: 2, [(h.mesa, 0, .goldenMorning), (h.delicate, 1, .goldenEvening), (h.mesa, 1, .goldenMorning)])
        let b = h.build(trip)
        #expect(b.layout.groups[0].conflictCount == 0)
        #expect(b.layout.groups[1].conflictCount >= 1)
        #expect(b.layout.groups[1].conflictCount == b.days[1].stops.reduce(0) { $0 + $1.conflicts.count })
        #expect(!b.layout.groups[0].hasConflict)
        #expect(b.layout.groups[1].hasConflict)
        #expect(b.layout.groups[1].suggestion?.dayIndex == 1)
        #expect(b.layout.groups[0].suggestion == nil)
    }

    @Test func numberingContinuesAcrossDays() {
        let layout = h.build(h.makeTrip()).layout
        let numbers = layout.groups.flatMap(\.stops).map(\.number)
        #expect(numbers == [1, 2, 3])
        #expect(layout.groups[1].stops.first?.number == 3)
        #expect(layout.day(ofStop: layout.groups[1].stops[0].id) == 1)
    }

    @Test func estimatedDrivesAreNotConflicts() {
        let layout = h.build(h.makeTrip(), driveMinutes: nil).layout
        #expect(layout.groups[0].hasEstimatedDrive)
        #expect(layout.groups[0].conflictCount == 0)
    }
}

// New: what the start place, lodging and totals add.
@Suite struct TripDaysTests {
    let h = TripHarness()

    @Test func theFirstStopsDriveComesFromTheStartPlace() {
        let b = h.build(h.makeTrip(start: h.home), start: h.home)
        guard case .driveIn(let drive)? = b.layout.groups[0].items.first else { Issue.record("day 1 should start with a drive in"); return }
        #expect(drive.fromStart && drive.fromName == "Home" && drive.fromLocality == "Moab, UT")
        #expect(drive.toStopID == b.days[0].stops[0].id)
        #expect(drive.transferTiming == nil && drive.fits)
        #expect(drive.leaveBy == b.days[0].stops[0].schedule?.leaveBy && drive.leaveBy != nil)
        #expect(b.days[0].stops[0].startPlace == h.home)
        #expect(b.days[0].stops[1].startPlace == nil)
        // It is a real drive: day 0's total counts it (start -> Mesa, Mesa -> Delicate, 60 minutes each).
        #expect(b.days[0].drivingSeconds == 2 * 3600)
        #expect(b.days[1].drivingSeconds == 3600)
    }

    @Test func noStartPlaceMeansNoDriveInOnDayZero() {
        let b = h.build(h.makeTrip())
        #expect(b.days[0].drivingSeconds == 3600)
        #expect(!b.layout.groups[0].items.contains { if case .driveIn = $0 { true } else { false } })
    }

    @Test func anEveningBeforeTransferCountsTowardTheDayBefore() {
        var trip = h.makeTrip()
        trip.transferTimings[1] = .eveningBefore
        let b = h.build(trip)
        #expect(b.days[0].drivingSeconds == 2 * 3600)
        #expect(b.days[1].drivingSeconds == 0)
        #expect(b.days[1].transferTiming == .eveningBefore && b.days[0].transferTiming == .morning)
    }

    @Test func aLodgingIsListedAndHasNoWindowOrConflict() {
        var trip = h.makeTrip()
        trip.stops.insert(Stop(place: h.horseshoe, dayIndex: 0, session: .goldenEvening, kind: .lodging), at: 2)
        let b = h.build(trip)
        let hotel = b.days[0].stops[2]
        #expect(hotel.stop.kind == .lodging && hotel.sessionWindow == nil && hotel.conflicts.isEmpty)
        #expect(hotel.number == 3 && b.days[1].stops[0].number == 4)
        #expect(b.layout.groups[0].overnightAfter?.placeName == h.horseshoe.name)
        #expect(b.layout.groups[0].bestWindow?.stopID == b.days[0].stops[0].id)
    }

    @Test func sunTimesComeFromTheFirstStopInItsOwnZone() {
        let b = h.build(h.makeTrip())
        #expect(b.days[0].timeZoneIdentifier == "America/Denver")
        #expect(b.days[1].timeZoneIdentifier == "America/Phoenix")
        #expect(b.days[0].sunrise != nil && b.days[0].sunset != nil && b.days[0].sunrise! < b.days[0].sunset!)
        #expect(b.layout.groups[1].timeZone.identifier == "America/Phoenix")
    }

    @Test func aStopWithNoLightIsStillListed() {
        let trip = h.makeTrip()
        let schedule = Scheduler().schedule(trip: trip, start: nil, windows: [:], legs: [:])
        let days = TripDays.make(trip: trip, start: nil, schedule: schedule, lights: [:])
        #expect(days.flatMap(\.stops).count == 3)
        #expect(days[0].stops.allSatisfy { $0.windows.isEmpty && $0.sessionWindow == nil })
        #expect(days[0].sunrise == nil && days[0].timeZone == .gmt)
        #expect(days[0].stops[0].conflicts == [.windowMissing])
    }

    @Test func theSchedulerWindowsComeFromTheEngine() {
        // Ports `suppliedWindowsGiveTheSameResultsAsComputingThem`: the windows are no longer computed inside the scheduler, so
        // what is checked is that `sessionWindows(for:engine:)` is exactly the engine's window for each light stop, and that
        // feeding them in is what `schedule` and `suggestOrdering` use.
        var trip = h.makeTrip()
        trip.stops.append(Stop(place: h.home, dayIndex: 1, session: .goldenMorning, kind: .waypoint))
        let windows = Scheduler().sessionWindows(for: trip, engine: h.engine)
        #expect(windows.count == 3)
        for stop in trip.stops where stop.kind == .light {
            #expect(windows[stop.id] == h.engine.windows(for: stop.place, on: trip.day(stop.dayIndex)).first { $0.kind == stop.session }?.span)
        }
        #expect(windows[trip.stops[3].id] == nil)
        #expect(Scheduler().schedule(trip: trip, start: nil, windows: windows, legs: [:]).schedule(for: trip.stops[3].id)?.issues.contains(.windowMissing) == false)
    }

    @Test func aFixedTimeOnTheFallBackDayIsReadInTheZoneOfThatDay() {
        // Denver clocks go back on 2026-11-01: 06:00 is MST (UTC-7), 13:00Z; the day before it would be MDT, 12:00Z.
        let fall = LocalDay(year: 2026, month: 11, day: 1)
        let stop = Stop(place: h.mesa, dayIndex: 1, session: .goldenMorning, fixedArrival: LocalTime(hour: 6, minute: 0), kind: .waypoint)
        let trip = Trip(name: "dst", startDay: fall.adding(days: -1), dayCount: 2, stops: [stop])
        let s = Scheduler().schedule(trip: trip, start: nil, windows: [:], legs: [:]).schedule(for: stop.id)!
        #expect(s.arriveBy == fall.at(hour: 6, in: h.mesa.timeZone))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        #expect(utc.component(.hour, from: s.arriveBy!) == 13)
        let before = Scheduler.fixedInstant(LocalTime(hour: 6, minute: 0), day: fall.adding(days: -1), in: h.mesa.timeZone)
        #expect(utc.component(.hour, from: before) == 12)
    }
}
