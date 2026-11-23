import Foundation
import Testing
import IterModel
import IterPlan
import IterStore
@testable import IterFeatures

@MainActor
@Suite struct BuildRowsTests {
    @Test func aMultiDayTripListsDaysStopsAndTransfersInOrder() throws {
        let h = try BuildHarness()
        let model = h.model()
        // No drive is known yet, so each drive is an estimate and the rows are the layout's shape.
        let ids = model.rows.map(\.id)
        #expect(ids.filter { $0.hasPrefix("header-") } == ["header-0", "header-1", "header-2", "header-3"])
        #expect(ids.filter { $0.hasPrefix("transfer-") } == ["transfer-1", "transfer-2", "transfer-3"])
        #expect(model.stopRows.map(\.name) == ["Horseshoe Bend", "Monument Valley", "Dead Horse Point", "Mesa Arch", "Delicate Arch", "Goblin Valley"])
        // Day 2 holds a stop, a drive inside the card, a stop, and its foot.
        let day1 = model.rows.filter { $0.day == 1 }.map(\.id)
        #expect(day1.first == "transfer-1")
        #expect(day1.last == "addStop-1")
        #expect(model.driveRows.count == 5)
        #expect(model.transferRows.map(\.day) == [1, 2, 3])
        #expect(model.transferRows.allSatisfy { $0.canChooseTiming && $0.timing == .morning })
        // Every transfer after the first knows where you slept.
        #expect(model.transferRows.allSatisfy { $0.overnight != nil })
    }

    @Test func lodgingAndEveningBeforeTransfersShowTheNight() throws {
        let h = try BuildHarness()
        let model = h.model()
        let hotel = Place(name: "Page Inn", locality: "Page, AZ", coordinate: Coordinate(latitude: 36.91, longitude: -111.46),
                          timeZoneIdentifier: "America/Phoenix", category: .landscape, origin: .user)
        let id = try #require(model.addStop(hotel, day: 0, kind: .lodging))
        let lodging = try #require(model.stopRows.first { $0.id == id })
        #expect(lodging.kind == .lodging)
        #expect(lodging.timeLabel == .arrive)
        #expect(lodging.options.isEmpty == false)   // the sun still makes windows there; a lodging simply is not driven by them
        #expect(lodging.score == nil)
        model.setTransferTiming(intoDay: 1, to: .eveningBefore)
        let transfer = try #require(model.transferRows.first { $0.day == 1 })
        #expect(transfer.timing == .eveningBefore)
        #expect(transfer.drive?.transferTiming == .eveningBefore)
        let night = try #require(transfer.overnight)
        // Evening before: you sleep near the destination, Monument Valley.
        #expect(night.place == model.stop(named: "Monument Valley")?.locality || night.place == "Monument Valley")
        #expect(night.findHotelsURL?.absoluteString.hasPrefix("maps://?q=Hotels&sll=") == true)
        // The overnight sits in the foot of day 0 only when the next day has no transfer card; here it has one.
        let footer = try #require(model.rows.last { $0.day == 0 })
        if case .footer(let day, let overnight) = footer.kind { #expect(day == 0 && overnight == nil) } else { Issue.record("no footer") }
    }

    @Test func stopsAreNumberedAcrossTheTripAndMatchTheMapPins() throws {
        let h = try BuildHarness()
        let model = h.model()
        #expect(model.stopRows.map(\.number) == [1, 2, 3, 4, 5, 6])
        #expect(model.mapContent.waypoints.map(\.number) == [1, 2, 3, 4, 5, 6])
        #expect(model.mapContent.waypoints.map(\.stopID) == model.stopRows.map(\.id))
        #expect(model.stopIDs == model.stopRows.map(\.id))
    }

    @Test func headerAndDaySelectorSummarizeTheTrip() throws {
        let h = try BuildHarness()
        let model = h.model()
        let header = try #require(model.header)
        #expect(header.name == "Canyon Country")
        #expect(header.dayCount == 4 && header.stopCount == 6)
        #expect(header.startDay == h.day && header.endDay == h.day.adding(days: 3))
        #expect(header.drivingIncludesEstimate)
        #expect(header.drivingSeconds > 0)
        #expect(model.dayItems.map(\.stopCount) == [1, 2, 2, 1])
        #expect(model.dayItems.map(\.index) == [0, 1, 2, 3])
        // With no score, a day's session is its first stop's window.
        #expect(model.dayItems.map(\.primarySession) == [.goldenEvening, .goldenMorning, .goldenMorning, .goldenEvening])
        #expect(model.dayItems.allSatisfy { $0.bestScore == nil })
    }

    @Test func stopCardsCarryTheSetUpTimeWalkInAndWindows() throws {
        let h = try BuildHarness()
        let model = h.model()
        let horseshoe = try #require(model.stop(named: "Horseshoe Bend"))
        #expect(horseshoe.session == .goldenEvening && horseshoe.kind == .light)
        #expect(horseshoe.walkInMinutes == 25)
        #expect(horseshoe.setUpBufferMinutes == 20)
        let evening = try #require(horseshoe.options.first { $0.kind == .goldenEvening })
        // Set up 20 minutes before the window; park 25 minutes before that.
        #expect(horseshoe.time == evening.start.addingTimeInterval(-20 * 60))
        #expect(horseshoe.parkAt == evening.start.addingTimeInterval(-45 * 60))
        #expect(horseshoe.timeLabel == .setUp)
        // "Shoot until" is the end of the window with no dwell; a dwell shortens it.
        #expect(horseshoe.shootUntil == evening.end)
        model.setDwell(horseshoe.id, minutes: 30)
        #expect(model.stop(named: "Horseshoe Bend")?.shootUntil == evening.start.addingTimeInterval(30 * 60))
        // Monument Valley has no known walk-in: shown as unknown.
        #expect(model.stop(named: "Monument Valley")?.walkInMinutes == nil)
        // Every window the sun makes is a picker option, in time order.
        #expect(horseshoe.options.map(\.kind).contains(.goldenMorning))
        #expect(horseshoe.options == horseshoe.options.sorted { $0.start < $1.start })
    }

    @Test func theRouteMapDrawsThinnedPathsAndFramesTheSelectedDay() async throws {
        let h = try BuildHarness()
        h.routing.setPathPoints(200)
        let model = h.model()
        model.open()
        #expect(await settle { !model.isLoadingDrives })
        model.refreshIfChanged()
        let legs = model.mapContent.legs
        #expect(legs.count == 5)
        #expect(legs.allSatisfy { !$0.isEstimate })
        // 200 collinear points thin to the two ends.
        #expect(legs.allSatisfy { $0.path.count == 2 })
        let all = try #require(model.cameraRegion)
        model.selectDay(2)
        let day = try #require(model.cameraRegion)
        #expect(day != all)
        #expect(day.latitudeDelta < all.latitudeDelta)
        let mesa = model.stop(named: "Mesa Arch")!.coordinate
        #expect(day.contains(mesa))
        // The whole trip again.
        model.selectDay(nil)
        #expect(model.cameraRegion == all)
        model.close()
    }

    @Test func scoresShowPerStopAndTheDayBestWindowWins() throws {
        let h = try BuildHarness()
        let model = h.model()
        let monday = try #require(model.stop(named: "Monument Valley"))
        let dead = try #require(model.stop(named: "Dead Horse Point"))
        h.conditions.samples[.init(placeID: monday.placeID, day: h.day.adding(days: 1))] =
            ConditionsSample(tier: .complete, scores: [.goldenMorning: 61, .goldenEvening: 20])
        h.conditions.samples[.init(placeID: dead.placeID, day: h.day.adding(days: 1))] =
            ConditionsSample(tier: .complete, scores: [.goldenEvening: 83])
        model.refreshIfChanged()
        #expect(model.stop(named: "Monument Valley")?.score == 61)
        #expect(model.stop(named: "Dead Horse Point")?.score == 83)
        // Each light-window option carries its own score chip value.
        #expect(model.stop(named: "Monument Valley")?.options.first { $0.kind == .goldenEvening }?.score == 20)
        let day = model.dayItems[1]
        #expect(day.bestScore == 83)
        #expect(day.primarySession == .goldenEvening)
        guard case .dayHeader(let header) = model.rows.first(where: { $0.id == "header-1" })?.kind else { Issue.record("no header"); return }
        #expect(header.best?.score == 83 && header.best?.stopID == dead.id)
        #expect(header.sunrise != nil && header.sunset != nil)
        #expect(header.stopCount == 2)
    }

    @Test func aSelectionDoesNotRebuildAnything() throws {
        let h = try BuildHarness()
        let model = h.model()
        let recomputes = model.recomputeCount, rows = model.rowsPublishCount, maps = model.mapPublishCount
        let region = model.cameraRegion
        model.selectStop(model.stopIDs[1])
        model.selectNext()
        model.selectPrevious()
        #expect(model.recomputeCount == recomputes)
        #expect(model.rowsPublishCount == rows && model.mapPublishCount == maps)
        // Stops 2 and 3 are on day 2; only the day change moves the camera.
        #expect(model.selectedDay == 1)
        #expect(model.cameraRegion != region)
    }

    // MARK: Arrow keys

    @Test func downAndUpWalkTripOrder() {
        let ids = (0..<4).map { _ in UUID() }
        #expect(BuildModel.adjacentStop(in: ids, from: ids[1], step: 1) == ids[2])
        #expect(BuildModel.adjacentStop(in: ids, from: ids[1], step: -1) == ids[0])
        #expect(BuildModel.adjacentStop(in: ids, from: nil, step: 1) == ids[0])
        #expect(BuildModel.adjacentStop(in: ids, from: nil, step: -1) == ids[3])
        #expect(BuildModel.adjacentStop(in: ids, from: UUID(), step: 1) == ids[0])
        #expect(BuildModel.adjacentStop(in: ids, from: ids[3], step: 1) == ids[3])
        #expect(BuildModel.adjacentStop(in: ids, from: ids[0], step: -1) == ids[0])
        #expect(BuildModel.adjacentStop(in: [], from: nil, step: 1) == nil)
    }

    @Test func arrowKeysSelectAcrossDays() throws {
        let h = try BuildHarness()
        let model = h.model()
        model.selectNext()
        #expect(model.selectedStopID == model.stopIDs[0] && model.selectedDay == 0)
        model.selectNext()
        #expect(model.selectedStopID == model.stopIDs[1] && model.selectedDay == 1)
        model.selectNext(); model.selectNext(); model.selectNext(); model.selectNext()
        #expect(model.selectedStopID == model.stopIDs[5] && model.selectedDay == 3)
        model.selectNext()
        #expect(model.selectedStopID == model.stopIDs[5], "stays on the last stop")
        model.selectPrevious()
        #expect(model.selectedStopID == model.stopIDs[4] && model.selectedDay == 2)
        model.selectStop(nil)
        model.selectPrevious()
        #expect(model.selectedStopID == model.stopIDs[5], "up from nothing is the last stop")
    }

    @Test func choosingADayDropsASelectedStopFromAnotherDay() throws {
        let h = try BuildHarness()
        let model = h.model()
        model.selectStop(model.stopIDs[0])
        model.selectDay(2)
        #expect(model.selectedStopID == nil)
        model.selectDay(9)
        #expect(model.selectedDay == 2, "an unknown day is ignored")
    }

    // MARK: Export

    @Test func exportV2DecodesBackWithEverythingTheNewFormatKeeps() throws {
        let h = try BuildHarness()
        let model = h.model()
        model.setDwell(model.stopIDs[0], minutes: 45)
        model.setKind(model.stopIDs[1], .waypoint)
        let data = try model.exportDocument(format: .v2)
        guard case .v2(let file) = try ITERFile.read(data) else { Issue.record("not v2"); return }
        let trip = try #require(file.trips.first)
        #expect(trip.id == h.trip.id && trip.name == "Canyon Country")
        #expect(trip.stops.count == 6)
        #expect(trip.stops[0].dwellMinutes == 45)
        #expect(trip.stops[1].kind == .waypoint)
        #expect(model.suggestedFileName == "Canyon Country.iter")
    }

    @Test func exportForOlderIterIsFormatOne() throws {
        let h = try BuildHarness()
        let model = h.model()
        model.setNote(model.stopIDs[0], to: "Bring the wide lens")
        let data = try model.exportDocument(format: .v1ForOlderIter)
        guard case .v1(let file) = try ITERFile.read(data) else { Issue.record("not v1"); return }
        #expect(file.plan.name == "Canyon Country")
        #expect(file.plan.stops.count == 6)
        #expect(file.plan.stops[0].note == "Bring the wide lens")
        #expect(file.plan.stops.map(\.dayIndex) == [0, 1, 1, 2, 2, 3])
    }

    @Test func exportOfADeletedTripThrows() throws {
        let h = try BuildHarness()
        let model = h.model()
        h.library.trips.delete(h.trip)
        #expect(throws: BuildExportError.tripMissing) { try model.exportDocument(format: .v2) }
        model.refreshIfChanged()
        #expect(model.trip == nil && model.rows.isEmpty && model.header == nil)
    }
}
