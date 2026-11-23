import Foundation
import Testing
import IterModel
import IterStore
@testable import IterFeatures

/// Mac to iPhone: library A is the Mac's, library B the phone's. Files travel through `SendFile` (what the Mac's Send to
/// iPhone writes) and are read back from disk like an AirDrop copy.
@MainActor
@Suite("Mac to iPhone sharing")
struct MacToPhoneTests {
    @MainActor struct Side {
        let container: AppContainer
        let model: LibraryModel
        init(seed: Bool) throws {
            container = try AppContainer.test(now: { TickingClock.shared() }, seed: seed)
            model = container.libraryModel(timeZone: TimeZone(identifier: "America/Denver")!)
        }
    }

    /// What the receiving phone sees: the bytes of the file on disk.
    private func sent(tripID: UUID, from side: Side) throws -> Data {
        let url = try #require(try SendFile.trip(tripID, from: side.model))
        #expect(url.pathExtension == "iter")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        return try Data(contentsOf: url)
    }

    private func canyon(_ s: Side) throws -> UUID { try #require(s.model.trips.first { $0.name == SampleLibrary.tripName }?.id) }

    @Test func aResentTripUpdatesInPlaceAndADeletedTripLeaves() throws {
        let mac = try Side(seed: true), phone = try Side(seed: false)
        let id = try canyon(mac)
        let older = try sent(tripID: id, from: mac)
        let first = try phone.model.importLibrary(older)
        #expect(first.tripsAdded == 1 && !first.asCopy)
        #expect(phone.model.trips.count == 1)

        // The Mac edits: rename, add a stop, change a dwell.
        mac.model.renameTrip(id, to: "Canyon Country, Revised")
        let spare = try #require(mac.model.savedPlaces.first { place in !(mac.model.trip(id: id)?.stops.contains { $0.place.id == place.id } ?? false) })
        _ = try #require(mac.model.addStop(placeID: spare.id, toTrip: id, day: 0))
        let stopRecord = try #require(mac.container.library.trips.trip(id: id)?.orderedStops.first)
        mac.container.library.trips.setDwell(stopRecord, minutes: 95)
        mac.model.refresh()
        let macTrip = try #require(mac.model.trip(id: id))

        let update = try phone.model.importLibrary(try sent(tripID: id, from: mac))
        #expect(update.tripsUpdated == 1 && update.tripsAdded == 0)
        #expect(phone.model.trips.count == 1)                       // no duplicate
        let phoneTrip = try #require(phone.model.trip(id: id))      // same id
        #expect(phoneTrip.name == "Canyon Country, Revised")
        #expect(phoneTrip.stops.map(\.id) == macTrip.stops.map(\.id))
        #expect(phoneTrip.stops.count == macTrip.stops.count)
        #expect(phoneTrip.stops.contains { $0.dwellMinutes == 95 })
        #expect(ImportText.summary(update, fileName: "Canyon Country").hasPrefix("Updated 1 trip"))

        // Sending the same file again changes nothing.
        let again = try phone.model.importLibrary(try sent(tripID: id, from: mac))
        #expect(again.isEmpty)

        // The Mac deletes the trip; the library file carries the tombstone and the phone drops it.
        mac.model.deleteTrip(id)
        let removal = try phone.model.importLibrary(try Data(contentsOf: try SendFile.library(mac.model)))
        #expect(removal.tripsRemoved == 1)
        #expect(phone.model.trip(id: id) == nil)
    }

    @Test func importAsCopyAddsASecondTripWithNewIds() throws {
        let mac = try Side(seed: true), phone = try Side(seed: false)
        let id = try canyon(mac)
        let data = try sent(tripID: id, from: mac)
        _ = try phone.model.importLibrary(data)
        let copy = try phone.model.importLibrary(data, asCopy: true)
        #expect(copy.asCopy && copy.tripsAdded == 1)
        #expect(phone.model.trips.count == 2)
        let original = try #require(phone.model.trip(id: id))
        let other = try #require(phone.model.trips.first { $0.id != id })
        let copied = try #require(phone.model.trip(id: other.id))
        #expect(copied.id != original.id)
        #expect(Set(copied.stops.map(\.id)).isDisjoint(with: original.stops.map(\.id)))
        #expect(copied.stops.count == original.stops.count)
    }

    @Test func sendLibraryIntoAnEmptyPhoneGivesEqualTripsPlacesAndFolders() throws {
        let mac = try Side(seed: true), phone = try Side(seed: false)
        let url = try SendFile.library(mac.model)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(url.lastPathComponent == "Iter Library.iter")
        let summary = try phone.model.importLibrary(try Data(contentsOf: url))
        #expect(summary.tripsAdded == mac.model.trips.count && !summary.asCopy)
        #expect(Set(phone.model.trips.map(\.id)) == Set(mac.model.trips.map(\.id)))
        for row in mac.model.trips { #expect(phone.model.trip(id: row.id) == mac.model.trip(id: row.id)) }
        #expect(Set(phone.model.savedPlaces.map(\.id)) == Set(mac.model.savedPlaces.map(\.id)))
        for row in mac.model.savedPlaces { #expect(phone.model.place(id: row.id) == mac.model.place(id: row.id)) }
        #expect(phone.model.tripFolders.map(\.id) == mac.model.tripFolders.map(\.id))
        #expect(phone.model.placeFolders.map(\.id) == mac.model.placeFolders.map(\.id))
        #expect(phone.model.tripFolders.map(\.name) == mac.model.tripFolders.map(\.name))
    }

    @Test func aV1FileImportsAsCopies() throws {
        let phone = try Side(seed: false)
        let dir = Fixtures.root.appending(path: "documents", directoryHint: .isDirectory)
        let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil).filter { $0.pathExtension == "iter" }
        #expect(!files.isEmpty)
        for url in files {
            let summary = try phone.model.importLibrary(try Data(contentsOf: url))
            #expect(summary.formatVersion == 1 && summary.asCopy && summary.tripsAdded == 1)
            #expect(ImportText.summary(summary, fileName: "x").hasSuffix("Everything came in as new copies."))
        }
        #expect(phone.model.trips.count == files.count)
    }

    @Test func importTextSentences() {
        let none = ImportSummary(formatVersion: 2, asCopy: false, tripsAdded: 0, tripsUpdated: 0, tripsRemoved: 0, placesAdded: 0, foldersAdded: 0)
        #expect(ImportText.summary(none, fileName: "Moab").contains("already in your library"))
        let some = ImportSummary(formatVersion: 2, asCopy: false, tripsAdded: 2, tripsUpdated: 1, tripsRemoved: 0, placesAdded: 1, foldersAdded: 0)
        #expect(ImportText.summary(some, fileName: "x") == "Added 2 trips, updated 1 trip, added 1 place.")
    }
}

extension TickingClock {
    /// One clock for the suite, so two libraries never write the same instant.
    static let shared = TickingClock()
}
