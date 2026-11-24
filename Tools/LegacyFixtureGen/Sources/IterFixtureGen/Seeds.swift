import Foundation
import IterCore
@testable import IterData

// Fixed fixture content for the V1-V3 stores. Same story at every version; fields a version lacks are ignored by its writer.

struct FolderSeed { var key: String; var id: UUID; var name: String; var kind: FolderKind; var sortOrder: Double
    var created: Date; var updated: Date; var isPinned = false; var pinnedAt: Date? = nil; var parentKey: String? = nil }

struct PlaceSeed { var key: String; var id: UUID; var curatedID: String? = nil; var origin: SpotOrigin; var externalID: String? = nil
    var name: String; var locality: String; var lat: Double; var lon: Double; var tz: String; var category: SpotCategory
    var bestLightRaw: String; var facing: Double?; var blurb: String; var notes: String; var walkIn: Int?; var elevation: Double?
    var popularity: Int; var tagsRaw: String; var isSaved: Bool; var created: Date; var updated: Date
    var folderKey: String? = nil; var sortOrder: Double = 0; var isPinned = false; var pinnedAt: Date? = nil }

struct TripSeed { var key: String; var id: UUID; var name: String; var startDayISO: String; var dayCount: Int; var notes: String
    var created: Date; var updated: Date; var folderKey: String? = nil; var sortOrder: Double = 0
    var isPinned = false; var pinnedAt: Date? = nil }

struct StopSeed { var id: UUID; var tripKey: String; var placeKey: String?; var dayIndex: Int; var sortOrder: Double
    var session: LightWindowKind; var buffer: Int; var note: String }

struct Seed { var folders: [FolderSeed] = []; var places: [PlaceSeed] = []; var trips: [TripSeed] = []; var stops: [StopSeed] = [] }

func fixedUUID(version: Int, _ n: Int) -> UUID {
    UUID(uuidString: String(format: "0000000%d-0000-4000-8000-%012d", version, n))!
}

/// Fixed instants. `h` hours after 2026-01-01 00:00 UTC (1_767_225_600); `frac` adds sub-second precision.
func fixedDate(_ h: Int, frac: Double = 0) -> Date { Date(timeIntervalSince1970: 1_767_225_600 + Double(h) * 3600 + frac) }

private func place(from spot: Spot, key: String, id: UUID, origin: SpotOrigin, saved: Bool, created: Date, updated: Date) -> PlaceSeed {
    PlaceSeed(key: key, id: id, curatedID: origin == .curated ? spot.id : nil, origin: origin,
              externalID: nil, name: spot.name, locality: spot.locality, lat: spot.coordinate.latitude, lon: spot.coordinate.longitude,
              tz: spot.timeZoneIdentifier, category: spot.category, bestLightRaw: spot.bestLight.map(\.rawValue).joined(separator: ","),
              facing: spot.facing, blurb: spot.blurb, notes: spot.notes, walkIn: spot.walkInMinutes, elevation: spot.elevationMeters,
              popularity: spot.popularity, tagsRaw: spot.tags.joined(separator: ","), isSaved: saved, created: created, updated: updated)
}

func makeSeed(version v: Int) -> Seed {
    func curated(_ id: String) -> Spot { CuratedSpots.spot(id: id)! }
    func uid(_ n: Int) -> UUID { fixedUUID(version: v, n) }
    var s = Seed()

    // Places: curated saved (all optionals set), curated unsaved (used only by a stop), own place, Apple Maps saved + unsaved.
    var mesa = place(from: curated("mesa-arch"), key: "mesa", id: uid(101), origin: .curated, saved: true, created: fixedDate(10), updated: fixedDate(20, frac: 0.123456))
    mesa.isPinned = v >= 3; mesa.pinnedAt = v >= 3 ? fixedDate(30, frac: 0.5) : nil
    var tunnel = place(from: curated("tunnel-view"), key: "tunnel", id: uid(102), origin: .curated, saved: false, created: fixedDate(11), updated: fixedDate(21))
    tunnel.facing = nil; tunnel.walkIn = nil; tunnel.elevation = nil
    var delicate = place(from: curated("delicate-arch"), key: "delicate", id: uid(103), origin: .curated, saved: true, created: fixedDate(12), updated: fixedDate(22))
    delicate.name = "Delicate Arch (my name) \u{1F304}"; delicate.notes = "Café stop on the way: crème brûlée. 日の出 at 6:52."
    let alabama = place(from: curated("alabama-hills"), key: "alabama", id: uid(104), origin: .curated, saved: false, created: fixedDate(13), updated: fixedDate(23))
    let own = PlaceSeed(key: "own", id: uid(105), origin: .user, name: "Dad's overlook \u{26F0}\u{FE0F}", locality: "Near Bishop, CA",
                        lat: 37.3601, lon: -118.4012, tz: "America/Los_Angeles", category: .landscape, bestLightRaw: "sunset,blueHour",
                        facing: 215.5, blurb: "", notes: "Gate code 1234; \"quote\" and a / slash and \\ backslash", walkIn: 25, elevation: 1520.75,
                        popularity: 50, tagsRaw: "family,dirt road", isSaved: true, created: fixedDate(14, frac: 0.25), updated: fixedDate(24))
    let ownBare = PlaceSeed(key: "ownBare", id: uid(106), origin: .user, name: "Unnamed pullout", locality: "", lat: 0, lon: 0, tz: "UTC",
                            category: .landscape, bestLightRaw: "", facing: nil, blurb: "", notes: "", walkIn: nil, elevation: nil,
                            popularity: 50, tagsRaw: "", isSaved: false, created: fixedDate(15), updated: fixedDate(25))
    var maps = PlaceSeed(key: "maps", id: uid(107), origin: .appleMaps, externalID: "I63802885E5FD6D1\(v)", name: "Mono Lake Visitor Center",
                         locality: "Lee Vining, CA", lat: 37.9577, lon: -119.1157, tz: "America/Los_Angeles", category: .urban,
                         bestLightRaw: "", facing: nil, blurb: "", notes: "", walkIn: nil, elevation: nil, popularity: 50, tagsRaw: "",
                         isSaved: false, created: fixedDate(16), updated: fixedDate(26))
    var mapsSaved = PlaceSeed(key: "mapsSaved", id: uid(108), origin: .appleMaps, externalID: "IA0B1C2D3E4F5A6\(v)", name: "Whoa Nellie Deli",
                              locality: "Lee Vining, CA", lat: 37.9366, lon: -119.1214, tz: "America/Los_Angeles", category: .street,
                              bestLightRaw: "midday", facing: 90, blurb: "Fish tacos", notes: "Closed in winter", walkIn: 2, elevation: 2020,
                              popularity: 70, tagsRaw: "food", isSaved: true, created: fixedDate(17), updated: fixedDate(27))
    maps.popularity = 50; mapsSaved.popularity = 70

    // Folders (V2+). One nested folder each: V2 a trip folder under "2026 trips", V3 a location folder under "Sierra".
    if v >= 2 {
        var f1 = FolderSeed(key: "f1", id: uid(201), name: "2026 trips", kind: .trips, sortOrder: 0, created: fixedDate(40), updated: fixedDate(41))
        var f2 = FolderSeed(key: "f2", id: uid(202), name: "Sierra", kind: .locations, sortOrder: 5, created: fixedDate(42), updated: fixedDate(43))
        var f3 = FolderSeed(key: "f3", id: uid(203), name: "Archive", kind: .trips, sortOrder: 2.5, created: fixedDate(44), updated: fixedDate(45, frac: 0.75))
        var f4 = FolderSeed(key: "f4", id: uid(204), name: v == 2 ? "Winter \u{2744}\u{FE0F}" : "Utah", kind: v == 2 ? .trips : .locations,
                            sortOrder: v == 2 ? 7 : 3, created: fixedDate(46), updated: fixedDate(47))
        f4.parentKey = v == 2 ? "f1" : "f2"
        if v >= 3 {
            f1.isPinned = true; f1.pinnedAt = fixedDate(50, frac: 0.5)
            f2.isPinned = true; f2.pinnedAt = fixedDate(49)
            f4.isPinned = true; f4.pinnedAt = nil   // pinned but no timestamp: a state the old code never writes but the type allows
        }
        f3.isPinned = false
        s.folders = [f1, f2, f3, f4]
    }

    var places = [mesa, tunnel, delicate, alabama, own, ownBare, maps, mapsSaved]
    if v >= 2 {
        // mesa and own in "Sierra" (V3 also "Utah" holds delicate)
        places[0].folderKey = "f2"; places[0].sortOrder = 1
        places[4].folderKey = "f2"; places[4].sortOrder = 0.5
        if v >= 3 { places[2].folderKey = "f4"; places[2].sortOrder = 0; places[4].isPinned = true; places[4].pinnedAt = fixedDate(60) }
    }
    s.places = places

    var t1 = TripSeed(key: "t1", id: uid(301), name: "Eastern Sierra \u{1F342}", startDayISO: "2026-10-10", dayCount: 4,
                      notes: "Bring the 14mm and a tripod.\nSecond line with \"quotes\".", created: fixedDate(70), updated: fixedDate(71, frac: 0.5))
    var t2 = TripSeed(key: "t2", id: uid(302), name: "Utah \u{2014} Arches & Canyonlands", startDayISO: "2026-11-02", dayCount: 3,
                      notes: "", created: fixedDate(72), updated: fixedDate(73))
    var t3 = TripSeed(key: "t3", id: uid(303), name: "Weekend near home", startDayISO: "2027-01-09", dayCount: 1,
                      notes: "Fog forecast.", created: fixedDate(74), updated: fixedDate(75))
    if v >= 2 {
        t1.folderKey = "f1"; t1.sortOrder = 1.5
        t2.isPinned = true; t2.pinnedAt = fixedDate(80, frac: 0.125); t2.sortOrder = 2
        t3.folderKey = "f4"; t3.sortOrder = 0   // in the nested trip folder at V2; at V3 f4 is a location folder, so unfiled
        if v >= 3 { t3.folderKey = "f3" }
    }
    s.trips = v >= 2 ? [t1, t2, t3] : [t1, t2]

    var stops: [StopSeed] = [
        .init(id: uid(401), tripKey: "t1", placeKey: "tunnel", dayIndex: 0, sortOrder: 0, session: .goldenEvening, buffer: 20, note: "Arrive 45 min early"),
        .init(id: uid(402), tripKey: "t1", placeKey: "own", dayIndex: 0, sortOrder: 1, session: .blueEvening, buffer: 10, note: ""),
        .init(id: uid(403), tripKey: "t1", placeKey: "mesa", dayIndex: 1, sortOrder: 0, session: .blueMorning, buffer: 35, note: "Sunrise glow \u{1F305}"),
        .init(id: uid(404), tripKey: "t1", placeKey: "maps", dayIndex: 1, sortOrder: 2.5, session: .night, buffer: 0, note: "Coffee first"),
        .init(id: uid(405), tripKey: "t1", placeKey: "alabama", dayIndex: 3, sortOrder: 0, session: .goldenMorning, buffer: 20, note: ""),
        .init(id: uid(406), tripKey: "t2", placeKey: "delicate", dayIndex: 0, sortOrder: 0, session: .goldenEvening, buffer: 45, note: "Permit needed"),
        .init(id: uid(407), tripKey: "t2", placeKey: "mesa", dayIndex: 1, sortOrder: 0, session: .goldenMorning, buffer: 20, note: "Same place as in the other trip"),
        .init(id: uid(408), tripKey: "t2", placeKey: "mapsSaved", dayIndex: 1, sortOrder: 1, session: .goldenEvening, buffer: 20, note: ""),
    ]
    if v >= 3 {
        stops.append(.init(id: uid(409), tripKey: "t2", placeKey: nil, dayIndex: 2, sortOrder: 0, session: .night, buffer: 15, note: "Broken link: its place was lost"))
    }
    if v >= 2 { stops.append(.init(id: uid(410), tripKey: "t3", placeKey: "ownBare", dayIndex: 0, sortOrder: 0, session: .blueMorning, buffer: 5, note: "Fog")) }
    s.stops = stops
    return s
}
