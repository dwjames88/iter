import Foundation
import Testing
import SwiftData
import IterCore
@testable import IterData

@MainActor
@Suite struct SchemaRulesTests {
    func tempStore() throws -> (URL, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iter-schema-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (dir, dir.appendingPathComponent("iter.store"))
    }

    /// CloudKit's rules for a SwiftData schema: no unique constraints, every attribute optional or defaulted,
    /// every relationship optional with an inverse. Checked on the live V2 schema and the frozen V1.
    @Test(arguments: [IterSchemaV1.self as any VersionedSchema.Type, IterSchemaV2.self])
    func cloudKitRulesHold(_ version: any VersionedSchema.Type) {
        let schema = Schema(versionedSchema: version)
        #expect(!schema.entities.isEmpty)
        for entity in schema.entities {
            #expect(entity.uniquenessConstraints.isEmpty, "\(entity.name) has a unique constraint")
            for attribute in entity.attributes {
                #expect(attribute.isOptional || attribute.defaultValue != nil, "\(entity.name).\(attribute.name) has no default")
            }
            for relationship in entity.relationships {
                #expect(relationship.isOptional, "\(entity.name).\(relationship.name) is required")
                #expect(relationship.inverseName != nil, "\(entity.name).\(relationship.name) has no inverse")
            }
        }
    }

    /// A bigger V1 store (twelve stops over three days with fractional orders) survives the migration in the same
    /// order, and opening the migrated store again changes nothing.
    @Test func migrationIsLosslessAndIdempotent() throws {
        let (dir, url) = try tempStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tripID = UUID()
        let stopIDs = (0..<12).map { _ in UUID() }
        let sessions: [LightWindowKind] = [.goldenMorning, .goldenEvening, .blueMorning, .blueEvening]
        do {
            let schema = Schema(versionedSchema: IterSchemaV1.self)
            let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
            let context = ModelContext(container)
            let trip = IterSchemaV1.TripRecord(id: tripID)
            trip.name = "Long"; trip.dayCount = 3; trip.startDayISO = "2026-10-10"
            context.insert(trip)
            for (i, id) in stopIDs.enumerated() {
                let place = IterSchemaV1.PlaceRecord()
                place.name = "P\(i)"; place.curatedID = i % 2 == 0 ? "slug-\(i)" : nil
                context.insert(place)
                let stop = IterSchemaV1.StopRecord(id: id)
                stop.dayIndex = i / 4
                stop.sortOrder = Double(i % 4) + (i % 3 == 0 ? 0.5 : 0)
                stop.sessionRaw = sessions[i % 4].rawValue
                stop.setUpBufferMinutes = i * 5
                stop.note = "n\(i)"
                context.insert(stop)
                stop.trip = trip
                stop.place = place
            }
            try context.save()
        }

        func snapshot() throws -> [String] {
            let store = IterStore(container: try IterSchema.makeContainer(url: url))
            let trip = try #require(store.trip(id: tripID))
            return trip.orderedStops.map {
                "\($0.id)|\($0.dayIndex)|\($0.sortOrder)|\($0.session.rawValue)|\($0.setUpBufferMinutes)|\($0.note)|\($0.place?.name ?? "-")|\($0.place?.curatedID ?? "-")"
            }
        }
        let first = try snapshot()
        #expect(first.count == 12)
        // Day then sort order; the day groups are intact.
        let days = first.compactMap { Int($0.split(separator: "|")[1]) }
        #expect(days == days.sorted())
        #expect(Set(first.map { String($0.split(separator: "|")[0]) }) == Set(stopIDs.map(\.uuidString)))
        #expect(try snapshot() == first)
        #expect(try snapshot() == first)
        let store = IterStore(container: try IterSchema.makeContainer(url: url))
        #expect((try store.context.fetchCount(FetchDescriptor<PlaceRecord>())) == 12)
        #expect((try store.context.fetchCount(FetchDescriptor<StopRecord>())) == 12)
        #expect((try store.context.fetchCount(FetchDescriptor<TripRecord>())) == 1)
        #expect((try store.context.fetchCount(FetchDescriptor<FolderRecord>())) == 0)
    }
}
