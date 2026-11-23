import Foundation
import Testing
import IterModel
import IterPlan
import IterStore
@testable import IterFeatures

@MainActor
@Suite struct BuildEditsTests {
    /// Runs `edit` as one user action, checks it changed the trip and registered `name`, then undoes and redoes it.
    private func check(_ name: String, in h: BuildHarness, _ model: BuildModel, file: StaticString = #file, line: UInt = #line,
                       _ edit: () -> Void) throws {
        let before = try #require(model.trip)
        let beforeRows = model.rows
        h.act(edit)
        let after = try #require(model.trip)
        #expect(after != before, "\(name) changed nothing")
        #expect(model.rows != beforeRows || model.header != nil)
        #expect(h.undo.undoActionName == name)
        h.undo.undo()
        model.refreshIfChanged()
        #expect(model.trip?.stops == before.stops && model.trip?.name == before.name && model.trip?.startDay == before.startDay
                && model.trip?.dayCount == before.dayCount && model.trip?.transferTimings == before.transferTimings
                && model.trip?.isPinned == before.isPinned && model.trip?.startPlaceID == before.startPlaceID,
                "undo of \(name) did not restore the trip")
        #expect(model.rows == beforeRows, "undo of \(name) did not restore the rows")
        #expect(h.undo.redoActionName == name)
        h.undo.redo()
        model.refreshIfChanged()
        #expect(model.trip?.stops == after.stops && model.trip?.name == after.name && model.trip?.dayCount == after.dayCount
                && model.trip?.startDay == after.startDay && model.trip?.transferTimings == after.transferTimings
                && model.trip?.isPinned == after.isPinned && model.trip?.startPlaceID == after.startPlaceID,
                "redo of \(name) did not reapply")
    }

    @Test func everyStopEditIsUndoableWithANamedAction() throws {
        let h = try BuildHarness(undoable: true)
        let model = h.model()
        let first = model.stopIDs[0], second = model.stopIDs[1]
        try check("setSession", in: h, model) { model.setSession(first, to: .goldenMorning) }
        try check("setNote", in: h, model) { model.setNote(first, to: "Arrive early") }
        try check("setDriveNote", in: h, model) { model.setDriveNote(second, to: "Fuel in Page") }
        try check("setBuffer", in: h, model) { model.setBuffer(first, minutes: 35) }
        try check("setDwell", in: h, model) { model.setDwell(first, minutes: 40) }
        try check("setStopKind", in: h, model) { model.setKind(first, .waypoint) }
        try check("setFixedArrival", in: h, model) { model.setFixedArrival(first, to: LocalTime(hour: 14, minute: 30)) }
        try check("removeStop", in: h, model) { model.removeStop(second) }
    }

    @Test func addingAStopSelectsItAndUndoRemovesIt() throws {
        let h = try BuildHarness(undoable: true)
        let model = h.model()
        let place = h.spot("bryce-sunset-point")
        var added: UUID?
        try check("addStop", in: h, model) { added = model.addStop(place, day: 3, session: .goldenMorning, at: 0) }
        _ = added
        #expect(model.stopRows.count == 7)   // redo reapplied it
        let id = try #require(added)
        #expect(model.stopRows.first { $0.id == id }?.session == .goldenMorning)
        model.selectStop(id)
        #expect(model.selectedDay == 3)
        // Added at the front of day 4: numbered after the first five stops.
        let day4 = model.stopRows.filter { $0.number >= 6 }
        #expect(day4.first?.id == id)
    }

    @Test func movingWithinAndAcrossDays() throws {
        let h = try BuildHarness(undoable: true)
        let model = h.model()
        let mesa = try #require(model.stop(named: "Mesa Arch")).id
        let delicate = try #require(model.stop(named: "Delicate Arch")).id
        try check("moveStop", in: h, model) { model.moveStop(delicate, toDay: 2, index: 0) }
        #expect(model.stopRows.map(\.name).filter { ["Mesa Arch", "Delicate Arch"].contains($0) } == ["Delicate Arch", "Mesa Arch"])
        // Across days: Mesa Arch to day 1, before Dead Horse Point.
        h.undo.removeAllActions()
        try check("moveStop", in: h, model) { model.moveStop(mesa, toDay: 1, index: 1) }
        let day1 = model.rows.filter { $0.day == 1 }.compactMap { row -> String? in
            if case .stop(let s) = row.kind { s.name } else { nil }
        }
        #expect(day1 == ["Monument Valley", "Mesa Arch", "Dead Horse Point"])   // undone and redone: the check ends redone
        #expect(model.stopRows.map(\.number) == [1, 2, 3, 4, 5, 6])
    }

    @Test func aMoveAcrossDaysRenumbersAndKeepsTheSelection() throws {
        let h = try BuildHarness()
        let model = h.model()
        let mesa = try #require(model.stop(named: "Mesa Arch")).id
        model.selectStop(mesa)
        model.moveStop(mesa, toDay: 1, index: 1)
        #expect(model.selectedStopID == mesa && model.selectedDay == 1)
        #expect(model.stopRows.map(\.name) == ["Horseshoe Bend", "Monument Valley", "Mesa Arch", "Dead Horse Point", "Delicate Arch", "Goblin Valley"])
        #expect(model.stopRows.map(\.number) == [1, 2, 3, 4, 5, 6])
        #expect(model.mapContent.waypoints.map(\.name) == model.stopRows.map(\.name))
        #expect(model.dayItems.map(\.stopCount) == [1, 3, 1, 1])
    }

    @Test func reorderingADayIsUndoable() throws {
        let h = try BuildHarness(undoable: true)
        let model = h.model()
        let a = model.stopIDs[1], b = model.stopIDs[2]
        try check("reorderStops", in: h, model) { model.reorder(day: 1, to: [b, a]) }
    }

    @Test func tripLevelEditsAreUndoable() throws {
        let h = try BuildHarness(undoable: true)
        let model = h.model()
        try check("renameTrip", in: h, model) { model.rename("Utah Loop") }
        #expect(model.header?.name == "Utah Loop")
        try check("setTransferTiming", in: h, model) { model.setTransferTiming(intoDay: 2, to: .eveningBefore) }
        try check("pinTrip", in: h, model) { model.setPinned(true) }
        #expect(model.header?.isPinned == true)
        let home = h.act { h.ownPlace() }
        try check("setStartPlace", in: h, model) { model.setStartPlace(home) }
        #expect(model.startPlace?.placeID == home)
    }

    @Test func changingDatesReportsAndUndoesTheMovedStops() throws {
        let h = try BuildHarness(undoable: true)
        let model = h.model()
        #expect(model.stopsAffected(byDayCount: 2) == 3)
        #expect(model.stopsAffected(byDayCount: 4) == 0)
        var moved = -1
        try check("setDates", in: h, model) { moved = model.changeDates(startDay: h.day.adding(days: 7), dayCount: 2) }
        _ = moved
        #expect(model.header?.dayCount == 2 && model.header?.startDay == h.day.adding(days: 7))
        #expect(model.stopRows.last?.name == "Goblin Valley")
        #expect(model.dayItems.map(\.stopCount) == [1, 5])
    }

    @Test func editingADeletedStopIsANoOp() throws {
        let h = try BuildHarness()
        let model = h.model()
        let before = model.trip
        model.setNote(UUID(), to: "x")
        model.removeStop(UUID())
        model.moveStop(UUID(), toDay: 0, index: 0)
        #expect(model.trip == before)
        #expect(model.addStop(h.spot("mesa-arch"), day: 0) != nil)
    }

    @Test func aTripDeletedElsewhereClearsTheModel() throws {
        let h = try BuildHarness()
        let model = h.model()
        model.selectStop(model.stopIDs[0])
        h.library.trips.delete(h.trip)
        model.refreshIfChanged()
        #expect(model.trip == nil && model.stopIDs.isEmpty && model.selectedStopID == nil)
        #expect(model.mapContent == BuildMapContent() && model.cameraRegion == nil)
        model.rename("x")
        model.setPinned(true)   // all silent
        #expect(model.trip == nil)
    }

    // MARK: Ordering suggestion

    private func backwardsDay() throws -> (BuildHarness, BuildModel, UUID, UUID) {
        let h = try BuildHarness(template: false)
        let model = h.model()
        // A sunset stop listed before a sunrise stop on the same day.
        let a = try #require(model.addStop(h.spot("delicate-arch"), day: 0, session: .goldenEvening))
        let b = try #require(model.addStop(h.spot("mesa-arch"), day: 0, session: .goldenMorning))
        return (h, model, a, b)
    }

    @Test func aBackwardsDayOffersLightFirstOrderAndApplyingItIsUndoable() throws {
        let (h, model, a, b) = try backwardsDay()
        let suggestion = try #require(model.suggestion(forDay: 0))
        #expect(suggestion.order == [b, a])
        #expect(suggestion.issuesAfter < suggestion.issuesBefore)
        #expect(suggestion.message.hasPrefix("Putting this day in light order clears"))
        #expect(model.rows.contains { if case .suggestion = $0.kind { true } else { false } })
        #expect(model.stop(named: "Delicate Arch")?.issues.isEmpty == false || model.stop(named: "Mesa Arch")?.issues.isEmpty == false)
        h.library.undoManager = h.undo
        h.act { model.applySuggestion(day: 0) }
        #expect(model.stopRows.map(\.name) == ["Mesa Arch", "Delicate Arch"])
        #expect(model.suggestion(forDay: 0) == nil)
        #expect(h.undo.undoActionName == "reorderStops")
        h.undo.undo()
        model.refreshIfChanged()
        #expect(model.stopRows.map(\.name) == ["Delicate Arch", "Mesa Arch"])
        #expect(model.suggestion(forDay: 0) != nil)
    }

    @Test func aDismissedSuggestionStaysHiddenUntilTheOrderChanges() throws {
        let (h, model, _, b) = try backwardsDay()
        model.dismissSuggestion(day: 0)
        #expect(model.suggestion(forDay: 0) == nil)
        // The same plan after another edit that does not change the order stays dismissed.
        model.setNote(b, to: "Sunrise first")
        #expect(model.suggestion(forDay: 0) == nil)
        // A different plan (a third stop) is a new suggestion.
        _ = model.addStop(h.spot("bryce-sunset-point"), day: 0, session: .goldenMorning)
        #expect(model.suggestion(forDay: 0)?.order.count == 3)
    }
}
