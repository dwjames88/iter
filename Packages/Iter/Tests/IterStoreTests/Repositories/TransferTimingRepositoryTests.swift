import Foundation
import IterModel
import Testing
@testable import IterStore

@MainActor
@Suite struct TransferTimingStoreTests {
    @Test func defaultsToMorningAndStoresOnlyEvening() throws {
        let f = try StoreFixture()
        let trip = f.trip3()
        #expect(trip.transferTimingsRaw == "")
        #expect(trip.value().transferTiming(intoDay: 1) == .morning)
        f.store.trips.setTransferTiming(trip, intoDay: 2, to: .eveningBefore)
        f.store.trips.setTransferTiming(trip, intoDay: 1, to: .eveningBefore)
        #expect(trip.transferTimingsRaw == "1:eveningBefore,2:eveningBefore")
        #expect(trip.value().transferTimings == [1: .eveningBefore, 2: .eveningBefore])
        f.store.trips.setTransferTiming(trip, intoDay: 1, to: .morning)
        #expect(trip.transferTimingsRaw == "2:eveningBefore")
        // Day 0 has no transfer into it; days past the end do not exist.
        f.store.trips.setTransferTiming(trip, intoDay: 0, to: .eveningBefore)
        f.store.trips.setTransferTiming(trip, intoDay: 3, to: .eveningBefore)
        #expect(trip.transferTimingsRaw == "2:eveningBefore")
    }

    @Test func garbageEntriesAreIgnored() throws {
        let f = try StoreFixture()
        let trip = f.trip3()
        trip.transferTimingsRaw = "1:eveningBefore,x:morning,2:sideways,,7:eveningBefore,0:eveningBefore,2:morning,junk"
        #expect(trip.transferTimings == [1: .eveningBefore])
        #expect(trip.value().transferTimings == [1: .eveningBefore])
    }

    @Test func settingTimingAndDriveNoteIsUndoable() throws {
        let f = try StoreFixture(undoable: true)
        f.store.actionName = { "Name:\($0.rawValue)" }
        let trip = f.act { f.trip3() }
        let arriving = trip.orderedStops(onDay: 1)[0]
        f.act { f.store.trips.setTransferTiming(trip, intoDay: 1, to: .eveningBefore) }
        #expect(f.undo.undoActionName == "Name:setTransferTiming")
        f.act { f.store.trips.setDriveNote(arriving, to: "Fuel in Kanab") }
        #expect(f.undo.undoActionName == "Name:setDriveNote")
        #expect(arriving.driveNote == "Fuel in Kanab")
        f.undo.undo()
        #expect(arriving.driveNote == "")
        #expect(trip.transferTiming(intoDay: 1) == .eveningBefore)
        f.undo.undo()
        #expect(trip.transferTiming(intoDay: 1) == .morning)
        f.undo.redo()
        f.undo.redo()
        #expect(trip.transferTiming(intoDay: 1) == .eveningBefore)
        #expect(arriving.driveNote == "Fuel in Kanab")
    }

    @Test func shrinkingTheDatesDropsTimingsForDaysThatNoLongerExist() throws {
        let f = try StoreFixture()
        let trip = f.trip3()
        f.store.trips.setTransferTiming(trip, intoDay: 1, to: .eveningBefore)
        f.store.trips.setTransferTiming(trip, intoDay: 2, to: .eveningBefore)
        f.store.trips.setDates(trip, startDay: f.day, dayCount: 2)
        #expect(trip.transferTimingsRaw == "1:eveningBefore")
        // Growing again does not bring it back.
        f.store.trips.setDates(trip, startDay: f.day, dayCount: 3)
        #expect(trip.value().transferTimings == [1: .eveningBefore])
    }

    @Test func duplicateAndImportCopyTimingsAndDriveNotes() throws {
        let f = try StoreFixture()
        let trip = f.trip3()
        f.store.trips.setTransferTiming(trip, intoDay: 1, to: .eveningBefore)
        f.store.trips.setDriveNote(trip.orderedStops(onDay: 1)[0], to: "Scenic route")
        f.store.trips.setDriveNote(trip.orderedStops(onDay: 0)[1], to: "Coffee first")

        let copy = f.store.trips.duplicate(trip)
        #expect(copy.value().transferTimings == [1: .eveningBefore])
        #expect(copy.orderedStops.map(\.driveNote) == ["", "Coffee first", "Scenic route", ""])

        let file = try #require(f.store.exportV1(tripID: trip.id))
        let imported = try #require(f.store.importAsCopy(.v1(file)).first)
        #expect(imported.value().transferTimings == [1: .eveningBefore])
        #expect(imported.orderedStops.map(\.driveNote) == ["", "Coffee first", "Scenic route", ""])
        #expect(imported.id != trip.id)
    }

    @Test func driveNoteTravelsWithTheArrivingStop() throws {
        let f = try StoreFixture()
        let trip = f.trip3()
        let arriving = trip.orderedStops(onDay: 0)[1]
        f.store.trips.setDriveNote(arriving, to: "Stop for water")
        f.store.trips.reorder(day: 0, in: trip, to: [arriving.id, trip.orderedStops(onDay: 0)[0].id])
        #expect(trip.orderedStops(onDay: 0)[0].driveNote == "Stop for water")
    }
}

@MainActor
@Suite struct TransferTimingDocumentTests {
    @Test func roundTripKeepsTimingsAndDriveNotes() throws {
        let f = try StoreFixture()
        let trip = f.trip3()
        f.store.trips.setTransferTiming(trip, intoDay: 2, to: .eveningBefore)
        f.store.trips.setDriveNote(trip.orderedStops[2], to: "Long day")
        let doc = try #require(f.store.exportV1(tripID: trip.id))
        #expect(doc.formatVersion == 1)
        let data = try doc.encoded()
        let decoded = try ITERFileV1.decode(data)
        #expect(decoded == doc)
        #expect(decoded.plan.transferTimings == [2: .eveningBefore])
        #expect(decoded.plan.stops[2].driveNote == "Long day")
        #expect(try decoded.encoded() == data)
    }

    @Test func olderFilesImportAsMorningWithNoDriveNotes() throws {
        let f = try StoreFixture()
        let doc = try #require(f.store.exportV1(tripID: f.trip3().id))
        // Rewrite the JSON the way an older build wrote it: without the new keys.
        var object = try #require(try JSONSerialization.jsonObject(with: doc.encoded()) as? [String: Any])
        var trip = try #require(object["trip"] as? [String: Any])
        trip.removeValue(forKey: "transferTimings")
        trip["stops"] = try #require(trip["stops"] as? [[String: Any]]).map { stop -> [String: Any] in
            var stop = stop
            stop.removeValue(forKey: "driveNote")
            return stop
        }
        object["trip"] = trip
        let legacy = try JSONSerialization.data(withJSONObject: object)
        #expect(!String(decoding: legacy, as: UTF8.self).contains("driveNote"))
        let decoded = try ITERFileV1.decode(legacy)
        #expect(decoded.plan.transferTimings.isEmpty)
        #expect(decoded.plan.stops.allSatisfy { $0.driveNote == "" })
        let imported = try #require(f.store.importAsCopy(.v1(decoded)).first)
        #expect(imported.transferTimingsRaw == "")
        #expect(imported.value().transferTiming(intoDay: 1) == .morning)
        #expect(imported.orderedStops.count == 4)
    }
}
