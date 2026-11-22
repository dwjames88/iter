import Foundation
import CoreData
import SwiftData
import Testing
import IterModel
@testable import IterStore

/// Each fixture store, written by the OLD module, opened by the new one and compared with what the old code read back.
@Suite struct FixtureMigrationTests {
    /// Reads the whole V5 store and compares it with `expected.json`.
    func assertMatches(_ container: ModelContainer, _ expected: ExpectedStore) throws {
        let context = ModelContext(container)
        let flattened = Set(expected.flattenedFolderIDs)

        // Folders
        let folders = try context.fetch(FetchDescriptor<FolderRecord>())
        #expect(Set(folders.map(\.id)) == Set(expected.folders.map(\.id)))
        for want in expected.folders {
            let got = try #require(folders.first { $0.id == want.id })
            #expect(got.name == want.name)
            #expect(got.kindRaw == want.kindRaw)
            #expect(got.sortOrder == want.sortOrder)
            #expect(got.createdAt.timeIntervalSinceReferenceDate == want.createdAt)
            if !flattened.contains(want.id) { #expect(got.updatedAt.timeIntervalSinceReferenceDate == want.updatedAt) }
            #expect(got.isPinned == want.isPinned)
            #expect(got.pinnedAt?.timeIntervalSinceReferenceDate == want.pinnedAt)
            #expect(got.parent?.id == want.parentID)
            #expect(Set((got.trips ?? []).map(\.id)) == Set(want.tripIDs))
            #expect(Set((got.places ?? []).map(\.id)) == Set(want.placeIDs))
        }
        // Flattened folders were stamped by this open, after the fixture was written.
        for id in flattened {
            let got = try #require(folders.first { $0.id == id })
            #expect(got.parent == nil)
            let want = try #require(expected.folders.first { $0.id == id })
            #expect(got.updatedAt.timeIntervalSinceReferenceDate > want.updatedAt || flattened.isEmpty)
        }

        // Places
        let places = try context.fetch(FetchDescriptor<PlaceRecord>())
        #expect(Set(places.map(\.id)) == Set(expected.places.map(\.id)))
        for want in expected.places {
            let got = try #require(places.first { $0.id == want.id })
            #expect(got.curatedID == want.curatedID)
            #expect(got.originRaw == want.originRaw)
            #expect(got.externalID == want.externalID)
            #expect(got.name == want.name)
            #expect(got.locality == want.locality)
            #expect(got.latitude == want.latitude)
            #expect(got.longitude == want.longitude)
            #expect(got.timeZoneIdentifier == want.timeZoneIdentifier)
            #expect(got.categoryRaw == want.categoryRaw)
            #expect(got.bestLightRaw == want.bestLightRaw)
            #expect(got.facing == want.facing)
            #expect(got.blurb == want.blurb)
            #expect(got.notes == want.notes)
            #expect(got.walkInMinutes == want.walkInMinutes)
            #expect(got.elevationMeters == want.elevationMeters)
            #expect(got.popularity == want.popularity)
            #expect(got.tagsRaw == want.tagsRaw)
            #expect(got.isSaved == want.isSaved)
            #expect(got.createdAt.timeIntervalSinceReferenceDate == want.createdAt)
            #expect(got.updatedAt.timeIntervalSinceReferenceDate == want.updatedAt)
            #expect(got.folder?.id == want.folderID)
            #expect(got.sortOrder == want.sortOrder)
            #expect(got.isPinned == want.isPinned)
            #expect(got.pinnedAt?.timeIntervalSinceReferenceDate == want.pinnedAt)
            #expect(Set((got.stops ?? []).map(\.id)) == Set(want.stopIDs))
            // V5 defaults
            #expect(got.sourcesRaw == "" && got.citationsJSON == "" && got.verificationRaw == "")
            #expect(got.discoveredAt == nil && got.horizonJSON == "")
        }

        // Trips
        let trips = try context.fetch(FetchDescriptor<TripRecord>())
        #expect(Set(trips.map(\.id)) == Set(expected.trips.map(\.id)))
        for want in expected.trips {
            let got = try #require(trips.first { $0.id == want.id })
            #expect(got.name == want.name)
            #expect(got.startDayISO == want.startDayISO)
            #expect(got.dayCount == want.dayCount)
            #expect(got.notes == want.notes)
            #expect(got.createdAt.timeIntervalSinceReferenceDate == want.createdAt)
            #expect(got.updatedAt.timeIntervalSinceReferenceDate == want.updatedAt)
            #expect(got.folder?.id == want.folderID)
            #expect(got.sortOrder == want.sortOrder)
            #expect(got.isPinned == want.isPinned)
            #expect(got.pinnedAt?.timeIntervalSinceReferenceDate == want.pinnedAt)
            #expect(got.transferTimingsRaw == want.transferTimingsRaw)
            #expect(got.startPlaceID == nil && got.timeZonePolicyRaw == "spot")
            // Stop order exactly as the old orderedStops gave it.
            #expect(got.orderedStops.map(\.id) == want.stopIDs)

            // The IterModel value, field by field, against the old TripPlan.
            let trip = got.value()
            let plan = try #require(want.plan)
            #expect(trip.id == plan.id && trip.name == plan.name && trip.startDay == plan.startDay)
            #expect(trip.dayCount == plan.dayCount && trip.notes == plan.notes)
            #expect(trip.transferTimings == plan.transferTimings)
            #expect(trip.stops.map(\.id) == plan.stops.map(\.id))
            #expect(trip.folderID == want.folderID && trip.sortOrder == want.sortOrder && trip.isPinned == want.isPinned)
            #expect(trip.startPlaceID == nil && trip.timeZonePolicy == .spot)
            for (stop, old) in zip(trip.stops, plan.stops) {
                #expect(stop.dayIndex == old.dayIndex && stop.session == old.session)
                #expect(stop.setUpBufferMinutes == old.setUpBufferMinutes)
                #expect(stop.note == old.note && stop.driveNote == old.driveNote)
                #expect(stop.dwellMinutes == 0 && stop.fixedArrival == nil && stop.kind == .light)
                #expect(stop.place.legacySpotID == old.spot.id)
                #expect(stop.place.name == old.spot.name && stop.place.locality == old.spot.locality)
                #expect(stop.place.coordinate == old.spot.coordinate)
                #expect(stop.place.bestLight == old.spot.bestLight && stop.place.tags == old.spot.tags)
                #expect(stop.place.origin == old.spot.origin && stop.place.category == old.spot.category)
            }
            // And the whole thing at once, through the v1 document's DTO.
            #expect(ITERFileV1(trip: trip, exportedAt: Date(timeIntervalSince1970: 0)).plan == plan)
        }

        // Stops (including a stop whose place is nil)
        let stops = try context.fetch(FetchDescriptor<StopRecord>())
        #expect(Set(stops.map(\.id)) == Set(expected.stops.map(\.id)))
        for want in expected.stops {
            let got = try #require(stops.first { $0.id == want.id })
            #expect(got.dayIndex == want.dayIndex)
            #expect(got.sortOrder == want.sortOrder)
            #expect(got.sessionRaw == want.sessionRaw)
            #expect(got.setUpBufferMinutes == want.setUpBufferMinutes)
            #expect(got.note == want.note)
            #expect(got.driveNote == want.driveNote)
            #expect(got.trip?.id == want.tripID)
            #expect(got.place?.id == want.placeID)
            #expect(got.dwellMinutes == 0 && got.fixedArrivalISO == "" && got.kindRaw == "light")
        }

        // The new models start empty.
        #expect(try context.fetchCount(FetchDescriptor<TripRunRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<StopVisitRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<DeletionRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<SyncPeerRecord>()) == 0)
    }

    func assertCarriesV5Metadata(_ url: URL) throws {
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(type: .sqlite, at: url, options: nil)
        let model = try #require(NSManagedObjectModel.makeManagedObjectModel(for: IterSchemaV5.models))
        let hashes = try #require(metadata[NSStoreModelVersionHashesKey] as? [String: Data])
        #expect(hashes == model.entityVersionHashesByName)
        #expect(metadata[NSStoreModelVersionIdentifiersKey] as? [String] == ["5.0.0"])
        #expect(try StoreSchemaDetector.detect(storeURL: url) == .v5)
    }

    /// The pure migration: `makeContainer(url:)` alone, with no opener around it.
    @Test(arguments: ExpectedStore.fixtureNames)
    func containerMigratesFixtureToV5(fixture: String) throws {
        let dir = try TestSupport.copyFixtureStore(fixture)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "Iter.store")
        let expected = try ExpectedStore.load(fixture)
        do {
            let container = try IterStoreSchema.makeContainer(url: url)
            // The opener flattens on every open; here the fixup is run by hand.
            let flattened = try FolderFlatten.flattenFolders(in: ModelContext(container))
            #expect(flattened == expected.flattenedFolderIDs.count)
            try assertMatches(container, expected)
            // Idempotent.
            #expect(try FolderFlatten.flattenFolders(in: ModelContext(container)) == 0)
        }
        try assertCarriesV5Metadata(url)
    }

    @Test(arguments: ExpectedStore.fixtureNames)
    func openerMigratesFixtureToV5(fixture: String) throws {
        let dir = try TestSupport.copyFixtureStore(fixture)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: "Iter.store")
        let expected = try ExpectedStore.load(fixture)
        do {
            let outcome = try StoreOpener(storeURL: url, backupsDirectory: dir.appending(path: "Backups")).open()
            #expect(outcome.activeURL == url)
            #expect(outcome.recovered == nil)
            #expect(outcome.backupFolder != nil)
            try assertMatches(outcome.container, expected)
        }
        try assertCarriesV5Metadata(url)
    }

    @Test(arguments: [("v1", StoreSchemaVersion.v1), ("v2", .v2), ("v3", .v3), ("v4-realistic", .v4)])
    func detectorReadsEachFixtureVersion(fixture: String, version: StoreSchemaVersion) throws {
        let dir = try TestSupport.copyFixtureStore(fixture)
        defer { try? FileManager.default.removeItem(at: dir) }
        let before = try TestSupport.storeHashes(dir: dir)
        let scratch = try TestSupport.makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: scratch) }
        #expect(try StoreSchemaDetector.detectOnCopy(storeURL: dir.appending(path: "Iter.store"), scratchDirectory: scratch) == version)
        // Detecting must not change the store, its -wal or its -shm, and leaves no scratch behind.
        #expect(TestSupport.names(in: scratch).isEmpty)
        #expect(try TestSupport.storeHashes(dir: dir) == before)
    }

    @Test func v4RealisticHasWhatTheOwnerStoreHas() throws {
        // Guard the fixture itself: folders, pins, transfer timings and drive notes are all present.
        let expected = try ExpectedStore.load("v4-realistic")
        #expect(expected.folders.contains { $0.isPinned })
        #expect(expected.trips.contains { $0.isPinned })
        #expect(expected.trips.contains { !$0.transferTimingsRaw.isEmpty })
        #expect(expected.stops.contains { !$0.driveNote.isEmpty })
    }
}
