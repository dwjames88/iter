import Foundation
import IterModel

// V5 records <-> IterModel values. Pure conversions: relationships to other records (folder, place, trip) are the
// caller's job (the repositories), except where a read can follow them (a trip's stops and their places).

/// The JSON coding used for the `citationsJSON` and `horizonJSON` columns.
enum RecordJSON {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func string<T: Encodable>(_ value: T) -> String {
        (try? encoder().encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    static func value<T: Decodable>(_ type: T.Type, from json: String) -> T? {
        guard !json.isEmpty else { return nil }
        return try? decoder().decode(type, from: Data(json.utf8))
    }
}

/// The old rules for reading the stored transfer timings ("1:eveningBefore,3:eveningBefore"): entries that do not parse,
/// are for day 0 or past the last day, or are `morning` are ignored.
public enum TransferTimingsCodec {
    public static func parse(_ raw: String, dayCount: Int) -> [Int: TransferTiming] {
        var out: [Int: TransferTiming] = [:]
        for entry in raw.split(separator: ",") {
            let parts = entry.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, let day = Int(parts[0]), day > 0, day < dayCount,
                  let timing = TransferTiming(rawValue: String(parts[1])), timing != .morning else { continue }
            out[day] = timing
        }
        return out
    }

    /// Only non-morning entries for days after the first, sorted by day.
    public static func encode(_ timings: [Int: TransferTiming]) -> String {
        timings.filter { $0.key > 0 && $0.value != .morning }
            .sorted { $0.key < $1.key }
            .map { "\($0.key):\($0.value.rawValue)" }
            .joined(separator: ",")
    }
}

enum Fallback {
    static let startDay = LocalDay(year: 1970, month: 1, day: 1)
}

// MARK: - Place

extension PlaceRecord {
    /// The value form. `folderID` follows the relationship.
    public func value() -> Place {
        Place(id: id, curatedID: curatedID, externalID: externalID, name: name, locality: locality,
              coordinate: Coordinate(latitude: latitude, longitude: longitude), timeZoneIdentifier: timeZoneIdentifier,
              category: PlaceCategory(rawValue: categoryRaw) ?? .landscape,
              bestLight: bestLightRaw.split(separator: ",").compactMap { BestLight(rawValue: String($0)) },
              facing: facing, blurb: blurb, notes: notes, walkInMinutes: walkInMinutes, elevationMeters: elevationMeters,
              popularity: popularity, tags: tagsRaw.split(separator: ",").map(String.init),
              origin: PlaceOrigin(rawValue: originRaw) ?? .user, isSaved: isSaved, folderID: folder?.id,
              sortOrder: sortOrder, isPinned: isPinned, pinnedAt: pinnedAt, createdAt: createdAt, updatedAt: updatedAt,
              sources: sourcesRaw.split(separator: ",").map { SourceID(String($0)) },
              citations: RecordJSON.value([Citation].self, from: citationsJSON) ?? [],
              verification: Verification(rawValue: verificationRaw), discoveredAt: discoveredAt,
              horizon: RecordJSON.value(HorizonProfile.self, from: horizonJSON))
    }

    /// Writes every stored scalar of `place` into this record (not `id`, not the folder or stops relationships).
    public func apply(_ place: Place) {
        applyContent(place)
        isSaved = place.isSaved
        sortOrder = place.sortOrder
        isPinned = place.isPinned
        pinnedAt = place.pinnedAt
        createdAt = place.createdAt
        updatedAt = place.updatedAt
    }

    /// The content a source or the catalogue describes (name, position, light, provenance), not the library metadata
    /// (saved, pinned, filing, order, timestamps).
    public func applyContent(_ place: Place) {
        curatedID = place.curatedID
        externalID = place.externalID
        name = place.name
        locality = place.locality
        latitude = place.coordinate.latitude
        longitude = place.coordinate.longitude
        timeZoneIdentifier = place.timeZoneIdentifier
        categoryRaw = place.category.rawValue
        bestLightRaw = place.bestLight.map(\.rawValue).joined(separator: ",")
        facing = place.facing
        blurb = place.blurb
        notes = place.notes
        walkInMinutes = place.walkInMinutes
        elevationMeters = place.elevationMeters
        popularity = place.popularity
        tagsRaw = place.tags.joined(separator: ",")
        originRaw = place.origin.rawValue
        sourcesRaw = place.sources.map(\.rawValue).joined(separator: ",")
        citationsJSON = place.citations.isEmpty ? "" : RecordJSON.string(place.citations)
        verificationRaw = place.verification?.rawValue ?? ""
        discoveredAt = place.discoveredAt
        horizonJSON = place.horizon.map { RecordJSON.string($0) } ?? ""
    }
}

// MARK: - Folder

extension FolderRecord {
    public func value() -> Folder {
        Folder(id: id, name: name, kind: FolderKind(rawValue: kindRaw) ?? .trips, sortOrder: sortOrder,
               createdAt: createdAt, updatedAt: updatedAt, isPinned: isPinned, pinnedAt: pinnedAt)
    }

    /// Writes every stored scalar of `folder` (not `id`, not the relationships).
    public func apply(_ folder: Folder) {
        name = folder.name
        kindRaw = folder.kind.rawValue
        sortOrder = folder.sortOrder
        createdAt = folder.createdAt
        updatedAt = folder.updatedAt
        isPinned = folder.isPinned
        pinnedAt = folder.pinnedAt
    }
}

// MARK: - Stop and Trip

extension StopRecord {
    /// nil only if the place is missing (a broken link); such a stop is left out of the trip, as the old `plan` did.
    public func value() -> Stop? {
        guard let place else { return nil }
        return Stop(id: id, place: place.value(), dayIndex: dayIndex,
                    session: LightWindowKind(rawValue: sessionRaw) ?? .goldenEvening,
                    setUpBufferMinutes: setUpBufferMinutes, note: note, driveNote: driveNote,
                    dwellMinutes: dwellMinutes, fixedArrival: LocalTime(iso: fixedArrivalISO),
                    kind: StopKind(rawValue: kindRaw) ?? .light)
    }

    /// Writes every stored scalar of `stop` (not `id`, not the trip or place relationships). `sortOrder` is the stop's
    /// position, which the caller decides (a `Stop` value carries only its day and its place in the array).
    public func apply(_ stop: Stop, sortOrder: Double) {
        dayIndex = stop.dayIndex
        self.sortOrder = sortOrder
        sessionRaw = stop.session.rawValue
        setUpBufferMinutes = stop.setUpBufferMinutes
        note = stop.note
        driveNote = stop.driveNote
        dwellMinutes = stop.dwellMinutes
        fixedArrivalISO = stop.fixedArrival?.iso ?? ""
        kindRaw = stop.kind.rawValue
    }
}

extension TripRecord {
    /// Stops ordered by `(dayIndex, sortOrder, id.uuidString)`, exactly like the old `orderedStops`.
    public var orderedStops: [StopRecord] {
        (stops ?? []).sorted {
            ($0.dayIndex, $0.sortOrder, $0.id.uuidString) < ($1.dayIndex, $1.sortOrder, $1.id.uuidString)
        }
    }

    public var startDay: LocalDay {
        get { LocalDay(iso: startDayISO) ?? Fallback.startDay }
        set { startDayISO = newValue.iso }
    }

    public var transferTimings: [Int: TransferTiming] {
        get { TransferTimingsCodec.parse(transferTimingsRaw, dayCount: dayCount) }
        set { transferTimingsRaw = TransferTimingsCodec.encode(newValue) }
    }

    /// The value form: stops in order, a stop whose place is nil dropped.
    public func value() -> Trip {
        Trip(id: id, name: name, startDay: startDay, dayCount: dayCount, stops: orderedStops.compactMap { $0.value() },
             notes: notes, transferTimings: transferTimings, folderID: folder?.id, sortOrder: sortOrder,
             isPinned: isPinned, pinnedAt: pinnedAt, createdAt: createdAt, updatedAt: updatedAt,
             startPlaceID: startPlaceID, timeZonePolicy: TimeZonePolicy(rawValue: timeZonePolicyRaw) ?? .spot)
    }

    /// Writes every stored scalar of `trip` (not `id`, not the folder or stops relationships).
    public func apply(_ trip: Trip) {
        name = trip.name
        startDayISO = trip.startDay.iso
        dayCount = trip.dayCount
        notes = trip.notes
        createdAt = trip.createdAt
        updatedAt = trip.updatedAt
        sortOrder = trip.sortOrder
        isPinned = trip.isPinned
        pinnedAt = trip.pinnedAt
        transferTimingsRaw = TransferTimingsCodec.encode(trip.transferTimings.filter { $0.key < trip.dayCount })
        startPlaceID = trip.startPlaceID
        timeZonePolicyRaw = trip.timeZonePolicy.rawValue
    }
}
