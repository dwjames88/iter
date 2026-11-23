import Foundation
import Testing
import IterConditions
import IterModel
import IterSources
@testable import IterFeatures

@MainActor
@Suite struct BuildConditionsTests {
    private func key(_ h: BuildHarness, _ model: BuildModel, _ name: String, day: Int) -> FakeConditions.Key {
        FakeConditions.Key(placeID: model.stop(named: name)!.placeID, day: h.day.adding(days: day))
    }

    // MARK: Request order

    @Test func requestsGoSelectedDayFirstThenSoonestInTime() throws {
        let h = try BuildHarness()
        let model = h.model()
        model.selectDay(2)
        model.open()
        let asked = h.conditions.requests
        #expect(asked.map(\.name) == ["Mesa Arch", "Delicate Arch", "Goblin Valley", "Horseshoe Bend", "Monument Valley", "Dead Horse Point"])
        #expect(asked.map(\.priority) == [.onScreen, .onScreen, .activeTrip, .activeTrip, .activeTrip, .activeTrip])
        #expect(asked.map(\.day) == [2, 2, 3, 0, 1, 1].map { h.day.adding(days: $0) })
        // The trip's places are the active trip; the selected day's are on screen.
        #expect(h.conditions.activeTrip.count == 6)
        #expect(h.conditions.visible == Set([model.stop(named: "Mesa Arch")!.placeID, model.stop(named: "Delicate Arch")!.placeID]))
    }

    @Test func withNoDaySelectedTheTripLoadsInDateOrder() throws {
        let h = try BuildHarness()
        let model = h.model()
        model.open()
        #expect(h.conditions.requests.map(\.name) == ["Horseshoe Bend", "Monument Valley", "Dead Horse Point", "Mesa Arch", "Delicate Arch", "Goblin Valley"])
        #expect(h.conditions.requests.first?.priority == .onScreen)
        #expect(h.conditions.requests.dropFirst().allSatisfy { $0.priority == .activeTrip })
    }

    @Test func choosingADayMovesWhatIsOnScreenWithoutAskingAgain() throws {
        let h = try BuildHarness()
        let model = h.model()
        model.open()
        let count = h.conditions.requests.count
        model.selectDay(3)
        #expect(h.conditions.requests.count == count)
        #expect(h.conditions.visible == [model.stop(named: "Goblin Valley")!.placeID])
    }

    @Test func aNewStopIsAskedForAndNothingElseIsAskedAgain() throws {
        let h = try BuildHarness()
        let model = h.model()
        model.open()
        let count = h.conditions.requests.count
        _ = model.addStop(h.spot("bryce-sunset-point"), day: 1)
        #expect(h.conditions.requests.count == count + 1)
        #expect(h.conditions.requests.last?.name == "Sunset Point")
        #expect(h.conditions.activeTrip.count == 7)
    }

    @Test func closingReleasesTheActiveTrip() throws {
        let h = try BuildHarness()
        let model = h.model()
        model.open()
        model.close()
        #expect(h.conditions.activeTrip.isEmpty)
        model.open()
        #expect(h.conditions.requests.count == 12, "reopening asks again")
    }

    // MARK: Progress

    @Test func progressNamesWhatIsStillLoading() throws {
        let h = try BuildHarness()
        let model = h.model()
        #expect(model.conditionsProgress.text == "Conditions: 0 of 6 stops ready; waiting for a first score for 6")
        let names = ["Horseshoe Bend": 0, "Monument Valley": 1, "Dead Horse Point": 1, "Mesa Arch": 2, "Delicate Arch": 2, "Goblin Valley": 3]
        for (name, day) in names {
            let complete = ["Horseshoe Bend", "Monument Valley", "Mesa Arch", "Delicate Arch"].contains(name)
            h.conditions.samples[key(h, model, name, day: day)] = ConditionsSample(
                tier: complete ? .complete : .quick, scores: [.goldenEvening: 50, .goldenMorning: 50],
                pendingSources: complete ? [] : [.noaaNOMADS])
        }
        model.refreshIfChanged()
        #expect(model.conditionsProgress.text == "Conditions: 4 of 6 stops ready; NOAA forecast still loading for 2")
        #expect(model.conditionsProgress.readyStops == 4 && model.conditionsProgress.improvingStops == 2)
        for (name, day) in names {
            h.conditions.samples[key(h, model, name, day: day)] = ConditionsSample(tier: .complete, scores: [.goldenEvening: 50])
        }
        model.refreshIfChanged()
        #expect(model.conditionsProgress.text == "Conditions: all 6 stops ready")
        #expect(model.conditionsProgress.isComplete)
    }

    @Test func progressTextForOneStopAndNone() throws {
        let h = try BuildHarness(template: false)
        let model = h.model()
        #expect(model.conditionsProgress.text == "")
        _ = model.addStop(h.spot("mesa-arch"), day: 0)
        #expect(model.conditionsProgress.text == "Conditions: 0 of 1 stop ready; waiting for a first score for 1")
        h.conditions.samples[key(h, model, "Mesa Arch", day: 0)] = ConditionsSample(tier: .complete, scores: [:])
        model.refreshIfChanged()
        #expect(model.conditionsProgress.text == "Conditions: 1 stop ready")
    }

    @Test func aSlowSourceShowsByNameAmongSeveral() {
        let progress = BuildConditionsProgress(totalStops: 9, readyStops: 4, improvingStops: 5, waitingStops: 0,
                                               pendingBySource: ["NOAA": 3, "MET Norway": 1])
        #expect(progress.text == "Conditions: 4 of 9 stops ready; NOAA forecast still loading for 3; MET Norway forecast still loading for 1")
        #expect(BuildModel.sourceName(.noaaNOMADS) == "NOAA" && BuildModel.sourceName(.noaaHRRRSmoke) == "NOAA")
        #expect(BuildModel.sourceName(.metNorway) == "MET Norway")
    }

    // MARK: No flicker

    @Test func aScoreIsKeptWhileABetterForecastLoadsAndNeverStepsBack() throws {
        let h = try BuildHarness()
        let model = h.model()
        let id = model.stop(named: "Horseshoe Bend")!.id
        let slot = key(h, model, "Horseshoe Bend", day: 0)
        #expect(model.stop(named: "Horseshoe Bend")?.score == nil)
        // The quick MET Norway score arrives first.
        h.conditions.samples[slot] = ConditionsSample(tier: .quick, scores: [.goldenEvening: 55, .goldenMorning: 40], pendingSources: [.noaaNOMADS])
        model.refreshIfChanged()
        #expect(model.stopRows.first { $0.id == id }?.score == 55)
        #expect(model.stopRows.first { $0.id == id }?.scoreIsImproving == true)
        // The next report has no score for the window yet: the one on screen stays.
        h.conditions.samples[slot] = ConditionsSample(tier: .nearTerm, scores: [.goldenMorning: 42], pendingSources: [.noaaNOMADS])
        model.refreshIfChanged()
        #expect(model.stopRows.first { $0.id == id }?.score == 55)
        #expect(model.stop(named: "Horseshoe Bend")?.options.first { $0.kind == .goldenMorning }?.score == 42)
        // The better forecast replaces it.
        h.conditions.samples[slot] = ConditionsSample(tier: .complete, scores: [.goldenEvening: 71, .goldenMorning: 42])
        model.refreshIfChanged()
        #expect(model.stopRows.first { $0.id == id }?.score == 71)
        #expect(model.stopRows.first { $0.id == id }?.scoreIsImproving == false)
        // A late, lower tier answer from a superseded load is ignored.
        h.conditions.samples[slot] = ConditionsSample(tier: .quick, scores: [.goldenEvening: 30])
        model.refreshIfChanged()
        #expect(model.stopRows.first { $0.id == id }?.score == 71)
    }

    @Test func aSlotWithNoReportYetKeepsWhatWasShown() throws {
        let h = try BuildHarness()
        let model = h.model()
        let slot = key(h, model, "Mesa Arch", day: 2)
        h.conditions.samples[slot] = ConditionsSample(tier: .quick, scores: [.goldenMorning: 64])
        model.refreshIfChanged()
        h.conditions.samples[slot] = .empty   // the slot went back to loading with no previous report visible
        model.refreshIfChanged()
        #expect(model.stop(named: "Mesa Arch")?.score == 64)
    }

    @Test func aForecastUpdateRecomputesOnceAfterTheBurst() async throws {
        let sleeper = TestSleeper(holds: { $0 == .milliseconds(60) })
        let h = try BuildHarness(sleeper: sleeper)
        let model = h.model()
        model.open()
        let before = model.recomputeCount
        // Three slots change in one burst; the observation schedules one coalesced refresh.
        for (name, day) in [("Mesa Arch", 2), ("Delicate Arch", 2), ("Goblin Valley", 3)] {
            h.conditions.samples[key(h, model, name, day: day)] = ConditionsSample(tier: .quick, scores: [.goldenEvening: 60, .goldenMorning: 60])
        }
        #expect(await settle { sleeper.waiting == [.milliseconds(60)] })
        #expect(model.recomputeCount == before)
        sleeper.fire()
        #expect(await settle { model.recomputeCount == before + 1 })
        #expect(model.stop(named: "Mesa Arch")?.score == 60)
        model.close()
    }

    // MARK: Offline packs

    @Test func aPackIsBuiltOnlyForPinnedTrips() async throws {
        let h = try BuildHarness()
        let model = h.model()
        model.open()
        for _ in 0..<50 { await Task.yield() }
        #expect(h.packs.builds.isEmpty)
        #expect(model.packState == .none)
        // Pinning builds it.
        model.setPinned(true)
        #expect(await settle { if case .ready = model.packState { true } else { false } })
        #expect(h.packs.builds.count == 1)
        #expect(h.packs.builds[0].id == h.trip.id && h.packs.builds[0].stops.count == 6)
        #expect(model.packState == .ready(builtAt: testNow))
        // Unpinning drops the state and builds nothing.
        model.setPinned(false)
        #expect(model.packState == .none)
        for _ in 0..<50 { await Task.yield() }
        #expect(h.packs.builds.count == 1)
        model.close()
    }

    @Test func aPinnedTripBuildsOnOpenUnlessItsPackIsFresh() async throws {
        // A pack built 10 minutes ago is fresh.
        let fresh = try BuildHarness(packExisting: testNow.addingTimeInterval(-600))
        fresh.library.trips.setPinned(fresh.trip, true)
        let a = fresh.model()
        a.open()
        #expect(await settle { if case .ready = a.packState { true } else { false } })
        #expect(fresh.packs.builds.isEmpty)
        #expect(a.packState == .ready(builtAt: testNow.addingTimeInterval(-600)))
        a.close()
        // A pack built two hours ago is rebuilt; so is a missing one.
        let stale = try BuildHarness(packExisting: testNow.addingTimeInterval(-7200))
        stale.library.trips.setPinned(stale.trip, true)
        let b = stale.model()
        b.open()
        #expect(await settle { b.packState == .ready(builtAt: testNow) })
        #expect(stale.packs.builds.count == 1)
        b.close()
        let none = try BuildHarness()
        none.library.trips.setPinned(none.trip, true)
        let c = none.model()
        #expect(c.packState == .none)
        c.open()
        #expect(await settle { c.packState == .ready(builtAt: testNow) })
        c.close()
    }

    @Test func aPinnedPackIsRebuiltWhenTheStopsChangeButNotForANote() async throws {
        let h = try BuildHarness()
        h.library.trips.setPinned(h.trip, true)
        let model = h.model()
        model.open()
        #expect(await settle { model.packState == .ready(builtAt: testNow) })
        #expect(h.packs.builds.count == 1)
        model.setNote(model.stopIDs[0], to: "Quiet edit")
        for _ in 0..<50 { await Task.yield() }
        #expect(h.packs.builds.count == 1, "a note changes nothing the pack holds")
        _ = model.addStop(h.spot("bryce-sunset-point"), day: 1)
        #expect(await settle { h.packs.builds.count == 2 })
        #expect(h.packs.builds[1].stops.count == 7)
        model.close()
    }

    @Test func anUnopenedModelBuildsNothing() async throws {
        let h = try BuildHarness()
        h.library.trips.setPinned(h.trip, true)
        let model = h.model()
        for _ in 0..<50 { await Task.yield() }
        #expect(h.packs.builds.isEmpty && model.packState == .none)
        #expect(model.directionsRequestCount == 0, "nothing is fetched before the builder opens")
        #expect(h.conditions.requests.isEmpty)
    }
}
