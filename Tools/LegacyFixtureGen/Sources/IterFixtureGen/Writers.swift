import Foundation
import SwiftData
import IterCore
@testable import IterData

// Writes a seed with the FROZEN classes of one schema version and no migration plan, as the old app did at that version.

private func fill<P: PlaceBaseF>(_ type: P.Type, _ s: PlaceSeed) -> P {
    let p = P(id: s.id)
    p.curatedID = s.curatedID; p.originRaw = s.origin.rawValue; p.externalID = s.externalID
    p.name = s.name; p.locality = s.locality; p.latitude = s.lat; p.longitude = s.lon; p.timeZoneIdentifier = s.tz
    p.categoryRaw = s.category.rawValue; p.bestLightRaw = s.bestLightRaw; p.facing = s.facing; p.blurb = s.blurb; p.notes = s.notes
    p.walkInMinutes = s.walkIn; p.elevationMeters = s.elevation; p.popularity = s.popularity; p.tagsRaw = s.tagsRaw
    p.isSaved = s.isSaved; p.createdAt = s.created; p.updatedAt = s.updated
    if let f = p as? any PlaceFolderF { f.sortOrder = s.sortOrder }
    if let n = p as? any PlacePinF { n.isPinned = s.isPinned; n.pinnedAt = s.pinnedAt }
    return p
}
private func fill<T: TripBaseF>(_ type: T.Type, _ s: TripSeed) -> T {
    let t = T(id: s.id)
    t.name = s.name; t.startDayISO = s.startDayISO; t.dayCount = s.dayCount; t.notes = s.notes
    t.createdAt = s.created; t.updatedAt = s.updated
    if let f = t as? any TripFolderF { f.sortOrder = s.sortOrder; f.isPinned = s.isPinned; f.pinnedAt = s.pinnedAt }
    return t
}
private func fill<S: StopBaseF>(_ type: S.Type, _ s: StopSeed) -> S {
    let o = S(id: s.id)
    o.dayIndex = s.dayIndex; o.sortOrder = s.sortOrder; o.sessionRaw = s.session.rawValue
    o.setUpBufferMinutes = s.buffer; o.note = s.note
    return o
}
private func fill<F: FolderBaseF>(_ type: F.Type, _ s: FolderSeed) -> F {
    let f = F(id: s.id)
    f.name = s.name; f.kindRaw = s.kind.rawValue; f.sortOrder = s.sortOrder; f.createdAt = s.created; f.updatedAt = s.updated
    if let p = f as? any FolderPinF { p.isPinned = s.isPinned; p.pinnedAt = s.pinnedAt }
    return f
}

private func container(_ schemaType: any VersionedSchema.Type, url: URL) throws -> ModelContainer {
    let schema = Schema(versionedSchema: schemaType)
    let configuration = ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)
    return try ModelContainer(for: schema, configurations: [configuration])
}

func writeV1(seed: Seed, to url: URL) throws {
    typealias P = IterSchemaV1.PlaceRecord; typealias T = IterSchemaV1.TripRecord; typealias S = IterSchemaV1.StopRecord
    let c = try container(IterSchemaV1.self, url: url)
    let ctx = ModelContext(c)
    let places = Dictionary(uniqueKeysWithValues: seed.places.map { ($0.key, fill(P.self, $0)) })
    let trips = Dictionary(uniqueKeysWithValues: seed.trips.map { ($0.key, fill(T.self, $0)) })
    for p in places.values { ctx.insert(p) }
    for t in trips.values { ctx.insert(t) }
    for s in seed.stops {
        let stop = fill(S.self, s); ctx.insert(stop)
        stop.trip = trips[s.tripKey]; stop.place = s.placeKey.flatMap { places[$0] }
    }
    try ctx.save()
}

func writeV2(seed: Seed, to url: URL) throws {
    typealias F = IterSchemaV2.FolderRecord; typealias P = IterSchemaV2.PlaceRecord
    typealias T = IterSchemaV2.TripRecord; typealias S = IterSchemaV2.StopRecord
    let c = try container(IterSchemaV2.self, url: url)
    let ctx = ModelContext(c)
    let folders = Dictionary(uniqueKeysWithValues: seed.folders.map { ($0.key, fill(F.self, $0)) })
    let places = Dictionary(uniqueKeysWithValues: seed.places.map { ($0.key, fill(P.self, $0)) })
    let trips = Dictionary(uniqueKeysWithValues: seed.trips.map { ($0.key, fill(T.self, $0)) })
    for f in folders.values { ctx.insert(f) }
    for p in places.values { ctx.insert(p) }
    for t in trips.values { ctx.insert(t) }
    for f in seed.folders { folders[f.key]!.parent = f.parentKey.flatMap { folders[$0] } }
    for p in seed.places { places[p.key]!.folder = p.folderKey.flatMap { folders[$0] } }
    for t in seed.trips { trips[t.key]!.folder = t.folderKey.flatMap { folders[$0] } }
    for s in seed.stops {
        let stop = fill(S.self, s); ctx.insert(stop)
        stop.trip = trips[s.tripKey]; stop.place = s.placeKey.flatMap { places[$0] }
    }
    try ctx.save()
}

func writeV3(seed: Seed, to url: URL) throws {
    typealias F = IterSchemaV3.FolderRecord; typealias P = IterSchemaV3.PlaceRecord
    typealias T = IterSchemaV3.TripRecord; typealias S = IterSchemaV3.StopRecord
    let c = try container(IterSchemaV3.self, url: url)
    let ctx = ModelContext(c)
    let folders = Dictionary(uniqueKeysWithValues: seed.folders.map { ($0.key, fill(F.self, $0)) })
    let places = Dictionary(uniqueKeysWithValues: seed.places.map { ($0.key, fill(P.self, $0)) })
    let trips = Dictionary(uniqueKeysWithValues: seed.trips.map { ($0.key, fill(T.self, $0)) })
    for f in folders.values { ctx.insert(f) }
    for p in places.values { ctx.insert(p) }
    for t in trips.values { ctx.insert(t) }
    for f in seed.folders { folders[f.key]!.parent = f.parentKey.flatMap { folders[$0] } }
    for p in seed.places { places[p.key]!.folder = p.folderKey.flatMap { folders[$0] } }
    for t in seed.trips { trips[t.key]!.folder = t.folderKey.flatMap { folders[$0] } }
    for s in seed.stops {
        let stop = fill(S.self, s); ctx.insert(stop)
        stop.trip = trips[s.tripKey]; stop.place = s.placeKey.flatMap { places[$0] }
    }
    try ctx.save()
}
