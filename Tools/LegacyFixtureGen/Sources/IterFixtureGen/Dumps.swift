import Foundation
import SwiftData
import IterCore
@testable import IterData

// Reads a store back into the dump structure. V1-V3 are read with the frozen classes (no migration plan); the live
// reader works on the V4 records an old `IterStore` hands out.

private func header(_ fixture: String, _ version: String, _ generator: [String]) -> [String: J] {
    ["fixture": .string(fixture), "writtenSchemaVersion": .string(version), "generator": .array(generator.map { .string($0) })]
}

func dumpV1(url: URL, fixture: String, generator: [String]) throws -> J {
    typealias P = IterSchemaV1.PlaceRecord; typealias T = IterSchemaV1.TripRecord; typealias S = IterSchemaV1.StopRecord
    let schema = Schema(versionedSchema: IterSchemaV1.self)
    let c = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
    let ctx = ModelContext(c)
    let places = try ctx.fetch(FetchDescriptor<P>()), trips = try ctx.fetch(FetchDescriptor<T>()), stops = try ctx.fetch(FetchDescriptor<S>())
    var o = header(fixture, "1.0.0", generator)
    o["folders"] = .array([])
    o["places"] = sortedByID(places.map { placeScalars($0).merging(["stopIDs": .sortedUUIDs(($0.stops ?? []).map(\.id))]) { a, _ in a } })
    o["trips"] = sortedByID(trips.map { tripScalars($0).merging(["stopIDs": .uuids(orderedStopIDs($0.stops ?? []))]) { a, _ in a } })
    o["stops"] = sortedByID(stops.map { stopScalars($0).merging(["tripID": .uuid($0.trip?.id), "placeID": .uuid($0.place?.id)]) { a, _ in a } })
    return .object(o)
}

func dumpV2(url: URL, fixture: String, generator: [String]) throws -> J {
    typealias F = IterSchemaV2.FolderRecord; typealias P = IterSchemaV2.PlaceRecord
    typealias T = IterSchemaV2.TripRecord; typealias S = IterSchemaV2.StopRecord
    let schema = Schema(versionedSchema: IterSchemaV2.self)
    let c = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
    let ctx = ModelContext(c)
    let folders = try ctx.fetch(FetchDescriptor<F>()), places = try ctx.fetch(FetchDescriptor<P>())
    let trips = try ctx.fetch(FetchDescriptor<T>()), stops = try ctx.fetch(FetchDescriptor<S>())
    var o = header(fixture, "2.0.0", generator)
    o["folders"] = sortedByID(folders.map { folderScalars($0).merging(["parentID": .uuid($0.parent?.id),
        "tripIDs": .sortedUUIDs(($0.trips ?? []).map(\.id)), "placeIDs": .sortedUUIDs(($0.places ?? []).map(\.id))]) { a, _ in a } })
    o["places"] = sortedByID(places.map { placeScalars($0).merging(["folderID": .uuid($0.folder?.id), "stopIDs": .sortedUUIDs(($0.stops ?? []).map(\.id))]) { a, _ in a } })
    o["trips"] = sortedByID(trips.map { tripScalars($0).merging(["folderID": .uuid($0.folder?.id), "stopIDs": .uuids(orderedStopIDs($0.stops ?? []))]) { a, _ in a } })
    o["stops"] = sortedByID(stops.map { stopScalars($0).merging(["tripID": .uuid($0.trip?.id), "placeID": .uuid($0.place?.id)]) { a, _ in a } })
    return .object(o)
}

func dumpV3(url: URL, fixture: String, generator: [String]) throws -> J {
    typealias F = IterSchemaV3.FolderRecord; typealias P = IterSchemaV3.PlaceRecord
    typealias T = IterSchemaV3.TripRecord; typealias S = IterSchemaV3.StopRecord
    let schema = Schema(versionedSchema: IterSchemaV3.self)
    let c = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
    let ctx = ModelContext(c)
    let folders = try ctx.fetch(FetchDescriptor<F>()), places = try ctx.fetch(FetchDescriptor<P>())
    let trips = try ctx.fetch(FetchDescriptor<T>()), stops = try ctx.fetch(FetchDescriptor<S>())
    var o = header(fixture, "3.0.0", generator)
    o["folders"] = sortedByID(folders.map { folderScalars($0).merging(["parentID": .uuid($0.parent?.id),
        "tripIDs": .sortedUUIDs(($0.trips ?? []).map(\.id)), "placeIDs": .sortedUUIDs(($0.places ?? []).map(\.id))]) { a, _ in a } })
    o["places"] = sortedByID(places.map { placeScalars($0).merging(["folderID": .uuid($0.folder?.id), "stopIDs": .sortedUUIDs(($0.stops ?? []).map(\.id))]) { a, _ in a } })
    o["trips"] = sortedByID(trips.map { tripScalars($0).merging(["folderID": .uuid($0.folder?.id), "stopIDs": .uuids(orderedStopIDs($0.stops ?? []))]) { a, _ in a } })
    o["stops"] = sortedByID(stops.map { stopScalars($0).merging(["tripID": .uuid($0.trip?.id), "placeID": .uuid($0.place?.id)]) { a, _ in a } })
    return .object(o)
}

/// The plan as `TripDocument.encoded()` encodes it (sorted keys, ISO-8601 dates), as a JSON tree.
func planJSON(_ plan: TripPlan) throws -> J {
    let e = JSONEncoder()
    e.outputFormatting = [.prettyPrinted, .sortedKeys]
    e.dateEncodingStrategy = .iso8601
    return try JSONDecoder().decode(J.self, from: e.encode(plan))
}

/// Dump of an old `IterStore` over a store (migrated to V4, folders flattened).
@MainActor
func dumpLive(store: IterStore, fixture: String, writtenVersion: String, generator: [String]) throws -> J {
    let ctx = store.context
    let folders = try ctx.fetch(FetchDescriptor<FolderRecord>()), places = try ctx.fetch(FetchDescriptor<PlaceRecord>())
    let trips = try ctx.fetch(FetchDescriptor<TripRecord>()), stops = try ctx.fetch(FetchDescriptor<StopRecord>())
    var o = header(fixture, writtenVersion, generator)
    o["folders"] = sortedByID(folders.map { folderScalars($0).merging(["parentID": .uuid($0.parent?.id),
        "tripIDs": .sortedUUIDs(($0.trips ?? []).map(\.id)), "placeIDs": .sortedUUIDs(($0.places ?? []).map(\.id))]) { a, _ in a } })
    o["places"] = sortedByID(places.map { placeScalars($0).merging(["folderID": .uuid($0.folder?.id), "stopIDs": .sortedUUIDs(($0.stops ?? []).map(\.id))]) { a, _ in a } })
    var tripObjects: [[String: J]] = []
    for t in trips {
        tripObjects.append(tripScalars(t).merging(["folderID": .uuid(t.folder?.id), "stopIDs": .uuids(t.orderedStops.map(\.id)),
                                                   "plan": try planJSON(t.plan)]) { a, _ in a })
    }
    o["trips"] = sortedByID(tripObjects)
    o["stops"] = sortedByID(stops.map { stopScalars($0).merging(["tripID": .uuid($0.trip?.id), "placeID": .uuid($0.place?.id)]) { a, _ in a } })
    return .object(o)
}
