import Foundation
import UniformTypeIdentifiers
import IterModel

/// Why an `.iter` file could not be read.
public enum ITERFileError: Error, Hashable, Sendable {
    /// The header names a `formatVersion` this reader does not handle.
    case unsupportedVersion(Int)
    /// The bytes are not a valid `.iter` document.
    case corrupt
}

extension UTType {
    /// The `.iter` trip type. The app declares it as an exported type in its Info.plist.
    public static let iterTrip = UTType(exportedAs: "com.dwjames.iter.trip", conformingTo: .json)
}

/// Names shared by every `.iter` version.
public enum ITERFileInfo {
    public static let typeIdentifier = "com.dwjames.iter.trip"
    public static let fileExtension = "iter"

    /// A file name safe on every file system, with the `.iter` extension. Ported unchanged from the old `TripDocument`.
    public static func suggestedFileName(forTripNamed name: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|").union(.controlCharacters).union(.newlines)
        let cleaned = name.components(separatedBy: forbidden).joined(separator: " ")
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return (cleaned.isEmpty ? "Trip" : cleaned) + "." + fileExtension
    }
}

/// The encoder every `.iter` version uses: pretty printed, sorted keys, ISO-8601 dates (the old encoder's settings).
func makeITEREncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
}

func makeITERDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
}

/// v2 encoder: as v1, but dates keep milliseconds ("2026-11-22T10:20:30.123Z"). The fraction is written from the integer
/// millisecond, so formatter truncation cannot move a value by one.
func makeITERv2Encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .custom { date, encoder in
        var container = encoder.singleValueContainer()
        let millis = Int((date.timeIntervalSince1970 * 1000).rounded())
        let seconds = Int((Double(millis) / 1000).rounded(.down))
        let whole = Date(timeIntervalSince1970: Double(seconds)).formatted(Date.ISO8601FormatStyle())  // "...Z"
        let fraction = String(format: ".%03d", millis - seconds * 1000)
        try container.encode(String(whole.dropLast()) + fraction + "Z")
    }
    return encoder
}

/// v2 decoder: accepts dates with or without fractional seconds (any number of digits, read exactly, no float parsing).
func makeITERv2Decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
        let text = try decoder.singleValueContainer().decode(String.self)
        var base = text
        var fraction = 0.0
        if let dot = text.firstIndex(of: ".") {
            let digitsEnd = text[text.index(after: dot)...].firstIndex(where: { !$0.isNumber }) ?? text.endIndex
            let digits = text[text.index(after: dot)..<digitsEnd]
            base = String(text[..<dot]) + String(text[digitsEnd...])
            if let n = Double(digits), !digits.isEmpty { fraction = n / pow(10, Double(digits.count)) }
        }
        guard let date = try? Date(base, strategy: Date.ISO8601FormatStyle()) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not an ISO-8601 date: \(text)"))
        }
        return date.addingTimeInterval(fraction)
    }
    return decoder
}

extension Date {
    /// The date at millisecond resolution: the precision of a v2 file, and of merge comparisons.
    var millisecondRounded: Date {
        Date(timeIntervalSince1970: (timeIntervalSince1970 * 1000).rounded() / 1000)
    }
}

struct ITERFileHeader: Decodable { var formatVersion: Int }

/// The `.iter` format version 1, byte-compatible with the old `TripDocument`: one trip as JSON,
/// `{formatVersion, exportedAt, trip: {id, name, startDay, dayCount, stops, notes, transferTimings}}`.
///
/// The DTOs mirror the old JSON exactly (including its tolerance for a missing `driveNote` or `transferTimings`, and
/// the clamp of `dayCount` to at least 1) so an old file decodes and re-encodes to the same bytes.
///
/// Mapping to and from the model (`init(trip:exportedAt:)`, `trip(...)`):
/// - Export: a stop's `spot.id` is `place.legacySpotID` (the curated slug, else the place's UUID string). The v1
///   fields only; V5 fields (dwell, fixed arrival, kind, provenance, folders, pins, sort order) are not written.
/// - Import: a spot whose origin is `curated` gets `curatedID = spot.id` and a fresh UUID. Otherwise a spot whose id
///   parses as a UUID keeps that UUID, and any other id becomes `externalID` with a fresh UUID. `isSaved` is true
///   only for `origin == .user`, matching the old `upsertPlace`. The same spot id within one file maps to one place.
/// - Trip and stop ids are kept, so a file round-trips. A caller that wants a new trip (the old behaviour) uses
///   `MergePlan.asCopy` or `Trip.copyWithNewIDs`.
/// - Not round-tripped: an imported non-UUID, non-curated spot id is exported back as the place's UUID string.
public struct ITERFileV1: Codable, Hashable, Sendable {
    public static let currentFormatVersion = 1

    public var formatVersion: Int
    public var exportedAt: Date
    public var plan: TripDTO

    private enum CodingKeys: String, CodingKey {
        case formatVersion, exportedAt
        case plan = "trip"
    }

    public struct TripDTO: Codable, Hashable, Sendable {
        public var id: UUID
        public var name: String
        public var startDay: LocalDay
        public var dayCount: Int
        public var stops: [StopDTO]
        public var notes: String
        public var transferTimings: [Int: TransferTiming]

        private enum CodingKeys: String, CodingKey { case id, name, startDay, dayCount, stops, notes, transferTimings }

        init(id: UUID, name: String, startDay: LocalDay, dayCount: Int, stops: [StopDTO], notes: String,
             transferTimings: [Int: TransferTiming]) {
            self.id = id
            self.name = name
            self.startDay = startDay
            self.dayCount = max(1, dayCount)
            self.stops = stops
            self.notes = notes
            self.transferTimings = transferTimings
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            startDay = try c.decode(LocalDay.self, forKey: .startDay)
            dayCount = max(1, try c.decode(Int.self, forKey: .dayCount))
            stops = try c.decode([StopDTO].self, forKey: .stops)
            notes = try c.decode(String.self, forKey: .notes)
            // Files written before transfer timings existed have no key.
            transferTimings = try c.decodeIfPresent([Int: TransferTiming].self, forKey: .transferTimings) ?? [:]
        }
    }

    public struct StopDTO: Codable, Hashable, Sendable {
        public var id: UUID
        public var spot: SpotDTO
        public var dayIndex: Int
        public var session: LightWindowKind
        public var setUpBufferMinutes: Int
        public var note: String
        public var driveNote: String

        private enum CodingKeys: String, CodingKey { case id, spot, dayIndex, session, setUpBufferMinutes, note, driveNote }

        init(id: UUID, spot: SpotDTO, dayIndex: Int, session: LightWindowKind, setUpBufferMinutes: Int, note: String,
             driveNote: String) {
            self.id = id
            self.spot = spot
            self.dayIndex = dayIndex
            self.session = session
            self.setUpBufferMinutes = setUpBufferMinutes
            self.note = note
            self.driveNote = driveNote
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            spot = try c.decode(SpotDTO.self, forKey: .spot)
            dayIndex = try c.decode(Int.self, forKey: .dayIndex)
            session = try c.decode(LightWindowKind.self, forKey: .session)
            setUpBufferMinutes = try c.decode(Int.self, forKey: .setUpBufferMinutes)
            note = try c.decode(String.self, forKey: .note)
            // Files written before drive notes existed have no key.
            driveNote = try c.decodeIfPresent(String.self, forKey: .driveNote) ?? ""
        }
    }

    /// The old `Spot`, key for key.
    public struct SpotDTO: Codable, Hashable, Sendable {
        public var id: String
        public var name: String
        public var locality: String
        public var coordinate: Coordinate
        public var timeZoneIdentifier: String
        public var category: PlaceCategory
        public var bestLight: [BestLight]
        public var facing: Double?
        public var blurb: String
        public var notes: String
        public var walkInMinutes: Int?
        public var elevationMeters: Double?
        public var popularity: Int
        public var tags: [String]
        public var origin: PlaceOrigin
    }

    /// `exportedAt` is truncated to whole seconds so a document survives encode and decode unchanged.
    public init(trip: Trip, exportedAt: Date) {
        formatVersion = Self.currentFormatVersion
        self.exportedAt = Date(timeIntervalSince1970: exportedAt.timeIntervalSince1970.rounded(.down))
        plan = TripDTO(
            id: trip.id, name: trip.name, startDay: trip.startDay, dayCount: trip.dayCount,
            stops: trip.stops.map { stop in
                StopDTO(id: stop.id, spot: SpotDTO(place: stop.place), dayIndex: stop.dayIndex, session: stop.session,
                        setUpBufferMinutes: stop.setUpBufferMinutes, note: stop.note, driveNote: stop.driveNote)
            },
            notes: trip.notes, transferTimings: trip.transferTimings)
    }

    public func encoded() throws -> Data { try makeITEREncoder().encode(self) }

    /// Throws `unsupportedVersion` for any `formatVersion` other than 1 and `corrupt` for bytes that do not decode.
    public static func decode(_ data: Data) throws -> ITERFileV1 {
        let decoder = makeITERDecoder()
        guard let header = try? decoder.decode(ITERFileHeader.self, from: data) else { throw ITERFileError.corrupt }
        guard header.formatVersion == currentFormatVersion else { throw ITERFileError.unsupportedVersion(header.formatVersion) }
        guard let file = try? decoder.decode(ITERFileV1.self, from: data) else { throw ITERFileError.corrupt }
        return file
    }

    /// The trip as model values. `makeID` supplies fresh place UUIDs (inject it in tests); `stamp` is written to every
    /// created place's `createdAt` and `updatedAt` (this target reads no clock).
    public func trip(makeID: () -> UUID = { UUID() }, stamp: Date = .distantPast) -> Trip {
        var placesBySpotID: [String: Place] = [:]
        var stops: [Stop] = []
        for dto in plan.stops {
            let place: Place
            if let known = placesBySpotID[dto.spot.id] {
                place = known
            } else {
                place = dto.spot.place(makeID: makeID, stamp: stamp)
                placesBySpotID[dto.spot.id] = place
            }
            stops.append(Stop(id: dto.id, place: place, dayIndex: dto.dayIndex, session: dto.session,
                              setUpBufferMinutes: dto.setUpBufferMinutes, note: dto.note, driveNote: dto.driveNote))
        }
        return Trip(id: plan.id, name: plan.name, startDay: plan.startDay, dayCount: plan.dayCount, stops: stops,
                    notes: plan.notes, transferTimings: plan.transferTimings, createdAt: stamp, updatedAt: stamp)
    }
}

extension ITERFileV1.SpotDTO {
    init(place: Place) {
        self.init(id: place.legacySpotID, name: place.name, locality: place.locality, coordinate: place.coordinate,
                  timeZoneIdentifier: place.timeZoneIdentifier, category: place.category, bestLight: place.bestLight,
                  facing: place.facing, blurb: place.blurb, notes: place.notes, walkInMinutes: place.walkInMinutes,
                  elevationMeters: place.elevationMeters, popularity: place.popularity, tags: place.tags,
                  origin: place.origin)
    }

    func place(makeID: () -> UUID, stamp: Date) -> Place {
        let uuid = UUID(uuidString: id)
        var place = Place(
            id: origin == .curated ? makeID() : (uuid ?? makeID()), name: name, locality: locality,
            coordinate: coordinate, timeZoneIdentifier: timeZoneIdentifier, category: category, bestLight: bestLight,
            facing: facing, blurb: blurb, notes: notes, walkInMinutes: walkInMinutes, elevationMeters: elevationMeters,
            popularity: popularity, tags: tags, origin: origin, isSaved: origin == .user, createdAt: stamp,
            updatedAt: stamp)
        if origin == .curated {
            place.curatedID = id
        } else if uuid == nil {
            place.externalID = id
        }
        return place
    }
}
