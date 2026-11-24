import Foundation
import SwiftData
import IterCore
@testable import IterData

// The frozen schema classes (and the live V4 classes) share property names, so empty conformances let one set of
// readers and writers work on every version. A version that lacks a field simply does not conform to its protocol.

protocol FolderBaseF: AnyObject {
    init(id: UUID)
    var id: UUID { get set }
    var name: String { get set }
    var kindRaw: String { get set }
    var sortOrder: Double { get set }
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
}
protocol FolderPinF: AnyObject { var isPinned: Bool { get set }; var pinnedAt: Date? { get set } }

protocol PlaceBaseF: AnyObject {
    init(id: UUID)
    var id: UUID { get set }
    var curatedID: String? { get set }
    var originRaw: String { get set }
    var externalID: String? { get set }
    var name: String { get set }
    var locality: String { get set }
    var latitude: Double { get set }
    var longitude: Double { get set }
    var timeZoneIdentifier: String { get set }
    var categoryRaw: String { get set }
    var bestLightRaw: String { get set }
    var facing: Double? { get set }
    var blurb: String { get set }
    var notes: String { get set }
    var walkInMinutes: Int? { get set }
    var elevationMeters: Double? { get set }
    var popularity: Int { get set }
    var tagsRaw: String { get set }
    var isSaved: Bool { get set }
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
}
protocol PlaceFolderF: AnyObject { var sortOrder: Double { get set } }
protocol PlacePinF: AnyObject { var isPinned: Bool { get set }; var pinnedAt: Date? { get set } }

protocol TripBaseF: AnyObject {
    init(id: UUID)
    var id: UUID { get set }
    var name: String { get set }
    var startDayISO: String { get set }
    var dayCount: Int { get set }
    var notes: String { get set }
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
}
protocol TripFolderF: AnyObject {
    var sortOrder: Double { get set }
    var isPinned: Bool { get set }
    var pinnedAt: Date? { get set }
}
protocol TripTimingF: AnyObject { var transferTimingsRaw: String { get set } }

protocol StopBaseF: AnyObject {
    init(id: UUID)
    var id: UUID { get set }
    var dayIndex: Int { get set }
    var sortOrder: Double { get set }
    var sessionRaw: String { get set }
    var setUpBufferMinutes: Int { get set }
    var note: String { get set }
}
protocol StopDriveF: AnyObject { var driveNote: String { get set } }

extension IterSchemaV1.PlaceRecord: PlaceBaseF {}
extension IterSchemaV1.TripRecord: TripBaseF {}
extension IterSchemaV1.StopRecord: StopBaseF {}

extension IterSchemaV2.FolderRecord: FolderBaseF {}
extension IterSchemaV2.PlaceRecord: PlaceBaseF, PlaceFolderF {}
extension IterSchemaV2.TripRecord: TripBaseF, TripFolderF {}
extension IterSchemaV2.StopRecord: StopBaseF {}

extension IterSchemaV3.FolderRecord: FolderBaseF, FolderPinF {}
extension IterSchemaV3.PlaceRecord: PlaceBaseF, PlaceFolderF, PlacePinF {}
extension IterSchemaV3.TripRecord: TripBaseF, TripFolderF {}
extension IterSchemaV3.StopRecord: StopBaseF {}

extension FolderRecord: FolderBaseF, FolderPinF {}
extension PlaceRecord: PlaceBaseF, PlaceFolderF, PlacePinF {}
extension TripRecord: TripBaseF, TripFolderF, TripTimingF {}
extension StopRecord: StopBaseF, StopDriveF {}

// MARK: - Scalar readers (every stored non-relationship field the object has)

func folderScalars(_ f: any FolderBaseF) -> [String: J] {
    var o: [String: J] = ["id": .uuid(f.id), "name": .string(f.name), "kindRaw": .string(f.kindRaw),
                          "sortOrder": .double(f.sortOrder), "createdAt": .date(f.createdAt), "updatedAt": .date(f.updatedAt)]
    if let p = f as? any FolderPinF { o["isPinned"] = .bool(p.isPinned); o["pinnedAt"] = .date(p.pinnedAt) }
    return o
}

func placeScalars(_ p: any PlaceBaseF) -> [String: J] {
    var o: [String: J] = [
        "id": .uuid(p.id), "curatedID": .opt(p.curatedID), "originRaw": .string(p.originRaw), "externalID": .opt(p.externalID),
        "name": .string(p.name), "locality": .string(p.locality), "latitude": .double(p.latitude), "longitude": .double(p.longitude),
        "timeZoneIdentifier": .string(p.timeZoneIdentifier), "categoryRaw": .string(p.categoryRaw),
        "bestLightRaw": .string(p.bestLightRaw), "facing": .opt(p.facing), "blurb": .string(p.blurb), "notes": .string(p.notes),
        "walkInMinutes": .opt(p.walkInMinutes), "elevationMeters": .opt(p.elevationMeters), "popularity": .int(p.popularity),
        "tagsRaw": .string(p.tagsRaw), "isSaved": .bool(p.isSaved), "createdAt": .date(p.createdAt), "updatedAt": .date(p.updatedAt)]
    if let f = p as? any PlaceFolderF { o["sortOrder"] = .double(f.sortOrder) }
    if let n = p as? any PlacePinF { o["isPinned"] = .bool(n.isPinned); o["pinnedAt"] = .date(n.pinnedAt) }
    return o
}

func tripScalars(_ t: any TripBaseF) -> [String: J] {
    var o: [String: J] = ["id": .uuid(t.id), "name": .string(t.name), "startDayISO": .string(t.startDayISO),
                          "dayCount": .int(t.dayCount), "notes": .string(t.notes),
                          "createdAt": .date(t.createdAt), "updatedAt": .date(t.updatedAt)]
    if let f = t as? any TripFolderF {
        o["sortOrder"] = .double(f.sortOrder); o["isPinned"] = .bool(f.isPinned); o["pinnedAt"] = .date(f.pinnedAt)
    }
    if let x = t as? any TripTimingF { o["transferTimingsRaw"] = .string(x.transferTimingsRaw) }
    return o
}

func stopScalars(_ s: any StopBaseF) -> [String: J] {
    var o: [String: J] = ["id": .uuid(s.id), "dayIndex": .int(s.dayIndex), "sortOrder": .double(s.sortOrder),
                          "sessionRaw": .string(s.sessionRaw), "setUpBufferMinutes": .int(s.setUpBufferMinutes),
                          "note": .string(s.note)]
    if let d = s as? any StopDriveF { o["driveNote"] = .string(d.driveNote) }
    return o
}

func sortedByID(_ items: [[String: J]]) -> J {
    func key(_ o: [String: J]) -> String { if case .string(let s)? = o["id"] { return s } else { return "" } }
    return .array(items.sorted { key($0) < key($1) }.map { .object($0) })
}

/// Stops ordered like `TripRecord.orderedStops`: day, then sortOrder, then id string.
func orderedStopIDs<S: StopBaseF>(_ stops: [S]) -> [UUID] {
    stops.sorted { ($0.dayIndex, $0.sortOrder, $0.id.uuidString) < ($1.dayIndex, $1.sortOrder, $1.id.uuidString) }.map(\.id)
}
