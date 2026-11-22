import Foundation
import IterModel
import SwiftData
import Testing
@testable import IterStore

@MainActor
@Suite struct TripRepositoryTests {
    @Test func createAndFetch() throws {
        let f = try StoreFixture()
        let a = f.store.trips.create(name: "A", startDay: f.day, dayCount: 0)
        #expect(a.dayCount == 1)
        let b = f.store.trips.create(name: "B", startDay: f.day, dayCount: 3)
        #expect(f.store.trips.all().map(\.name) == ["B", "A"])
        f.store.trips.rename(a, to: "A2")
        #expect(f.store.trips.all().map(\.name) == ["A2", "B"])
        #expect(f.store.trips.trip(id: b.id)?.startDay == f.day)
        f.store.trips.delete(b)
        #expect(f.store.trips.trip(id: b.id) == nil)
        #expect(f.store.trips.all().count == 1)
    }

    @Test func stampsComeFromTheInjectedClock() throws {
        let f = try StoreFixture()
        let start = f.clock.now
        let trip = f.store.trips.create(name: "A", startDay: f.day, dayCount: 1)
        #expect(trip.createdAt >= start && trip.createdAt == trip.updatedAt)
        f.clock.advance(by: 1000)
        f.store.trips.setNotes(trip, to: "n")
        #expect(trip.updatedAt >= start.addingTimeInterval(1000))
        #expect(f.store.trips.value(id: trip.id)?.notes == "n")
    }

    @Test func stopsOrderAndDefaults() throws {
        let f = try StoreFixture()
        let trip = f.trip3()
        let stops = trip.orderedStops
        #expect(stops.map(\.dayIndex) == [0, 0, 1, 2])
        #expect(stops[0].place?.curatedID == "mesa-arch")
        #expect(stops[0].session == .goldenMorning)
        #expect(stops[1].session == .goldenEvening)
        #expect(stops.allSatisfy { $0.setUpBufferMinutes == 20 })
        let value = trip.value()
        #expect(value.stops.count == 4)
        #expect(value.stops[0].place.curatedID == "mesa-arch")
        // Insert at index.
        let new = f.store.trips.addStop(f.spot("tunnel-view"), to: trip, day: 0, session: .night, at: 1)
        #expect(trip.orderedStops(onDay: 0).map(\.id).prefix(3)[1] == new.id)
        #expect(new.session == .night)
    }

    @Test func placesAreReused() throws {
        let f = try StoreFixture()
        let trip = f.trip3()
        f.store.trips.addStop(f.spot("mesa-arch"), to: trip, day: 1)
        #expect(f.count(PlaceRecord.self) == 4)
        #expect(f.count(StopRecord.self) == 5)
    }

    @Test func setDatesShrinkMovesStopsToLastDay() throws {
        let f = try StoreFixture()
        let trip = f.trip3()
        let moved = f.store.trips.setDates(trip, startDay: f.day.adding(days: 1), dayCount: 2)
        #expect(moved == 1)
        #expect(trip.dayCount == 2)
        #expect(trip.startDay == f.day.adding(days: 1))
        let day1 = trip.orderedStops(onDay: 1)
        #expect(day1.compactMap { $0.place?.curatedID } == ["horseshoe-bend", "monument-valley"])
        #expect(day1.map(\.sortOrder) == [0, 1])
        #expect(f.store.trips.setDates(trip, startDay: trip.startDay, dayCount: 5) == 0)
        #expect(f.store.trips.setDates(trip, startDay: trip.startDay, dayCount: 0) == 2)
        #expect(trip.dayCount == 1)
        #expect(trip.orderedStops.compactMap { $0.place?.curatedID } == ["mesa-arch", "delicate-arch", "horseshoe-bend", "monument-valley"])
    }

    @Test func moveStopAcrossDaysKeepsOrderConsistent() throws {
        let f = try StoreFixture()
        let trip = f.trip3()
        let mesa = trip.orderedStops(onDay: 0)[0]
        let updatedBefore = trip.updatedAt
        f.store.trips.moveStop(mesa, toDay: 1, index: 0)
        #expect(trip.updatedAt > updatedBefore)
        #expect(trip.orderedStops(onDay: 0).compactMap { $0.place?.curatedID } == ["delicate-arch"])
        #expect(trip.orderedStops(onDay: 1).compactMap { $0.place?.curatedID } == ["mesa-arch", "horseshoe-bend"])
        #expect(trip.orderedStops(onDay: 0).map(\.sortOrder) == [0])
        #expect(trip.orderedStops(onDay: 1).map(\.sortOrder) == [0, 1])
        // Within a day, to the end and clamped.
        f.store.trips.moveStop(mesa, toDay: 1, index: 99)
        #expect(trip.orderedStops(onDay: 1).compactMap { $0.place?.curatedID } == ["horseshoe-bend", "mesa-arch"])
        f.store.trips.moveStop(mesa, toDay: 99, index: nil)
        #expect(mesa.dayIndex == 2)
        #expect(trip.orderedStops(onDay: 2).compactMap { $0.place?.curatedID } == ["monument-valley", "mesa-arch"])
    }

    @Test func reorderDay() throws {
        let f = try StoreFixture()
        let trip = f.trip3()
        let day0 = trip.orderedStops(onDay: 0)
        f.store.trips.reorder(day: 0, in: trip, to: [day0[1].id, day0[0].id])
        #expect(trip.orderedStops(onDay: 0).map(\.id) == [day0[1].id, day0[0].id])
        // Unknown ids ignored, missing ones follow.
        f.store.trips.reorder(day: 0, in: trip, to: [UUID(), day0[0].id])
        #expect(trip.orderedStops(onDay: 0).map(\.id) == [day0[0].id, day0[1].id])
    }

    @Test func stopEdits() throws {
        let f = try StoreFixture()
        let trip = f.trip3()
        let stop = trip.orderedStops[0]
        f.store.trips.setSession(stop, to: .blueMorning)
        f.store.trips.setNote(stop, to: "tripod")
        f.store.trips.setBuffer(stop, minutes: 35)
        let value = trip.value()
        #expect(value.stops[0].session == .blueMorning)
        #expect(value.stops[0].note == "tripod")
        #expect(value.stops[0].setUpBufferMinutes == 35)
        f.store.trips.setBuffer(stop, minutes: -5)
        #expect(stop.setUpBufferMinutes == 0)
    }

    @Test func templatesAndDuplicate() throws {
        let f = try StoreFixture()
        let template = TripTemplates.all[0]
        let trip = f.store.trips.create(from: template, startDay: f.day)
        #expect(trip.name == template.defaultName)
        #expect(trip.dayCount == template.dayCount)
        #expect(trip.orderedStops.count == template.stops.count)
        let copy = f.store.trips.duplicate(trip, name: "Copy")
        #expect(copy.id != trip.id)
        #expect(copy.value().stops.map(\.place) == trip.value().stops.map(\.place))
        #expect(Set(copy.value().stops.map(\.id)).isDisjoint(with: trip.value().stops.map(\.id)))
        f.store.trips.delete(trip)
        #expect(copy.orderedStops.count == template.stops.count)
        #expect(f.count(PlaceRecord.self) == Set(template.stops.map(\.spotID)).count)
    }

    @Test func v5FieldsAreWrittenAndDuplicated() throws {
        let f = try StoreFixture()
        let trip = f.trip3()
        let stop = trip.orderedStops[0]
        let home = f.ownPlace("Home")
        f.store.trips.setDwell(stop, minutes: 45)
        f.store.trips.setKind(stop, to: .lodging)
        f.store.trips.setFixedArrival(stop, to: LocalTime(hour: 18, minute: 30))
        f.store.trips.setStartPlace(trip, to: home.id)
        let value = try #require(f.store.trips.value(id: trip.id))
        #expect(value.stops[0].dwellMinutes == 45 && value.stops[0].kind == .lodging)
        #expect(value.stops[0].fixedArrival == LocalTime(hour: 18, minute: 30))
        #expect(value.startPlaceID == home.id)
        // Clearing and no-op edits.
        f.store.trips.setDwell(stop, minutes: -3)
        #expect(stop.dwellMinutes == 0)
        f.store.trips.setFixedArrival(stop, to: nil)
        #expect(stop.fixedArrivalISO == "")
        f.store.trips.setFixedArrival(stop, to: LocalTime(hour: 7, minute: 0))
        let copy = f.store.trips.duplicate(trip)
        #expect(copy.startPlaceID == home.id)
        #expect(copy.orderedStops[0].dwellMinutes == 0 && copy.orderedStops[0].kind == .lodging)
        #expect(copy.orderedStops[0].fixedArrival == LocalTime(hour: 7, minute: 0))
    }
}

@MainActor
@Suite struct SavedPlaceTests {
    @Test func savingCuratedTwiceDoesNotDuplicate() throws {
        let f = try StoreFixture()
        let spot = f.spot("mesa-arch")
        #expect(!f.store.places.isSaved(spotID: "mesa-arch"))
        f.store.places.setSaved(spot, true)
        f.store.places.setSaved(spot, true)
        #expect(f.count(PlaceRecord.self) == 1)
        #expect(f.store.places.isSaved(spotID: "mesa-arch"))
        #expect(f.store.places.isSaved(spot))
        #expect(f.store.places.savedPlaces().map(\.curatedID) == ["mesa-arch"])
        // Used in a trip, then saved: still one record.
        let trip = f.store.trips.create(name: "T", startDay: f.day, dayCount: 1)
        f.store.trips.addStop(spot, to: trip, day: 0)
        #expect(f.count(PlaceRecord.self) == 1)
        f.store.places.setSaved(spot, false)
        #expect(!f.store.places.isSaved(spotID: "mesa-arch"))
        #expect(f.count(PlaceRecord.self) == 1)
        #expect(f.store.places.savedPlaces().isEmpty)
    }

    @Test func unsavingUnusedPlaceRemovesIt() throws {
        let f = try StoreFixture()
        f.store.places.setSaved(f.spot("bodie"), true)
        f.store.places.setSaved(f.spot("bodie"), false)
        #expect(f.count(PlaceRecord.self) == 0)
        // Pruning an unused cache record is not a deletion the user made.
        #expect(f.count(DeletionRecord.self) == 0)
    }

    @Test func userSpotsAppearInSavedPlaces() throws {
        let f = try StoreFixture()
        f.store.places.setSaved(f.spot("mesa-arch"), true)
        let mine = f.store.places.createUserSpot(
            name: "Secret pond", locality: "Near Bishop", coordinate: Coordinate(latitude: 37.3, longitude: -118.4),
            timeZoneIdentifier: "America/Los_Angeles", category: .landscape, bestLight: [.sunrise],
            notes: "Gate code 1234", walkInMinutes: 15)
        let saved = f.store.places.savedPlaces()
        #expect(saved.count == 2)
        #expect(saved.contains { $0.id == mine.id })
        #expect(mine.origin == .user && mine.isSaved)
        #expect(f.store.places.isSaved(spotID: mine.id.uuidString))
        f.store.places.updatePlace(mine, name: "Pond", walkInMinutes: .some(nil))
        #expect(mine.name == "Pond" && mine.walkInMinutes == nil && mine.notes == "Gate code 1234")
        // An own place can be used in a trip through its value without duplicating the record.
        let trip = f.store.trips.create(name: "T", startDay: f.day, dayCount: 1)
        f.store.trips.addStop(mine.value(), to: trip, day: 0)
        #expect(f.count(PlaceRecord.self) == 2)
        #expect(trip.orderedStops[0].place?.id == mine.id)
    }

    @Test func appleMapsSpotsAreReusedByExternalID() throws {
        let f = try StoreFixture()
        let trip = f.store.trips.create(name: "T", startDay: f.day, dayCount: 2)
        // Two different values (different ids) that name the same MapKit place.
        f.store.trips.addStop(f.mapsPlace(), to: trip, day: 0)
        f.store.trips.addStop(f.mapsPlace(), to: trip, day: 1)
        #expect(f.count(PlaceRecord.self) == 1)
        #expect(trip.orderedStops[0].place?.externalID == "I63803AE6A1C5C9A1")
        f.store.trips.removeStop(trip.orderedStops[0])
        #expect(f.count(PlaceRecord.self) == 1)
        f.store.trips.removeStop(trip.orderedStops[0])
        #expect(f.count(PlaceRecord.self) == 0)
    }

    @Test func savingACuratedPlaceKeepsYourTextWhenItIsAddedLater() throws {
        let f = try StoreFixture()
        let spot = f.spot("mesa-arch")
        f.store.places.setSaved(spot, true)
        let record = try #require(f.store.places.savedPlaces().first)
        f.store.places.updatePlace(record, name: "My Arch", notes: "Mine")
        f.store.places.setVerification(record, to: .confirmed)
        let trip = f.store.trips.create(name: "T", startDay: f.day, dayCount: 1)
        f.store.trips.addStop(spot, to: trip, day: 0)
        #expect(record.name == "My Arch" && record.notes == "Mine" && record.verificationRaw == "confirmed")
    }
}

@MainActor
@Suite struct UndoTests {
    @Test func deleteTripAndUndoRestoresSameIDs() throws {
        let f = try StoreFixture(undoable: true)
        f.store.actionName = { "Name:\($0.rawValue)" }
        let trip = f.act { f.trip3() }
        let before = trip.value()
        let tripID = trip.id
        let placeIDs = Set(trip.orderedStops.compactMap { $0.place?.id })
        f.act { f.store.trips.delete(trip) }
        #expect(f.count(TripRecord.self) == 0 && f.count(StopRecord.self) == 0 && f.count(PlaceRecord.self) == 0)
        #expect(f.undo.undoActionName == "Name:deleteTrip")
        f.undo.undo()
        let restored = try #require(f.store.trips.trip(id: tripID))
        #expect(restored.value() == before)
        #expect(Set(restored.orderedStops.compactMap { $0.place?.id }) == placeIDs)
        #expect(f.count(StopRecord.self) == 4 && f.count(PlaceRecord.self) == 4)
        #expect(f.undo.redoActionName == "Name:deleteTrip")
        f.undo.redo()
        #expect(f.count(TripRecord.self) == 0 && f.count(PlaceRecord.self) == 0)
        f.undo.undo()
        #expect(f.store.trips.trip(id: tripID)?.value() == before)
    }

    @Test func removeStopUndoRedo() throws {
        let f = try StoreFixture(undoable: true)
        let trip = f.act { f.trip3() }
        let before = trip.value()
        let stop = trip.orderedStops(onDay: 0)[0]
        f.act { f.store.trips.removeStop(stop) }
        #expect(trip.orderedStops.count == 3)
        #expect(trip.orderedStops(onDay: 0).map(\.sortOrder) == [0])
        f.undo.undo()
        #expect(trip.value() == before)
        f.undo.redo()
        #expect(trip.orderedStops.count == 3)
        f.undo.undo()
        #expect(trip.value() == before)
    }

    @Test func addStopUndoRemovesCreatedPlace() throws {
        let f = try StoreFixture(undoable: true)
        let trip = f.act { f.store.trips.create(name: "T", startDay: f.day, dayCount: 1) }
        _ = f.act { f.store.trips.addStop(f.spot("mesa-arch"), to: trip, day: 0) }
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
        let f = try StoreFixture(undoable: true)
        let trip = f.act { f.trip3() }
        let before = trip.value()
        let mesa = trip.orderedStops(onDay: 0)[0]
        f.act { f.store.trips.moveStop(mesa, toDay: 2, index: 0) }
        let after = trip.value()
        #expect(after != before)
        #expect(trip.orderedStops(onDay: 2).compactMap { $0.place?.curatedID } == ["mesa-arch", "monument-valley"])
        f.undo.undo()
        #expect(trip.value() == before)
        f.undo.redo()
        #expect(trip.value() == after)
    }

    @Test func renameAndDatesUndo() throws {
        let f = try StoreFixture(undoable: true)
        f.store.actionName = { $0.rawValue }
        let trip = f.act { f.trip3() }
        let before = trip.value()
        f.act { f.store.trips.rename(trip, to: "New") }
        #expect(trip.name == "New")
        #expect(f.undo.undoActionName == "renameTrip")
        f.undo.undo()
        #expect(trip.name == "T")
        f.undo.redo()
        #expect(trip.name == "New")
        f.undo.undo()
        f.act { _ = f.store.trips.setDates(trip, startDay: f.day, dayCount: 1) }
        #expect(trip.dayCount == 1)
        f.undo.undo()
        #expect(trip.value() == before)
    }

    @Test func deleteUserSpotUsedByTripUndo() throws {
        let f = try StoreFixture(undoable: true)
        let trip = f.act { f.trip3() }
        let mine = f.act {
            f.store.places.createUserSpot(name: "Pond", coordinate: Coordinate(latitude: 37, longitude: -118),
                                          timeZoneIdentifier: "America/Los_Angeles")
        }
        _ = f.act { f.store.trips.addStop(mine.value(), to: trip, day: 1, at: 0) }
        let withSpot = trip.value()
        let spotID = mine.id
        let stopIDs = trip.orderedStops.map(\.id)
        #expect(withSpot.stops.count == 5)
        f.act { f.store.places.deletePlace(mine) }
        #expect(f.store.places.place(id: spotID) == nil)
        #expect(trip.orderedStops.count == 4)
        #expect(f.store.places.savedPlaces().isEmpty)
        f.undo.undo()
        let back = try #require(f.store.places.place(id: spotID))
        #expect(back.name == "Pond" && back.isSaved && back.origin == .user)
        #expect(trip.value() == withSpot)
        #expect(trip.orderedStops.map(\.id) == stopIDs)
        #expect(back.stops?.count == 1)
        f.undo.redo()
        #expect(f.store.places.place(id: spotID) == nil && trip.orderedStops.count == 4)
    }

    @Test func noUndoManagerIsFine() throws {
        let store = LibraryStore(container: try IterStoreSchema.makeInMemoryContainer())
        let trip = store.trips.create(name: "T", startDay: LocalDay(year: 2026, month: 1, day: 1), dayCount: 1)
        store.trips.delete(trip)
        #expect(store.trips.all().isEmpty)
    }

    @Test func undoAndRedoKeepEveryV5Field() throws {
        let f = try StoreFixture(undoable: true)
        let trip = f.act { f.trip3() }
        let home = f.act { f.ownPlace("Home") }
        let stop = trip.orderedStops[1]
        f.act { f.store.trips.setDwell(stop, minutes: 50) }
        f.act { f.store.trips.setKind(stop, to: .waypoint) }
        f.act { f.store.trips.setFixedArrival(stop, to: LocalTime(hour: 6, minute: 15)) }
        f.act { f.store.trips.setStartPlace(trip, to: home.id) }
        f.act { f.store.places.setSources(home, to: ["osm", "wikidata"]) }
        f.act { f.store.places.setVerification(home, to: .singleSource, discoveredAt: Date(timeIntervalSince1970: 1_700_000_000)) }
        f.act { f.store.places.setHorizon(home, to: HorizonProfile(azimuthStepDegrees: 90, elevationsDegrees: [1, 2, 3, 4])) }
        let withEverything = trip.value()
        let homeWith = home.value()
        #expect(homeWith.sources.count == 2 && homeWith.verification == .singleSource && homeWith.horizon != nil)

        // Deleting the trip and the place, then undoing, brings every V5 field back.
        f.act { f.store.trips.delete(trip) }
        f.act { f.store.places.deletePlace(home) }
        f.undo.undo()
        f.undo.undo()
        let restoredTrip = try #require(f.store.trips.trip(id: trip.id))
        #expect(restoredTrip.value() == withEverything)
        #expect(try #require(f.store.places.place(id: home.id)).value() == homeWith)

        // Undoing each edit in turn clears its field; redo puts it back. (The restored records are new objects.)
        let home2 = try #require(f.store.places.place(id: home.id))
        f.undo.undo()   // horizon
        #expect(home2.horizonJSON == "")
        f.undo.redo()
        #expect(home2.value().horizon == homeWith.horizon)
        f.undo.undo(); f.undo.undo(); f.undo.undo()   // horizon, verification, sources
        #expect(home2.sourcesRaw == "" && home2.verificationRaw == "" && home2.discoveredAt == nil)
        f.undo.undo()   // start place
        #expect(restoredTrip.startPlaceID == nil)
        f.undo.undo(); f.undo.undo(); f.undo.undo()   // fixed arrival, kind, dwell
        let plain = restoredTrip.orderedStops[1]
        #expect(plain.dwellMinutes == 0 && plain.kind == .light && plain.fixedArrivalISO == "")
        f.undo.redo(); f.undo.redo(); f.undo.redo(); f.undo.redo()
        #expect(plain.dwellMinutes == 50 && plain.kind == .waypoint && plain.fixedArrival == LocalTime(hour: 6, minute: 15))
        #expect(restoredTrip.startPlaceID == home.id)
    }

    @Test func deletingWritesATombstoneAndUndoRemovesIt() throws {
        let f = try StoreFixture(undoable: true)
        let trip = f.act { f.trip3() }
        let folder = f.act { f.store.folders.create(name: "F", kind: .trips) }
        let mine = f.act { f.ownPlace("Pond") }
        let deletedAt = f.clock.now

        f.act { f.store.trips.delete(trip) }
        let tombstone = try #require(f.store.deletions.tombstone(.trip, id: trip.id))
        #expect(tombstone.deletedAt >= deletedAt)
        #expect(f.count(DeletionRecord.self) == 1)
        f.undo.undo()
        #expect(f.store.deletions.all().isEmpty)
        f.undo.redo()
        #expect(f.store.deletions.tombstone(.trip, id: trip.id) != nil)
        f.undo.undo()

        f.act { f.store.places.deletePlace(mine) }
        #expect(f.store.deletions.tombstone(.place, id: mine.id) != nil)
        f.act { f.store.folders.delete(folder) }
        #expect(f.store.deletions.tombstone(.folder, id: folder.id) != nil)
        #expect(f.store.deletions.all().count == 2)
        f.undo.undo()
        #expect(f.store.deletions.all().map(\.entity) == [.place])
        f.undo.undo()
        #expect(f.store.deletions.all().isEmpty)
    }

    @Test func pruneRemovesOnlyTombstonesPastRetention() throws {
        let f = try StoreFixture()
        let old = f.ownTrip("old")
        f.store.trips.delete(old)
        let oldDeletedAt = try #require(f.store.deletions.all().first).deletedAt
        f.clock.advance(by: 91 * 24 * 3600)
        let recent = f.ownTrip("recent")
        f.store.trips.delete(recent)
        #expect(f.store.deletions.all().count == 2)
        #expect(f.store.deletions.prune(olderThan: DeletionRepository.retention) == 1)
        #expect(f.store.deletions.all().map(\.id) == [recent.id])
        #expect(f.store.deletions.all().allSatisfy { $0.deletedAt > oldDeletedAt })
        #expect(f.store.deletions.prune() == 0)
        #expect(DeletionRepository.retention == 90 * 24 * 3600)
    }
}
