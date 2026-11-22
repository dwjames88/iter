import Foundation
import Testing
import SwiftData
import UniformTypeIdentifiers
import IterCore
@testable import IterData

@MainActor
struct Fixture {
    let store: IterStore
    let undo = UndoManager()
    let day = LocalDay(year: 2026, month: 10, day: 10)

    /// With `undoable`, every store call must be inside `act` (no run loop here to open and close groups).
    init(undoable: Bool = false) throws {
        store = IterStore(container: try IterSchema.makeContainer(inMemory: true))
        undo.groupsByEvent = false
        if undoable { store.undoManager = undo }
    }

    /// One user action = one undo group (the app gets this from the run loop).
    func act<T>(_ body: () -> T) -> T {
        undo.beginUndoGrouping()
        defer { undo.endUndoGrouping() }
        return body()
    }

    func spot(_ id: String) -> Spot { CuratedSpots.spot(id: id)! }

    func count<M: PersistentModel>(_ type: M.Type) -> Int {
        (try? store.context.fetchCount(FetchDescriptor<M>())) ?? -1
    }

    func trip3() -> TripRecord {
        let trip = store.createTrip(name: "T", startDay: day, dayCount: 3)
        store.addStop(spot("mesa-arch"), to: trip, day: 0)
        store.addStop(spot("delicate-arch"), to: trip, day: 0)
        store.addStop(spot("horseshoe-bend"), to: trip, day: 1)
        store.addStop(spot("monument-valley"), to: trip, day: 2)
        return trip
    }
}

@MainActor
@Suite struct TripTests {
    @Test func createAndFetch() throws {
        let f = try Fixture()
        let a = f.store.createTrip(name: "A", startDay: f.day, dayCount: 0)
        #expect(a.dayCount == 1)
        let b = f.store.createTrip(name: "B", startDay: f.day, dayCount: 3)
        #expect(f.store.trips().map(\.name) == ["B", "A"])
        f.store.renameTrip(a, to: "A2")
        #expect(f.store.trips().map(\.name) == ["A2", "B"])
        #expect(f.store.trip(id: b.id)?.startDay == f.day)
        f.store.deleteTrip(b)
        #expect(f.store.trip(id: b.id) == nil)
        #expect(f.store.trips().count == 1)
    }

    @Test func stopsOrderAndDefaults() throws {
        let f = try Fixture()
        let trip = f.trip3()
        let stops = trip.orderedStops
        #expect(stops.map(\.dayIndex) == [0, 0, 1, 2])
        #expect(stops[0].place?.curatedID == "mesa-arch")
        #expect(stops[0].session == .goldenMorning)
        #expect(stops[1].session == .goldenEvening)
        #expect(stops.allSatisfy { $0.setUpBufferMinutes == 20 })
        let plan = trip.plan
        #expect(plan.stops.count == 4)
        #expect(plan.stops[0].spot.id == "mesa-arch")
        // Insert at index.
        let new = f.store.addStop(f.spot("tunnel-view"), to: trip, day: 0, session: .night, at: 1)
        #expect(trip.orderedStops(onDay: 0).map(\.id).prefix(3)[1] == new.id)
        #expect(new.session == .night)
    }

    @Test func placesAreReused() throws {
        let f = try Fixture()
        let trip = f.trip3()
        f.store.addStop(f.spot("mesa-arch"), to: trip, day: 1)
        #expect(f.count(PlaceRecord.self) == 4)
        #expect(f.count(StopRecord.self) == 5)
    }

    @Test func setDatesShrinkMovesStopsToLastDay() throws {
        let f = try Fixture()
        let trip = f.trip3()
        let moved = f.store.setDates(trip, startDay: f.day.adding(days: 1), dayCount: 2)
        #expect(moved == 1)
        #expect(trip.dayCount == 2)
        #expect(trip.startDay == f.day.adding(days: 1))
        let day1 = trip.orderedStops(onDay: 1)
        #expect(day1.compactMap { $0.place?.curatedID } == ["horseshoe-bend", "monument-valley"])
        #expect(day1.map(\.sortOrder) == [0, 1])
        #expect(f.store.setDates(trip, startDay: trip.startDay, dayCount: 5) == 0)
        #expect(f.store.setDates(trip, startDay: trip.startDay, dayCount: 0) == 2)
        #expect(trip.dayCount == 1)
        #expect(trip.orderedStops.compactMap { $0.place?.curatedID } == ["mesa-arch", "delicate-arch", "horseshoe-bend", "monument-valley"])
    }

    @Test func moveStopAcrossDaysKeepsOrderConsistent() throws {
        let f = try Fixture()
        let trip = f.trip3()
        let mesa = trip.orderedStops(onDay: 0)[0]
        f.store.moveStop(mesa, toDay: 1, index: 0)
        #expect(trip.orderedStops(onDay: 0).compactMap { $0.place?.curatedID } == ["delicate-arch"])
        #expect(trip.orderedStops(onDay: 1).compactMap { $0.place?.curatedID } == ["mesa-arch", "horseshoe-bend"])
        #expect(trip.orderedStops(onDay: 0).map(\.sortOrder) == [0])
        #expect(trip.orderedStops(onDay: 1).map(\.sortOrder) == [0, 1])
        // Within a day, to the end and clamped.
        f.store.moveStop(mesa, toDay: 1, index: 99)
        #expect(trip.orderedStops(onDay: 1).compactMap { $0.place?.curatedID } == ["horseshoe-bend", "mesa-arch"])
        f.store.moveStop(mesa, toDay: 99, index: nil)
        #expect(mesa.dayIndex == 2)
        #expect(trip.orderedStops(onDay: 2).compactMap { $0.place?.curatedID } == ["monument-valley", "mesa-arch"])
    }

    @Test func reorderDay() throws {
        let f = try Fixture()
        let trip = f.trip3()
        let day0 = trip.orderedStops(onDay: 0)
        f.store.reorder(day: 0, in: trip, to: [day0[1].id, day0[0].id])
        #expect(trip.orderedStops(onDay: 0).map(\.id) == [day0[1].id, day0[0].id])
        // Unknown ids ignored, missing ones follow.
        f.store.reorder(day: 0, in: trip, to: [UUID(), day0[0].id])
        #expect(trip.orderedStops(onDay: 0).map(\.id) == [day0[0].id, day0[1].id])
    }

    @Test func stopEdits() throws {
        let f = try Fixture()
        let trip = f.trip3()
        let stop = trip.orderedStops[0]
        f.store.setSession(stop, to: .blueMorning)
        f.store.setNote(stop, to: "tripod")
        f.store.setBuffer(stop, minutes: 35)
        #expect(trip.plan.stops[0].session == .blueMorning)
        #expect(trip.plan.stops[0].note == "tripod")
        #expect(trip.plan.stops[0].setUpBufferMinutes == 35)
    }

    @Test func templatesAndDuplicate() throws {
        let f = try Fixture()
        let template = TripTemplates.all[0]
        let trip = f.store.createTrip(from: template, startDay: f.day)
        #expect(trip.name == template.defaultName)
        #expect(trip.dayCount == template.dayCount)
        #expect(trip.orderedStops.count == template.stops.count)
        let copy = f.store.duplicateTrip(trip, name: "Copy")
        #expect(copy.id != trip.id)
        #expect(copy.plan.stops.map(\.spot) == trip.plan.stops.map(\.spot))
        #expect(Set(copy.plan.stops.map(\.id)).isDisjoint(with: trip.plan.stops.map(\.id)))
        f.store.deleteTrip(trip)
        #expect(copy.orderedStops.count == template.stops.count)
        #expect(f.count(PlaceRecord.self) == Set(template.stops.map(\.spotID)).count)
    }

    @Test func seedAndReset() throws {
        let f = try Fixture()
        let trip = f.store.seedSampleTrip(startDay: f.day)
        #expect(!trip.orderedStops.isEmpty)
        #expect(!f.undo.canUndo)
        f.store.resetAllData()
        #expect(f.count(TripRecord.self) == 0 && f.count(StopRecord.self) == 0 && f.count(PlaceRecord.self) == 0)
    }
}

@MainActor
@Suite struct SavedTests {
    @Test func savingCuratedTwiceDoesNotDuplicate() throws {
        let f = try Fixture()
        let spot = f.spot("mesa-arch")
        #expect(!f.store.isSaved(spotID: spot.id))
        f.store.setSaved(spot, true)
        f.store.setSaved(spot, true)
        #expect(f.count(PlaceRecord.self) == 1)
        #expect(f.store.isSaved(spotID: "mesa-arch"))
        #expect(f.store.savedPlaces().map(\.curatedID) == ["mesa-arch"])
        // Used in a trip, then saved: still one record.
        let trip = f.store.createTrip(name: "T", startDay: f.day, dayCount: 1)
        f.store.addStop(spot, to: trip, day: 0)
        #expect(f.count(PlaceRecord.self) == 1)
        f.store.setSaved(spot, false)
        #expect(!f.store.isSaved(spotID: "mesa-arch"))
        #expect(f.count(PlaceRecord.self) == 1)
        #expect(f.store.savedPlaces().isEmpty)
    }

    @Test func unsavingUnusedPlaceRemovesIt() throws {
        let f = try Fixture()
        f.store.setSaved(f.spot("bodie"), true)
        f.store.setSaved(f.spot("bodie"), false)
        #expect(f.count(PlaceRecord.self) == 0)
    }

    @Test func userSpotsAppearInSavedPlaces() throws {
        let f = try Fixture()
        f.store.setSaved(f.spot("mesa-arch"), true)
        let mine = f.store.createUserSpot(name: "Secret pond", locality: "Near Bishop", coordinate: Coordinate(latitude: 37.3, longitude: -118.4),
                                          timeZoneIdentifier: "America/Los_Angeles", category: .landscape, bestLight: [.sunrise],
                                          notes: "Gate code 1234", walkInMinutes: 15)
        let saved = f.store.savedPlaces()
        #expect(saved.count == 2)
        #expect(saved.contains { $0.id == mine.id })
        #expect(mine.origin == .user && mine.isSaved)
        #expect(mine.spot.id == mine.id.uuidString)
        #expect(f.store.isSaved(spotID: mine.id.uuidString))
        f.store.updatePlace(mine, name: "Pond", walkInMinutes: .some(nil))
        #expect(mine.name == "Pond" && mine.walkInMinutes == nil && mine.notes == "Gate code 1234")
        // A user spot can be used in a trip through its Spot value without duplicating the record.
        let trip = f.store.createTrip(name: "T", startDay: f.day, dayCount: 1)
        f.store.addStop(mine.spot, to: trip, day: 0)
        #expect(f.count(PlaceRecord.self) == 2)
        #expect(trip.orderedStops[0].place?.id == mine.id)
    }

    @Test func appleMapsSpotsAreReusedByExternalID() throws {
        let f = try Fixture()
        let spot = Spot(id: "I63803AE6A1C5C9A1", name: "Overlook", locality: "UT", coordinate: Coordinate(latitude: 38, longitude: -110),
                        timeZoneIdentifier: "America/Denver", category: .landscape, origin: .appleMaps)
        let trip = f.store.createTrip(name: "T", startDay: f.day, dayCount: 2)
        f.store.addStop(spot, to: trip, day: 0)
        f.store.addStop(spot, to: trip, day: 1)
        #expect(f.count(PlaceRecord.self) == 1)
        #expect(trip.orderedStops[0].place?.externalID == "I63803AE6A1C5C9A1")
        f.store.removeStop(trip.orderedStops[0])
        #expect(f.count(PlaceRecord.self) == 1)
        f.store.removeStop(trip.orderedStops[0])
        #expect(f.count(PlaceRecord.self) == 0)
    }
}

@MainActor
@Suite struct UndoTests {
    @Test func deleteTripAndUndoRestoresSameIDs() throws {
        let f = try Fixture(undoable: true)
        f.store.actionName = { "Name:\($0.rawValue)" }
        let trip = f.act { f.trip3() }
        let before = trip.plan
        let tripID = trip.id
        let placeIDs = Set(trip.orderedStops.compactMap { $0.place?.id })
        f.act { f.store.deleteTrip(trip) }
        #expect(f.count(TripRecord.self) == 0 && f.count(StopRecord.self) == 0 && f.count(PlaceRecord.self) == 0)
        #expect(f.undo.undoActionName == "Name:deleteTrip")
        f.undo.undo()
        let restored = try #require(f.store.trip(id: tripID))
        #expect(restored.plan == before)
        #expect(Set(restored.orderedStops.compactMap { $0.place?.id }) == placeIDs)
        #expect(f.count(StopRecord.self) == 4 && f.count(PlaceRecord.self) == 4)
        #expect(f.undo.redoActionName == "Name:deleteTrip")
        f.undo.redo()
        #expect(f.count(TripRecord.self) == 0 && f.count(PlaceRecord.self) == 0)
        f.undo.undo()
        #expect(f.store.trip(id: tripID)?.plan == before)
    }

    @Test func removeStopUndoRedo() throws {
        let f = try Fixture(undoable: true)
        let trip = f.act { f.trip3() }
        let before = trip.plan
        let stop = trip.orderedStops(onDay: 0)[0]
        f.act { f.store.removeStop(stop) }
        #expect(trip.orderedStops.count == 3)
        #expect(trip.orderedStops(onDay: 0).map(\.sortOrder) == [0])
        f.undo.undo()
        #expect(trip.plan == before)
        f.undo.redo()
        #expect(trip.orderedStops.count == 3)
        f.undo.undo()
        #expect(trip.plan == before)
    }

    @Test func addStopUndoRemovesCreatedPlace() throws {
        let f = try Fixture(undoable: true)
        let trip = f.act { f.store.createTrip(name: "T", startDay: f.day, dayCount: 1) }
        _ = f.act { f.store.addStop(f.spot("mesa-arch"), to: trip, day: 0) }
        #expect(f.count(PlaceRecord.self) == 1)
        f.undo.undo()
        #expect(f.count(PlaceRecord.self) == 0 && trip.orderedStops.isEmpty)
        f.undo.redo()
        #expect(f.count(PlaceRecord.self) == 1 && trip.orderedStops.count == 1)
        f.undo.undo()
        f.undo.undo()
        #expect(f.count(TripRecord.self) == 0)
    }

    @Test func moveStopUndoRedo() throws {
        let f = try Fixture(undoable: true)
        let trip = f.act { f.trip3() }
        let before = trip.plan
        let mesa = trip.orderedStops(onDay: 0)[0]
        f.act { f.store.moveStop(mesa, toDay: 2, index: 0) }
        let after = trip.plan
        #expect(after != before)
        #expect(trip.orderedStops(onDay: 2).compactMap { $0.place?.curatedID } == ["mesa-arch", "monument-valley"])
        f.undo.undo()
        #expect(trip.plan == before)
        f.undo.redo()
        #expect(trip.plan == after)
    }

    @Test func renameAndDatesUndo() throws {
        let f = try Fixture(undoable: true)
        f.store.actionName = { $0.rawValue }
        let trip = f.act { f.trip3() }
        let before = trip.plan
        f.act { f.store.renameTrip(trip, to: "New") }
        #expect(trip.name == "New")
        #expect(f.undo.undoActionName == "renameTrip")
        f.undo.undo()
        #expect(trip.name == "T")
        f.undo.redo()
        #expect(trip.name == "New")
        f.undo.undo()
        f.act { _ = f.store.setDates(trip, startDay: f.day, dayCount: 1) }
        #expect(trip.dayCount == 1)
        f.undo.undo()
        #expect(trip.plan == before)
    }

    @Test func deleteUserSpotUsedByTripUndo() throws {
        let f = try Fixture(undoable: true)
        let trip = f.act { f.trip3() }
        let mine = f.act {
            f.store.createUserSpot(name: "Pond", coordinate: Coordinate(latitude: 37, longitude: -118), timeZoneIdentifier: "America/Los_Angeles")
        }
        _ = f.act { f.store.addStop(mine.spot, to: trip, day: 1, at: 0) }
        let withSpot = trip.plan
        let spotID = mine.id
        let stopIDs = trip.orderedStops.map(\.id)
        #expect(withSpot.stops.count == 5)
        f.act { f.store.deletePlace(mine) }
        #expect(f.store.place(id: spotID) == nil)
        #expect(trip.orderedStops.count == 4)
        #expect(f.store.savedPlaces().isEmpty)
        f.undo.undo()
        let back = try #require(f.store.place(id: spotID))
        #expect(back.name == "Pond" && back.isSaved && back.origin == .user)
        #expect(trip.plan == withSpot)
        #expect(trip.orderedStops.map(\.id) == stopIDs)
        #expect(back.stops?.count == 1)
        f.undo.redo()
        #expect(f.store.place(id: spotID) == nil && trip.orderedStops.count == 4)
    }

    @Test func noUndoManagerIsFine() throws {
        let store = IterStore(container: try IterSchema.makeContainer(inMemory: true))
        let trip = store.createTrip(name: "T", startDay: LocalDay(year: 2026, month: 1, day: 1), dayCount: 1)
        store.deleteTrip(trip)
        #expect(store.trips().isEmpty)
    }
}

@MainActor
@Suite struct DocumentTests {
    @Test func roundTrip() throws {
        let f = try Fixture()
        let trip = f.trip3()
        f.store.setNote(trip.orderedStops[0], to: "Arrive early")
        f.store.setBuffer(trip.orderedStops[1], minutes: 45)
        let doc = f.store.document(for: trip, exportedAt: Date(timeIntervalSince1970: 1_800_000_000.7))
        let data = try doc.encoded()
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"formatVersion\" : 1"))
        #expect(text.contains("2027-01-15T"))
        let decoded = try TripDocument.decode(data)
        #expect(decoded == doc)
        #expect(try decoded.encoded() == data)
    }

    @Test func versionAndCorruptErrors() throws {
        let f = try Fixture()
        let doc = f.store.document(for: f.trip3())
        var future = doc
        future.formatVersion = 2
        #expect(throws: TripDocument.DocumentError.unsupportedVersion(2)) { try TripDocument.decode(try future.encoded()) }
        #expect(throws: TripDocument.DocumentError.corrupt) { try TripDocument.decode(Data("nonsense".utf8)) }
        #expect(throws: TripDocument.DocumentError.corrupt) { try TripDocument.decode(Data("{\"formatVersion\":1}".utf8)) }
    }

    @Test func importTwiceGivesTwoTrips() throws {
        let f = try Fixture(undoable: true)
        let source = f.act { f.trip3() }
        let doc = f.store.document(for: source)
        let a = f.act { f.store.importTrip(doc) }
        let b = f.act { f.store.importTrip(doc) }
        #expect(f.store.trips().count == 3)
        #expect(Set([source.id, a.id, b.id]).count == 3)
        #expect(a.plan.stops.map(\.spot) == source.plan.stops.map(\.spot))
        #expect(a.plan.stops.map(\.session) == source.plan.stops.map(\.session))
        #expect(Set(a.plan.stops.map(\.id)).isDisjoint(with: b.plan.stops.map(\.id)))
        #expect(f.count(PlaceRecord.self) == 4)
        f.undo.undo()
        #expect(f.store.trips().count == 2 && f.count(PlaceRecord.self) == 4)
    }

    @Test func importInFreshStoreCreatesPlaces() throws {
        let f = try Fixture()
        let mine = f.store.createUserSpot(name: "Pond", coordinate: Coordinate(latitude: 37, longitude: -118), timeZoneIdentifier: "America/Los_Angeles")
        let trip = f.store.createTrip(name: "T", startDay: f.day, dayCount: 1)
        f.store.addStop(mine.spot, to: trip, day: 0)
        f.store.addStop(f.spot("bodie"), to: trip, day: 0)
        let doc = f.store.document(for: trip)
        let other = try Fixture()
        let imported = other.store.importTrip(doc)
        #expect(imported.plan.stops.map(\.spot.name) == ["Pond", CuratedSpots.spot(id: "bodie")!.name])
        other.store.importTrip(doc)
        #expect(other.count(PlaceRecord.self) == 2)
    }

    @Test func fileNameAndType() {
        #expect(TripDocument.suggestedFileName(forTripNamed: "Utah / Arizona: 2026?") == "Utah Arizona 2026.iter")
        #expect(TripDocument.suggestedFileName(forTripNamed: "  ") == "Trip.iter")
        #expect(TripDocument.typeIdentifier == "com.dwjames.iter.trip")
        #expect(UTType.iterTrip.identifier == "com.dwjames.iter.trip")
    }
}
