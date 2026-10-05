import Foundation
import Testing
import IterCore
import IterLight
import IterData
@testable import IterFeatures

@MainActor
@Suite struct TripBuilderModelTests {
    @Test func requestsTheDrivesTheSchedulerNeeds() async {
        let h = TripHarness()
        let trip = h.makeTrip()
        let drives = FakeDrives()
        let model = h.model(for: trip, drives: drives)
        await model.waitForLegs()

        let plan = model.plan!
        let expected = Set(h.scheduler.legPairsNeeded(for: plan).map { key -> FakeDrives.LegRequest in
            let a = plan.stops.first(where: { $0.id == key.from })!.spot.coordinate
            let b = plan.stops.first(where: { $0.id == key.to })!.spot.coordinate
            return .init(from: a, to: b)
        })
        let calls = await drives.calls
        #expect(Set(calls) == expected)
        #expect(calls.count == expected.count, "each pair is fetched once")
        #expect(model.legs.count == expected.count)
        #expect(!model.isLoadingLegs)
        // Current order: Mesa -> Delicate (same day), Delicate -> Horseshoe (overnight).
        #expect(model.days[0].stops[1].schedule?.legFromPrevious?.isEstimate == false)
        #expect(model.days[1].stops[0].isOvernightFromPrevious)
    }

    @Test func fallsBackToEstimatesWhenMapsFails() async {
        let h = TripHarness()
        let trip = h.makeTrip()
        let model = h.model(for: trip, drives: FakeDrives(fail: true))
        await model.waitForLegs()
        #expect(!model.legs.isEmpty)
        let allEstimates = model.legs.values.allSatisfy { $0.isEstimate }
        #expect(allEstimates)
        let second = model.days[0].stops[1].schedule
        #expect(second?.issues.contains(.driveEstimated) == true)
        #expect(model.days[0].hasEstimatedDrive)
    }

    @Test func loadingFlagCoversTheFetch() async {
        let h = TripHarness()
        let trip = h.makeTrip()
        let model = h.model(for: trip)
        #expect(model.isLoadingLegs)
        await model.waitForLegs()
        #expect(!model.isLoadingLegs)
    }

    @Test func movingAStopRecomputesTheSchedule() async {
        let h = TripHarness()
        let trip = h.makeTrip()
        let drives = FakeDrives()
        let model = h.model(for: trip, drives: drives)
        await model.waitForLegs()
        let mesa = model.days[0].stops[0].id
        let delicate = model.days[0].stops[1].id
        let horseshoe = model.days[1].stops[0].id

        // Move Horseshoe Bend to day 0, before Delicate Arch.
        model.moveStop(horseshoe, toDay: 0, before: delicate)
        #expect(model.days[0].stops.map(\.id) == [mesa, horseshoe, delicate])
        #expect(model.days[1].stops.isEmpty)
        #expect(model.days[0].stops.map(\.number) == [1, 2, 3])
        // Horseshoe now follows Mesa Arch, so its incoming leg is that pair.
        let mesaCoordinate = model.plan!.stops.first(where: { $0.id == mesa })!.spot.coordinate
        #expect(model.schedule.schedule(for: horseshoe)?.legFromPrevious?.from == mesaCoordinate)
        await model.waitForLegs()
        let calls = await drives.calls
        #expect(calls.count > 2, "new pairs are fetched after the move")
        #expect(model.legs[LegKey(mesa, horseshoe)] != nil)

        // Undoing is the store's job, but the model must follow the store after a refresh.
        model.nudgeStop(horseshoe, by: 1)
        #expect(model.days[0].stops.map(\.id) == [mesa, delicate, horseshoe])
        #expect(!model.canNudge(horseshoe, by: 1))
        #expect(model.canNudge(horseshoe, by: -1))
    }

    @Test func removingAndEditingFlowThrough() async {
        let h = TripHarness()
        let trip = h.makeTrip()
        let model = h.model(for: trip)
        await model.waitForLegs()
        let id = model.days[0].stops[0].id
        model.setSession(id, to: .blueMorning)
        model.setNote(id, to: "Bring the wide lens")
        model.setBuffer(id, minutes: 35)
        let stop = model.plan!.stops.first(where: { $0.id == id })!
        #expect(stop.session == .blueMorning)
        #expect(stop.note == "Bring the wide lens")
        #expect(stop.setUpBufferMinutes == 35)
        model.removeStop(id)
        #expect(model.plan!.stops.count == 2)
    }

    @Test func addStopAppliesTheDefaultBuffer() async {
        let h = TripHarness()
        let trip = h.makeTrip()
        let model = h.model(for: trip)
        let id = model.addStop(h.spot("goblin-valley"), toDay: 1, defaultBufferMinutes: 45)
        let added = model.plan!.stops.first(where: { $0.id == id })!
        #expect(added.setUpBufferMinutes == 45)
        #expect(added.dayIndex == 1)
        #expect(added.session == h.spot("goblin-valley").defaultSession)
        #expect(model.days[1].stops.last?.id == id)
        let defaulted = model.addStop(h.spot("monument-valley"), toDay: 1, defaultBufferMinutes: 20)
        #expect(model.plan!.stops.first(where: { $0.id == defaulted })!.setUpBufferMinutes == 20)
    }

    @Test func suggestionApplyAndDismiss() async throws {
        let h = TripHarness()
        let trip = h.store.createTrip(name: "Backwards", startDay: TripHarness.start, dayCount: 1)
        // Sunset first, then sunrise: the order is backwards.
        h.store.addStop(h.spot("delicate-arch"), to: trip, day: 0, session: .goldenEvening)
        h.store.addStop(h.spot("mesa-arch"), to: trip, day: 0, session: .goldenMorning)

        let dismissals = SuggestionDismissals()
        let model = h.model(for: trip, dismissals: dismissals)
        await model.waitForLegs()
        let suggestion = try #require(model.suggestion(forDay: 0))
        #expect(model.conflictsFixed(by: suggestion) >= 1)
        #expect(model.days[0].stops[1].schedule?.issues.contains(.outOfOrder) == true)

        // Dismissing hides it for this trip, day and order; the plan itself is untouched.
        model.dismiss(suggestion)
        #expect(model.suggestion(forDay: 0) == nil)
        #expect(model.days[0].stops.map(\.stop.spot.id) == ["delicate-arch", "mesa-arch"])
        // A fresh model in the same session still remembers.
        let again = h.model(for: trip, dismissals: dismissals)
        #expect(again.suggestion(forDay: 0) == nil)
        // Without that memory it comes back.
        let fresh = h.model(for: trip)
        let back = try #require(fresh.suggestion(forDay: 0))

        fresh.apply(back)
        #expect(fresh.days[0].stops.map(\.stop.spot.id) == ["mesa-arch", "delicate-arch"])
        #expect(fresh.suggestion(forDay: 0) == nil)
        #expect(fresh.schedule.issueCount < suggestion.issuesBefore)
    }

    @Test func shrinkingDatesCountsAndMovesStops() async {
        let h = TripHarness()
        let trip = h.makeTrip()
        let model = h.model(for: trip)
        #expect(model.stopsDisplaced(byDayCount: 2) == 0)
        #expect(model.stopsDisplaced(byDayCount: 1) == 1)
        let moved = model.setDates(start: TripHarness.start.adding(days: 1), dayCount: 1)
        #expect(moved == 1)
        #expect(model.plan!.dayCount == 1)
        #expect(model.plan!.startDay == TripHarness.start.adding(days: 1))
        #expect(model.days.count == 1)
        #expect(model.days[0].stops.count == 3)
    }

    @Test func deletedTripBecomesUnavailable() async {
        let h = TripHarness()
        let trip = h.makeTrip()
        let model = h.model(for: trip)
        #expect(model.plan != nil)
        model.deleteTrip()
        #expect(model.plan == nil)
        #expect(model.days.isEmpty)
        #expect(!model.isLoadingLegs)
    }

    @Test func dayTotalsIncludeTheOvernightDrive() async {
        let h = TripHarness()
        let trip = h.makeTrip()
        let model = h.model(for: trip, drives: FakeDrives(minutes: 30))
        await model.waitForLegs()
        #expect(model.days[0].drivingSeconds == 30 * 60)   // Mesa -> Delicate
        #expect(model.days[1].drivingSeconds == 30 * 60)   // overnight into day 2
        #expect(!model.days[0].hasEstimatedDrive)
        #expect(model.days[0].sunrise != nil && model.days[0].sunset != nil)
    }
}

@MainActor
@Suite struct AddStopCandidatesTests {
    @Test func nearestToTheDaysLastStopFirst() {
        let h = TripHarness()
        let trip = h.makeTrip()
        let plan = trip.plan
        let curated = CuratedSpots.all
        let list = AddStopCandidates.make(plan: plan, day: 0, saved: [], curated: curated, query: "")
        #expect(list.anchor?.id == "delicate-arch")
        let distances = list.candidates.compactMap(\.distanceMeters)
        #expect(distances == distances.sorted())
        let hasOnDay = list.candidates.contains { $0.isOnDay }
        #expect(hasOnDay)
        // Yosemite is nowhere near Utah.
        let ids = list.candidates.map(\.id)
        #expect(ids.firstIndex(of: "tunnel-view")! > ids.firstIndex(of: "mesa-arch")!)
    }

    @Test func emptyDayUsesThePreviousDaysLastStop() {
        let h = TripHarness()
        let trip = h.store.createTrip(name: "x", startDay: TripHarness.start, dayCount: 3)
        h.store.addStop(h.spot("mesa-arch"), to: trip, day: 0)
        let list = AddStopCandidates.make(plan: trip.plan, day: 2, saved: [], curated: CuratedSpots.all, query: "")
        #expect(list.anchor?.id == "mesa-arch")
        let none = AddStopCandidates.make(plan: h.store.createTrip(name: "e", startDay: TripHarness.start, dayCount: 1).plan,
                                          day: 0, saved: [], curated: CuratedSpots.all, query: "")
        #expect(none.anchor == nil)
        #expect(none.candidates.allSatisfy { $0.distanceMeters == nil })
    }

    @Test func searchFiltersAndSavedMergeWithCurated() {
        let h = TripHarness()
        let trip = h.makeTrip()
        let mesa = h.spot("mesa-arch")
        let list = AddStopCandidates.make(plan: trip.plan, day: 1, saved: [mesa], curated: CuratedSpots.all, query: "mesa")
        let mesaRows = list.candidates.filter { $0.id == "mesa-arch" }
        #expect(mesaRows.count == 1)
        #expect(mesaRows.first?.isSaved == true)
        let allMatch = list.candidates.allSatisfy { $0.spot.name.localizedCaseInsensitiveContains("mesa") || $0.spot.locality.localizedCaseInsensitiveContains("mesa") }
        #expect(allMatch)
    }
}
