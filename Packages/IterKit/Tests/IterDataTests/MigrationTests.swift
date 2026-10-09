import Foundation
import Testing
import SwiftData
import IterCore
@testable import IterData

@MainActor
@Suite struct MigrationTests {
    @Test func versionOneStoreMigratesToVersionTwo() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iter-migration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("iter.store")

        let tripID = UUID(), stopAID = UUID(), stopBID = UUID(), curatedPlaceID = UUID(), userPlaceID = UUID()
        let created = Date(timeIntervalSince1970: 1_700_000_000)
        let updated = Date(timeIntervalSince1970: 1_700_100_000)

        // 1. Write a version 1 store.
        do {
            let schema = Schema(versionedSchema: IterSchemaV1.self)
            let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = ModelContext(container)

            let curated = IterSchemaV1.PlaceRecord(id: curatedPlaceID)
            curated.curatedID = "mesa-arch"
            curated.originRaw = SpotOrigin.curated.rawValue
            curated.name = "Mesa Arch"
            curated.locality = "Moab, UT"
            curated.latitude = 38.3897
            curated.longitude = -109.8678
            curated.timeZoneIdentifier = "America/Denver"
            curated.categoryRaw = SpotCategory.landscape.rawValue
            curated.bestLightRaw = "goldenMorning,blueMorning"
            curated.facing = 90
            curated.blurb = "Sunrise glow"
            curated.notes = "Arrive early"
            curated.walkInMinutes = 15
            curated.elevationMeters = 1800
            curated.popularity = 97
            curated.tagsRaw = "arch,sunrise"
            curated.isSaved = true
            curated.createdAt = created
            curated.updatedAt = updated

            let user = IterSchemaV1.PlaceRecord(id: userPlaceID)
            user.externalID = "ext-1"
            user.name = "My Spot"
            user.locality = "Somewhere"
            user.latitude = 40.1
            user.longitude = -105.2
            user.timeZoneIdentifier = "America/Denver"
            user.notes = "Private"
            user.isSaved = false
            user.createdAt = created
            user.updatedAt = updated

            let trip = IterSchemaV1.TripRecord(id: tripID)
            trip.name = "Utah"
            trip.startDayISO = "2026-10-10"
            trip.dayCount = 3
            trip.notes = "Bring tripod"
            trip.createdAt = created
            trip.updatedAt = updated

            let a = IterSchemaV1.StopRecord(id: stopAID)
            a.dayIndex = 0
            a.sortOrder = 0
            a.sessionRaw = LightWindowKind.goldenMorning.rawValue
            a.setUpBufferMinutes = 35
            a.note = "First"
            let b = IterSchemaV1.StopRecord(id: stopBID)
            b.dayIndex = 1
            b.sortOrder = 2.5
            b.sessionRaw = LightWindowKind.goldenEvening.rawValue
            b.setUpBufferMinutes = 5
            b.note = "Second"

            for model in [curated, user] { context.insert(model) }
            context.insert(trip)
            context.insert(a)
            context.insert(b)
            a.trip = trip
            a.place = curated
            b.trip = trip
            b.place = user
            try context.save()
        }

        // 2. Open it with the current schema: the lightweight V1 -> V2 stage runs.
        let container = try IterSchema.makeContainer(url: url)
        let store = IterStore(container: container)

        let trips = store.trips()
        #expect(trips.count == 1)
        let trip = try #require(trips.first)
        #expect(trip.id == tripID)
        #expect(trip.name == "Utah")
        #expect(trip.startDayISO == "2026-10-10")
        #expect(trip.dayCount == 3)
        #expect(trip.notes == "Bring tripod")
        #expect(trip.createdAt == created)
        #expect(trip.updatedAt == updated)
        #expect(trip.folder == nil)
        #expect(trip.isPinned == false)
        #expect(trip.pinnedAt == nil)
        #expect(trip.sortOrder == 0)

        let stops = trip.orderedStops
        #expect(stops.map(\.id) == [stopAID, stopBID])
        #expect(stops[0].dayIndex == 0 && stops[0].sortOrder == 0)
        #expect(stops[0].session == .goldenMorning && stops[0].setUpBufferMinutes == 35 && stops[0].note == "First")
        #expect(stops[1].dayIndex == 1 && stops[1].sortOrder == 2.5)
        #expect(stops[1].session == .goldenEvening && stops[1].setUpBufferMinutes == 5 && stops[1].note == "Second")
        #expect(stops[0].trip?.id == tripID && stops[1].trip?.id == tripID)

        let curated = try #require(store.place(id: curatedPlaceID))
        #expect(stops[0].place?.id == curatedPlaceID)
        #expect(curated.curatedID == "mesa-arch")
        #expect(curated.origin == .curated)
        #expect(curated.externalID == nil)
        #expect(curated.name == "Mesa Arch")
        #expect(curated.locality == "Moab, UT")
        #expect(curated.latitude == 38.3897 && curated.longitude == -109.8678)
        #expect(curated.timeZoneIdentifier == "America/Denver")
        #expect(curated.category == .landscape)
        #expect(curated.bestLightRaw == "goldenMorning,blueMorning")
        #expect(curated.facing == 90)
        #expect(curated.blurb == "Sunrise glow" && curated.notes == "Arrive early")
        #expect(curated.walkInMinutes == 15 && curated.elevationMeters == 1800)
        #expect(curated.popularity == 97)
        #expect(curated.tagsRaw == "arch,sunrise")
        #expect(curated.isSaved)
        #expect(curated.createdAt == created && curated.updatedAt == updated)
        #expect(curated.folder == nil && curated.sortOrder == 0)
        #expect((curated.stops ?? []).map(\.id) == [stopAID])

        let user = try #require(store.place(id: userPlaceID))
        #expect(stops[1].place?.id == userPlaceID)
        #expect(user.curatedID == nil)
        #expect(user.externalID == "ext-1")
        #expect(user.origin == .user)
        #expect(user.name == "My Spot" && user.locality == "Somewhere")
        #expect(user.latitude == 40.1 && user.longitude == -105.2)
        #expect(user.facing == nil && user.walkInMinutes == nil && user.elevationMeters == nil)
        #expect(user.popularity == 50)
        #expect(user.notes == "Private")
        #expect(!user.isSaved)
        #expect(user.folder == nil && user.sortOrder == 0)
        #expect(store.folders(kind: .trips).isEmpty && store.folders(kind: .locations).isEmpty)

        // 3. The new features work on migrated data.
        let folder = store.createFolder(name: "Road trips", kind: .trips)
        store.moveTrips([trip], to: folder, index: nil)
        store.setPinned(trip, true)
        #expect(store.trips(in: folder).map(\.id) == [tripID])
        #expect(store.pinnedTrips().map(\.id) == [tripID])
        #expect(store.lastSaveError == nil)
    }

    @Test func versionTwoStoreMigratesToVersionThree() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iter-migration-v2-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("iter.store")
        let folderID = UUID(), placeID = UUID(), tripID = UUID()

        do {
            let schema = Schema(versionedSchema: IterSchemaV2.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            let folder = IterSchemaV2.FolderRecord(id: folderID)
            folder.name = "Utah"
            folder.kindRaw = FolderKind.locations.rawValue
            folder.sortOrder = 3
            let place = IterSchemaV2.PlaceRecord(id: placeID)
            place.name = "Mesa Arch"
            place.isSaved = true
            place.sortOrder = 2
            let trip = IterSchemaV2.TripRecord(id: tripID)
            trip.name = "Road"
            trip.isPinned = true
            trip.pinnedAt = Date(timeIntervalSince1970: 1_700_000_000)
            context.insert(folder); context.insert(place); context.insert(trip)
            place.folder = folder
            try context.save()
        }

        let store = IterStore(container: try IterSchema.makeContainer(url: url))
        let folder = try #require(store.folder(id: folderID))
        #expect(folder.name == "Utah" && folder.kind == .locations && folder.sortOrder == 3)
        #expect(!folder.isPinned && folder.pinnedAt == nil)
        let place = try #require(store.place(id: placeID))
        #expect(place.name == "Mesa Arch" && place.folder?.id == folderID && place.sortOrder == 2)
        #expect(!place.isPinned && place.pinnedAt == nil)
        let trip = try #require(store.trip(id: tripID))
        #expect(trip.isPinned && trip.pinnedAt == Date(timeIntervalSince1970: 1_700_000_000))

        store.setPinned(folder, true)
        store.setPinned(place, true)
        #expect(store.pinnedFolders(kind: .locations).map(\.id) == [folderID])
        #expect(store.pinnedPlaces().map(\.id) == [placeID])
        #expect(store.lastSaveError == nil)
    }

    @Test func currentSchemaIsVersionThree() {
        #expect(IterSchemaV3.versionIdentifier == Schema.Version(3, 0, 0))
        #expect(IterMigrationPlan.stages.count == 2)
        #expect(IterSchemaV3.models.count == 4)
    }
}
