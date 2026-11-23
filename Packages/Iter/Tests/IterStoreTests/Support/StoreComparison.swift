import Foundation
import SwiftData
import IterModel
@testable import IterStore

/// One field that differs between the old code's dump and the new store.
struct StoreDifference: Codable, Equatable, Sendable, CustomStringConvertible {
    var entity: String
    var id: String
    /// The trip's name for a trip (and for its stops and plan), so a reader can find it without the id.
    var label: String?
    var field: String
    var before: String
    var after: String

    var description: String {
        "\(entity) \(id)\(label.map { " (\($0))" } ?? ""): \(field) \(before) -> \(after)"
    }
}

/// Collects the field-by-field result. Free-text fields (`notes`, `blurb`, `note`, `driveNote`) are never printed: a
/// difference there says only "differs (len a -> b)", so a report made from a private store cannot leak what was typed.
struct ComparisonRecorder: Sendable {
    static let redactedFields: Set<String> = ["notes", "blurb", "note", "driveNote"]

    var differences: [StoreDifference] = []
    /// Fields deliberately not compared (and why), once each.
    var skipped: [String] = []
    var checkCount = 0

    mutating func skip(_ note: String) { if !skipped.contains(note) { skipped.append(note) } }

    /// The last path component of a field path, without an index: "plan.stops[2].note" -> "note".
    static func leaf(_ field: String) -> String {
        let last = field.split(separator: ".").last.map(String.init) ?? field
        return last.split(separator: "[").first.map(String.init) ?? last
    }

    mutating func record(_ entity: String, _ id: String, _ label: String?, _ field: String, before: String, after: String) {
        let hide = Self.redactedFields.contains(Self.leaf(field))
        differences.append(StoreDifference(
            entity: entity, id: id, label: label, field: field,
            before: hide ? "differs (len \(before.count) \u{2192} \(after.count))" : before,
            after: hide ? "(text not shown)" : after))
    }

    mutating func check<T: Equatable>(_ entity: String, _ id: UUID, label: String? = nil, _ field: String, expected: T, actual: T) {
        checkCount += 1
        guard expected != actual else { return }
        record(entity, id.uuidString, label, field, before: Self.text(expected), after: Self.text(actual))
    }

    static func text<T>(_ value: T) -> String {
        if let o = value as? any OptionalProtocolBox { return o.isNil ? "nil" : String(describing: o.wrappedAny) }
        return String(describing: value)
    }
}

/// Lets `ComparisonRecorder.text` print an Optional without "Optional(...)".
private protocol OptionalProtocolBox { var isNil: Bool { get }; var wrappedAny: Any { get } }
extension Optional: OptionalProtocolBox {
    fileprivate var isNil: Bool { self == nil }
    fileprivate var wrappedAny: Any { self! }
}

struct ComparisonResult: Sendable {
    var differences: [StoreDifference]
    var skipped: [String]
    var checkCount: Int

    var summary: String { differences.map(\.description).joined(separator: "\n") }
}

/// Compares a V5 store with an old-code dump and returns the differences instead of asserting, so both the fixture tests
/// (`#expect(result.differences.isEmpty)`) and the real-store dry run (a report) use one set of checks.
enum StoreComparison {
    /// The v1 document encoder's view of a plan, as a JSON tree (for field-level plan differences).
    static func planTree(_ plan: ITERFileV1.TripDTO) throws -> Any {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try JSONSerialization.jsonObject(with: encoder.encode(plan))
    }

    /// Field-level differences between two plans (by encoded v1 JSON). `path` prefixes each field.
    static func planDifferences(expected: ITERFileV1.TripDTO, actual: ITERFileV1.TripDTO, entity: String, id: UUID, label: String?,
                                path: String = "plan", into rec: inout ComparisonRecorder) throws {
        rec.checkCount += 1
        guard expected != actual else { return }
        func walk(_ a: Any?, _ b: Any?, _ path: String) {
            switch (a, b) {
            case let (x as [String: Any], y as [String: Any]):
                for key in Set(x.keys).union(y.keys).sorted() { walk(x[key], y[key], "\(path).\(key)") }
            case let (x as [Any], y as [Any]):
                if x.count != y.count { rec.record(entity, id.uuidString, label, "\(path).count", before: "\(x.count)", after: "\(y.count)") }
                for i in 0..<min(x.count, y.count) { walk(x[i], y[i], "\(path)[\(i)]") }
            case (nil, nil): break
            default:
                let sa = a.map { "\($0)" } ?? "(absent)", sb = b.map { "\($0)" } ?? "(absent)"
                if sa != sb { rec.record(entity, id.uuidString, label, path, before: sa, after: sb) }
            }
        }
        walk(try planTree(expected), try planTree(actual), path)
        if !rec.differences.contains(where: { $0.entity == entity && $0.id == id.uuidString && $0.field.hasPrefix(path) }) {
            rec.record(entity, id.uuidString, label, path, before: "(equal as JSON)", after: "(not equal as values)")
        }
    }

    /// Every folder, place, trip and stop field of the V5 store in `context` against `expected`, ordered stop ids, each
    /// trip's plan through the carried v1 encoder, and the V5 columns at their defaults.
    static func compare(context: ModelContext, expected: ExpectedStore) throws -> ComparisonResult {
        var rec = ComparisonRecorder()
        let flattened = Set(expected.flattenedFolderIDs)
        let tripNames = Dictionary(expected.trips.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        func t(_ d: Date) -> Double { d.timeIntervalSinceReferenceDate }

        // Folders
        let folders = try context.fetch(FetchDescriptor<FolderRecord>())
        rec.check("folder", UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, "ids", expected: Set(expected.folders.map(\.id)), actual: Set(folders.map(\.id)))
        for want in expected.folders {
            guard let got = folders.first(where: { $0.id == want.id }) else { continue }
            let e = "folder", i = want.id
            rec.check(e, i, "name", expected: want.name, actual: got.name)
            rec.check(e, i, "kindRaw", expected: want.kindRaw, actual: got.kindRaw)
            rec.check(e, i, "sortOrder", expected: want.sortOrder, actual: got.sortOrder)
            rec.check(e, i, "createdAt", expected: want.createdAt, actual: t(got.createdAt))
            if flattened.contains(want.id) {
                rec.skip("folder.updatedAt of flattened folders (the open restamps them): \(flattened.count) folder(s)")
                rec.check(e, i, "parent (flattened)", expected: UUID?.none, actual: got.parent?.id)
            } else {
                rec.check(e, i, "updatedAt", expected: want.updatedAt, actual: t(got.updatedAt))
                rec.check(e, i, "parentID", expected: want.parentID, actual: got.parent?.id)
            }
            rec.check(e, i, "isPinned", expected: want.isPinned, actual: got.isPinned)
            rec.check(e, i, "pinnedAt", expected: want.pinnedAt, actual: got.pinnedAt.map(t))
            rec.check(e, i, "tripIDs", expected: Set(want.tripIDs), actual: Set((got.trips ?? []).map(\.id)))
            rec.check(e, i, "placeIDs", expected: Set(want.placeIDs), actual: Set((got.places ?? []).map(\.id)))
        }

        // Places
        let places = try context.fetch(FetchDescriptor<PlaceRecord>())
        rec.check("place", UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, "ids", expected: Set(expected.places.map(\.id)), actual: Set(places.map(\.id)))
        for want in expected.places {
            guard let got = places.first(where: { $0.id == want.id }) else { continue }
            let e = "place", i = want.id
            rec.check(e, i, "curatedID", expected: want.curatedID, actual: got.curatedID)
            rec.check(e, i, "originRaw", expected: want.originRaw, actual: got.originRaw)
            rec.check(e, i, "externalID", expected: want.externalID, actual: got.externalID)
            rec.check(e, i, "name", expected: want.name, actual: got.name)
            rec.check(e, i, "locality", expected: want.locality, actual: got.locality)
            rec.check(e, i, "latitude", expected: want.latitude, actual: got.latitude)
            rec.check(e, i, "longitude", expected: want.longitude, actual: got.longitude)
            rec.check(e, i, "timeZoneIdentifier", expected: want.timeZoneIdentifier, actual: got.timeZoneIdentifier)
            rec.check(e, i, "categoryRaw", expected: want.categoryRaw, actual: got.categoryRaw)
            rec.check(e, i, "bestLightRaw", expected: want.bestLightRaw, actual: got.bestLightRaw)
            rec.check(e, i, "facing", expected: want.facing, actual: got.facing)
            rec.check(e, i, "blurb", expected: want.blurb, actual: got.blurb)
            rec.check(e, i, "notes", expected: want.notes, actual: got.notes)
            rec.check(e, i, "walkInMinutes", expected: want.walkInMinutes, actual: got.walkInMinutes)
            rec.check(e, i, "elevationMeters", expected: want.elevationMeters, actual: got.elevationMeters)
            rec.check(e, i, "popularity", expected: want.popularity, actual: got.popularity)
            rec.check(e, i, "tagsRaw", expected: want.tagsRaw, actual: got.tagsRaw)
            rec.check(e, i, "isSaved", expected: want.isSaved, actual: got.isSaved)
            rec.check(e, i, "createdAt", expected: want.createdAt, actual: t(got.createdAt))
            rec.check(e, i, "updatedAt", expected: want.updatedAt, actual: t(got.updatedAt))
            rec.check(e, i, "folderID", expected: want.folderID, actual: got.folder?.id)
            rec.check(e, i, "sortOrder", expected: want.sortOrder, actual: got.sortOrder)
            rec.check(e, i, "isPinned", expected: want.isPinned, actual: got.isPinned)
            rec.check(e, i, "pinnedAt", expected: want.pinnedAt, actual: got.pinnedAt.map(t))
            rec.check(e, i, "stopIDs", expected: Set(want.stopIDs), actual: Set((got.stops ?? []).map(\.id)))
            // V5 defaults
            let d = "v5Defaults"
            rec.check(d, i, label: "place", "sourcesRaw/citationsJSON/verificationRaw", expected: ["", "", ""], actual: [got.sourcesRaw, got.citationsJSON, got.verificationRaw])
            rec.check(d, i, label: "place", "discoveredAt", expected: Date?.none, actual: got.discoveredAt)
            rec.check(d, i, label: "place", "horizonJSON", expected: "", actual: got.horizonJSON)
        }

        // Trips
        let trips = try context.fetch(FetchDescriptor<TripRecord>())
        rec.check("trip", UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, "ids", expected: Set(expected.trips.map(\.id)), actual: Set(trips.map(\.id)))
        for want in expected.trips {
            guard let got = trips.first(where: { $0.id == want.id }) else { continue }
            let e = "trip", i = want.id, l = want.name
            rec.check(e, i, label: l, "name", expected: want.name, actual: got.name)
            rec.check(e, i, label: l, "startDayISO", expected: want.startDayISO, actual: got.startDayISO)
            rec.check(e, i, label: l, "dayCount", expected: want.dayCount, actual: got.dayCount)
            rec.check(e, i, label: l, "notes", expected: want.notes, actual: got.notes)
            rec.check(e, i, label: l, "createdAt", expected: want.createdAt, actual: t(got.createdAt))
            rec.check(e, i, label: l, "updatedAt", expected: want.updatedAt, actual: t(got.updatedAt))
            rec.check(e, i, label: l, "folderID", expected: want.folderID, actual: got.folder?.id)
            rec.check(e, i, label: l, "sortOrder", expected: want.sortOrder, actual: got.sortOrder)
            rec.check(e, i, label: l, "isPinned", expected: want.isPinned, actual: got.isPinned)
            rec.check(e, i, label: l, "pinnedAt", expected: want.pinnedAt, actual: got.pinnedAt.map(t))
            rec.check(e, i, label: l, "transferTimingsRaw", expected: want.transferTimingsRaw, actual: got.transferTimingsRaw)
            rec.check(e, i, label: l, "stopIDs (ordered)", expected: want.stopIDs, actual: got.orderedStops.map(\.id))
            rec.check("v5Defaults", i, label: l, "trip startPlaceID/timeZonePolicyRaw", expected: "nil/spot", actual: "\(got.startPlaceID.map(\.uuidString) ?? "nil")/\(got.timeZonePolicyRaw)")

            // The IterModel value, converted with the carried v1 encoder, against the old TripPlan.
            let trip = got.value()
            guard let plan = want.plan else {
                rec.record("tripPlan", i.uuidString, l, "plan", before: "(missing from the expected dump)", after: "")
                continue
            }
            let actualPlan = ITERFileV1(trip: trip, exportedAt: Date(timeIntervalSince1970: 0)).plan
            try planDifferences(expected: plan, actual: actualPlan, entity: "tripPlan", id: i, label: l, into: &rec)
            rec.check("tripValue", i, label: l, "folderID/sortOrder/isPinned", expected: "\(want.folderID.map(\.uuidString) ?? "nil")/\(want.sortOrder)/\(want.isPinned)",
                      actual: "\(trip.folderID.map(\.uuidString) ?? "nil")/\(trip.sortOrder)/\(trip.isPinned)")
            rec.check("v5Defaults", i, label: l, "trip value startPlaceID/timeZonePolicy", expected: "nil/spot", actual: "\(trip.startPlaceID.map { "\($0)" } ?? "nil")/\(trip.timeZonePolicy.rawValue)")
            for (stop, old) in zip(trip.stops, plan.stops) {
                rec.check("v5Defaults", old.id, label: l, "stop value dwell/fixedArrival/kind", expected: "0/nil/light",
                          actual: "\(stop.dwellMinutes)/\(stop.fixedArrival.map { "\($0)" } ?? "nil")/\(stop.kind.rawValue)")
                rec.check("tripValue", old.id, label: l, "stop place legacySpotID", expected: old.spot.id, actual: stop.place.legacySpotID)
            }
        }

        // Stops (including a stop whose place is nil)
        let stops = try context.fetch(FetchDescriptor<StopRecord>())
        rec.check("stop", UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, "ids", expected: Set(expected.stops.map(\.id)), actual: Set(stops.map(\.id)))
        for want in expected.stops {
            guard let got = stops.first(where: { $0.id == want.id }) else { continue }
            let e = "stop", i = want.id, l = want.tripID.flatMap { tripNames[$0] }
            rec.check(e, i, label: l, "dayIndex", expected: want.dayIndex, actual: got.dayIndex)
            rec.check(e, i, label: l, "sortOrder", expected: want.sortOrder, actual: got.sortOrder)
            rec.check(e, i, label: l, "sessionRaw", expected: want.sessionRaw, actual: got.sessionRaw)
            rec.check(e, i, label: l, "setUpBufferMinutes", expected: want.setUpBufferMinutes, actual: got.setUpBufferMinutes)
            rec.check(e, i, label: l, "note", expected: want.note, actual: got.note)
            rec.check(e, i, label: l, "driveNote", expected: want.driveNote, actual: got.driveNote)
            rec.check(e, i, label: l, "tripID", expected: want.tripID, actual: got.trip?.id)
            rec.check(e, i, label: l, "placeID", expected: want.placeID, actual: got.place?.id)
            rec.check("v5Defaults", i, label: l, "stop dwellMinutes/fixedArrivalISO/kindRaw", expected: "0//light", actual: "\(got.dwellMinutes)/\(got.fixedArrivalISO)/\(got.kindRaw)")
        }

        // The new models start empty.
        rec.check("v5Defaults", UUID(uuidString: "00000000-0000-0000-0000-000000000000")!, "new models (run/visit/deletion/syncPeer counts)", expected: [0, 0, 0, 0],
                  actual: [try context.fetchCount(FetchDescriptor<TripRunRecord>()), try context.fetchCount(FetchDescriptor<StopVisitRecord>()),
                           try context.fetchCount(FetchDescriptor<DeletionRecord>()), try context.fetchCount(FetchDescriptor<SyncPeerRecord>())])
        return ComparisonResult(differences: rec.differences, skipped: rec.skipped, checkCount: rec.checkCount)
    }

    /// What the app sees through `LibraryStore`'s repositories (not raw fetches) against the expected dump: the trip list
    /// and each trip's value, saved places, pins, folders in order, and filing.
    @MainActor
    static func compareLibrary(_ library: LibraryStore, expected: ExpectedStore) throws -> ComparisonResult {
        var rec = ComparisonRecorder()
        let none = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        func ids(_ a: [UUID]) -> [String] { a.map(\.uuidString) }

        // Trips
        let allTrips = library.trips.all()
        rec.check("libraryTrips", none, "all() ids", expected: Set(expected.trips.map(\.id)), actual: Set(allTrips.map(\.id)))
        for want in expected.trips {
            guard let plan = want.plan, let value = library.trips.value(id: want.id) else { continue }
            try planDifferences(expected: plan, actual: ITERFileV1(trip: value, exportedAt: Date(timeIntervalSince1970: 0)).plan,
                                entity: "libraryTripValue", id: want.id, label: want.name, into: &rec)
        }
        rec.check("libraryTrips", none, "pinned() ids in order", expected: ids(expected.trips.filter(\.isPinned).sorted {
            ($0.pinnedAt ?? .infinity, $0.id.uuidString) < ($1.pinnedAt ?? .infinity, $1.id.uuidString) }.map(\.id)),
                  actual: ids(library.trips.pinned().map(\.id)))
        let unfiled = expected.trips.filter { $0.folderID == nil }.map(\.id)
        rec.check("libraryTrips", none, "unfiled trip ids", expected: Set(unfiled), actual: Set(library.trips.trips(in: nil).map(\.id)))

        // Places
        let wantSaved = expected.places.filter { $0.isSaved || $0.originRaw == "user" }
        rec.check("libraryPlaces", none, "savedPlaces() ids", expected: Set(wantSaved.map(\.id)), actual: Set(library.places.savedPlaces().map(\.id)))
        rec.check("libraryPlaces", none, "pinned() ids in order", expected: ids(wantSaved.filter(\.isPinned).sorted {
            ($0.pinnedAt ?? .infinity, $0.id.uuidString) < ($1.pinnedAt ?? .infinity, $1.id.uuidString) }.map(\.id)),
                  actual: ids(library.places.pinned().map(\.id)))

        // Folders
        for kind in FolderKind.allCases {
            let want = expected.folders.filter { $0.kindRaw == kind.rawValue }
            let got = library.folders.list(kind: kind)
            rec.check("libraryFolders", none, "\(kind.rawValue) ids", expected: Set(want.map(\.id)), actual: Set(got.map(\.id)))
            let sorted = got.map(\.sortOrder)
            rec.check("libraryFolders", none, "\(kind.rawValue) order is by sortOrder", expected: true, actual: sorted == sorted.sorted())
            rec.check("libraryFolders", none, "\(kind.rawValue) pinned ids in order", expected: ids(want.filter(\.isPinned).sorted {
                ($0.pinnedAt ?? .infinity, $0.id.uuidString) < ($1.pinnedAt ?? .infinity, $1.id.uuidString) }.map(\.id)),
                      actual: ids(library.folders.pinned(kind: kind).map(\.id)))
        }
        for want in expected.folders where want.kindRaw == FolderKind.trips.rawValue {
            guard let folder = library.folders.folder(id: want.id) else { continue }
            rec.check("libraryFolders", want.id, label: want.name, "trips(in:) ids", expected: Set(want.tripIDs), actual: Set(library.trips.trips(in: folder).map(\.id)))
        }
        return ComparisonResult(differences: rec.differences, skipped: rec.skipped, checkCount: rec.checkCount)
    }
}
