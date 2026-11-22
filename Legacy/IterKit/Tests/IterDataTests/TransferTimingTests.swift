import Foundation
import Testing
import IterCore
@testable import IterData

@MainActor
@Suite struct TransferTimingStoreTests {
    @Test func defaultsToMorningAndStoresOnlyEvening() throws {
        let f = try Fixture()
        let trip = f.trip3()
        #expect(trip.transferTimingsRaw == "")
        #expect(trip.plan.transferTiming(intoDay: 1) == .morning)
        f.store.setTransferTiming(trip, intoDay: 2, to: .eveningBefore)
        f.store.setTransferTiming(trip, intoDay: 1, to: .eveningBefore)
        #expect(trip.transferTimingsRaw == "1:eveningBefore,2:eveningBefore")
        #expect(trip.plan.transferTimings == [1: .eveningBefore, 2: .eveningBefore])
        f.store.setTransferTiming(trip, intoDay: 1, to: .morning)
        #expect(trip.transferTimingsRaw == "2:eveningBefore")
        // Day 0 has no transfer into it; days past the end do not exist.
        f.store.setTransferTiming(trip, intoDay: 0, to: .eveningBefore)
        f.store.setTransferTiming(trip, intoDay: 3, to: .eveningBefore)
        #expect(trip.transferTimingsRaw == "2:eveningBefore")
    }

    @Test func garbageEntriesAreIgnored() throws {
        let f = try Fixture()
        let trip = f.trip3()
        trip.transferTimingsRaw = "1:eveningBefore,x:morning,2:sideways,,7:eveningBefore,0:eveningBefore,2:morning,junk"
        #expect(trip.transferTimings == [1: .eveningBefore])
        #expect(trip.plan.transferTimings == [1: .eveningBefore])
    }

    @Test func settingTimingAndDriveNoteIsUndoable() throws {
        let f = try Fixture(undoable: true)
        f.store.actionName = { "Name:\($0.rawValue)" }
        let trip = f.act { f.trip3() }
        let arriving = trip.orderedStops(onDay: 1)[0]
        f.act { f.store.setTransferTiming(trip, intoDay: 1, to: .eveningBefore) }
        #expect(f.undo.undoActionName == "Name:setTransferTiming")
        f.act { f.store.setDriveNote(arriving, to: "Fuel in Kanab") }
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
        let f = try Fixture()
        let trip = f.trip3()
        f.store.setTransferTiming(trip, intoDay: 1, to: .eveningBefore)
        f.store.setTransferTiming(trip, intoDay: 2, to: .eveningBefore)
        f.store.setDates(trip, startDay: f.day, dayCount: 2)
        #expect(trip.transferTimingsRaw == "1:eveningBefore")
        // Growing again does not bring it back.
        f.store.setDates(trip, startDay: f.day, dayCount: 3)
        #expect(trip.plan.transferTimings == [1: .eveningBefore])
    }

    @Test func duplicateAndImportCopyTimingsAndDriveNotes() throws {
        let f = try Fixture()
        let trip = f.trip3()
        f.store.setTransferTiming(trip, intoDay: 1, to: .eveningBefore)
        f.store.setDriveNote(trip.orderedStops(onDay: 1)[0], to: "Scenic route")
        f.store.setDriveNote(trip.orderedStops(onDay: 0)[1], to: "Coffee first")

        let copy = f.store.duplicateTrip(trip)
        #expect(copy.plan.transferTimings == [1: .eveningBefore])
        #expect(copy.orderedStops.map(\.driveNote) == ["", "Coffee first", "Scenic route", ""])

        let imported = f.store.importTrip(f.store.document(for: trip))
        #expect(imported.plan.transferTimings == [1: .eveningBefore])
        #expect(imported.orderedStops.map(\.driveNote) == ["", "Coffee first", "Scenic route", ""])
        #expect(imported.id != trip.id)
    }

    @Test func driveNoteTravelsWithTheArrivingStop() throws {
        let f = try Fixture()
        let trip = f.trip3()
        let arriving = trip.orderedStops(onDay: 0)[1]
        f.store.setDriveNote(arriving, to: "Stop for water")
        f.store.reorder(day: 0, in: trip, to: [arriving.id, trip.orderedStops(onDay: 0)[0].id])
        #expect(trip.orderedStops(onDay: 0)[0].driveNote == "Stop for water")
    }
}

@MainActor
@Suite struct TransferTimingDocumentTests {
    @Test func roundTripKeepsTimingsAndDriveNotes() throws {
        let f = try Fixture()
        let trip = f.trip3()
        f.store.setTransferTiming(trip, intoDay: 2, to: .eveningBefore)
        f.store.setDriveNote(trip.orderedStops[2], to: "Long day")
        let doc = f.store.document(for: trip, exportedAt: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(doc.formatVersion == 1)
        let data = try doc.encoded()
        let decoded = try TripDocument.decode(data)
        #expect(decoded == doc)
        #expect(decoded.trip.transferTimings == [2: .eveningBefore])
        #expect(decoded.trip.stops[2].driveNote == "Long day")
        #expect(try decoded.encoded() == data)
    }

    @Test func olderFilesImportAsMorningWithNoDriveNotes() throws {
        let f = try Fixture()
        let doc = f.store.document(for: f.trip3(), exportedAt: Date(timeIntervalSince1970: 1_800_000_000))
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
        let decoded = try TripDocument.decode(legacy)
        #expect(decoded.trip.transferTimings.isEmpty)
        #expect(decoded.trip.transferTiming(intoDay: 1) == .morning)
        #expect(decoded.trip.stops.allSatisfy { $0.driveNote == "" })
        let imported = f.store.importTrip(decoded)
        #expect(imported.transferTimingsRaw == "")
        #expect(imported.orderedStops.count == 4)
    }
}
