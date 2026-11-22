import Foundation
import IterModel

/// A deletion record for sync merge: "this id was deleted at this time".
public struct LibraryTombstone: Hashable, Sendable {
    public enum Entity: String, Codable, Hashable, Sendable, CaseIterable {
        case trip, place, folder
    }

    public var entity: Entity
    public var id: UUID
    public var deletedAt: Date

    public init(entity: Entity, id: UUID, deletedAt: Date) {
        self.entity = entity
        self.id = id
        self.deletedAt = deletedAt
    }
}

/// An `.iter` file of either supported version.
public enum ITERFile: Sendable {
    case v1(ITERFileV1)
    case v2(ITERFileV2)

    /// Reads the header's `formatVersion` and dispatches. Any other version is `unsupportedVersion`.
    public static func read(_ data: Data) throws -> ITERFile {
        guard let header = try? makeITERDecoder().decode(ITERFileHeader.self, from: data) else { throw ITERFileError.corrupt }
        switch header.formatVersion {
        case 1: return .v1(try ITERFileV1.decode(data))
        case 2: return .v2(try ITERFileV2.decode(data))
        default: throw ITERFileError.unsupportedVersion(header.formatVersion)
        }
    }
}

/// The `.iter` format version 2: one trip (`kind == .trip`) or the whole library (`kind == .library`).
///
/// Trips reference places by id rather than embedding them; `places` holds every place a trip uses plus the saved
/// and own places. The file is made of DTOs, not the model's own Codable, so the format does not move when the model
/// does. Dates are ISO-8601 with fractional seconds, exact to the millisecond; decoding also accepts whole seconds.
/// Decoding ignores unknown keys and defaults missing optional ones; a stop that names a place the file does
/// not carry is `corrupt`.
public struct ITERFileV2: Codable, Hashable, Sendable {
    public static let currentFormatVersion = 2

    public enum Kind: String, Codable, Hashable, Sendable {
        case trip, library
    }

    public var formatVersion: Int
    public var exportedAt: Date
    public var kind: Kind
    public var tripDTOs: [TripDTO]
    public var placeDTOs: [PlaceDTO]
    public var folderDTOs: [FolderDTO]
    public var tombstoneDTOs: [TombstoneDTO]

    private enum CodingKeys: String, CodingKey {
        case formatVersion, exportedAt, kind
        case tripDTOs = "trips", placeDTOs = "places", folderDTOs = "folders", tombstoneDTOs = "tombstones"
    }

    // MARK: Builders

    /// One trip and the places its stops use.
    public static func trip(_ trip: Trip, exportedAt: Date) -> ITERFileV2 {
        ITERFileV2(kind: .trip, trips: [trip], places: [], folders: [], tombstones: [], exportedAt: exportedAt)
    }

    /// The library. `places` are the saved and own places; every place a trip's stops use is added, deduplicated by id
    /// (the entry with the newer `updatedAt` wins; a tie keeps the one listed first).
    public static func library(trips: [Trip], places: [Place], folders: [Folder], tombstones: [LibraryTombstone],
                               exportedAt: Date) -> ITERFileV2 {
        ITERFileV2(kind: .library, trips: trips, places: places, folders: folders, tombstones: tombstones,
                   exportedAt: exportedAt)
    }

    private init(kind: Kind, trips: [Trip], places: [Place], folders: [Folder], tombstones: [LibraryTombstone],
                 exportedAt: Date) {
        formatVersion = Self.currentFormatVersion
        // Milliseconds: the precision a v2 file keeps, so a document survives encode and decode unchanged.
        self.exportedAt = exportedAt.millisecondRounded
        self.kind = kind
        var order: [UUID] = []
        var byID: [UUID: Place] = [:]
        for place in places + trips.flatMap({ $0.stops.map(\.place) }) {
            if let existing = byID[place.id] {
                if place.updatedAt > existing.updatedAt { byID[place.id] = place }
            } else {
                byID[place.id] = place
                order.append(place.id)
            }
        }
        tripDTOs = trips.map(TripDTO.init(trip:))
        placeDTOs = order.compactMap { byID[$0] }.map(PlaceDTO.init(place:))
        folderDTOs = folders.map(FolderDTO.init(folder:))
        tombstoneDTOs = tombstones.map(TombstoneDTO.init(tombstone:))
    }

    // MARK: Accessors

    public var places: [Place] { placeDTOs.map { $0.place } }
    public var folders: [Folder] { folderDTOs.map { $0.folder } }
    /// Tombstones for an entity this reader does not know are dropped.
    public var tombstones: [LibraryTombstone] { tombstoneDTOs.compactMap { $0.tombstone } }

    /// The trips with their stops' places resolved from `places`.
    public var trips: [Trip] {
        let byID = Dictionary(placeDTOs.map { ($0.id, $0.place) }, uniquingKeysWith: { first, _ in first })
        return tripDTOs.map { $0.trip(places: byID) }
    }

    // MARK: Encode and decode

    public func encoded() throws -> Data { try makeITERv2Encoder().encode(self) }

    public static func decode(_ data: Data) throws -> ITERFileV2 {
        let decoder = makeITERv2Decoder()
        guard let header = try? decoder.decode(ITERFileHeader.self, from: data) else { throw ITERFileError.corrupt }
        guard header.formatVersion == currentFormatVersion else { throw ITERFileError.unsupportedVersion(header.formatVersion) }
        guard let file = try? decoder.decode(ITERFileV2.self, from: data) else { throw ITERFileError.corrupt }
        let known = Set(file.placeDTOs.map(\.id))
        for trip in file.tripDTOs where trip.stops.contains(where: { !known.contains($0.placeID) }) {
            throw ITERFileError.corrupt
        }
        return file
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decode(Int.self, forKey: .formatVersion)
        exportedAt = try c.decodeIfPresent(Date.self, forKey: .exportedAt) ?? .distantPast
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .library
        tripDTOs = try c.decodeIfPresent([TripDTO].self, forKey: .tripDTOs) ?? []
        placeDTOs = try c.decodeIfPresent([PlaceDTO].self, forKey: .placeDTOs) ?? []
        folderDTOs = try c.decodeIfPresent([FolderDTO].self, forKey: .folderDTOs) ?? []
        tombstoneDTOs = try c.decodeIfPresent([TombstoneDTO].self, forKey: .tombstoneDTOs) ?? []
    }
}

// MARK: - DTOs

extension KeyedDecodingContainer {
    /// Decodes `key`, or `fallback` when the key is absent.
    fileprivate func value<T: Decodable>(_ key: Key, default fallback: T) throws -> T {
        try decodeIfPresent(T.self, forKey: key) ?? fallback
    }
}

extension ITERFileV2 {
    public struct TripDTO: Codable, Hashable, Sendable {
        public var id: UUID
        public var name: String
        /// "YYYY-MM-DD".
        public var startDay: String
        public var dayCount: Int
        public var notes: String
        public var transferTimings: [Int: TransferTiming]
        public var stops: [StopDTO]
        public var folderID: UUID?
        public var sortOrder: Double
        public var isPinned: Bool
        public var pinnedAt: Date?
        public var createdAt: Date
        public var updatedAt: Date
        public var startPlaceID: UUID?
        public var timeZonePolicy: TimeZonePolicy

        private enum CodingKeys: String, CodingKey {
            case id, name, startDay, dayCount, notes, transferTimings, stops, folderID, sortOrder, isPinned, pinnedAt
            case createdAt, updatedAt, startPlaceID, timeZonePolicy
        }

        init(trip: Trip) {
            id = trip.id
            name = trip.name
            startDay = trip.startDay.iso
            dayCount = trip.dayCount
            notes = trip.notes
            transferTimings = trip.transferTimings
            stops = trip.stops.map(StopDTO.init(stop:))
            folderID = trip.folderID
            sortOrder = trip.sortOrder
            isPinned = trip.isPinned
            pinnedAt = trip.pinnedAt
            createdAt = trip.createdAt
            updatedAt = trip.updatedAt
            startPlaceID = trip.startPlaceID
            timeZonePolicy = trip.timeZonePolicy
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            startDay = try c.decode(String.self, forKey: .startDay)
            guard LocalDay(iso: startDay) != nil else {
                throw DecodingError.dataCorruptedError(forKey: .startDay, in: c, debugDescription: "Not a YYYY-MM-DD day")
            }
            dayCount = max(1, try c.value(.dayCount, default: 1))
            notes = try c.value(.notes, default: "")
            transferTimings = try c.value(.transferTimings, default: [:])
            stops = try c.value(.stops, default: [])
            folderID = try c.decodeIfPresent(UUID.self, forKey: .folderID)
            sortOrder = try c.value(.sortOrder, default: 0)
            isPinned = try c.value(.isPinned, default: false)
            pinnedAt = try c.decodeIfPresent(Date.self, forKey: .pinnedAt)
            createdAt = try c.value(.createdAt, default: .distantPast)
            updatedAt = try c.value(.updatedAt, default: .distantPast)
            startPlaceID = try c.decodeIfPresent(UUID.self, forKey: .startPlaceID)
            timeZonePolicy = try c.decodeIfPresent(TimeZonePolicy.self, forKey: .timeZonePolicy) ?? .spot
        }

        func trip(places: [UUID: Place]) -> Trip {
            Trip(id: id, name: name, startDay: LocalDay(iso: startDay) ?? LocalDay(year: 1970, month: 1, day: 1),
                 dayCount: dayCount, stops: stops.compactMap { $0.stop(places: places) }, notes: notes,
                 transferTimings: transferTimings, folderID: folderID, sortOrder: sortOrder, isPinned: isPinned,
                 pinnedAt: pinnedAt, createdAt: createdAt, updatedAt: updatedAt, startPlaceID: startPlaceID,
                 timeZonePolicy: timeZonePolicy)
        }
    }

    public struct StopDTO: Codable, Hashable, Sendable {
        public var id: UUID
        public var placeID: UUID
        public var dayIndex: Int
        public var session: LightWindowKind
        public var setUpBufferMinutes: Int
        public var note: String
        public var driveNote: String
        public var dwellMinutes: Int
        /// "HH:mm".
        public var fixedArrival: String?
        public var kind: StopKind

        private enum CodingKeys: String, CodingKey {
            case id, placeID, dayIndex, session, setUpBufferMinutes, note, driveNote, dwellMinutes, fixedArrival, kind
        }

        init(stop: Stop) {
            id = stop.id
            placeID = stop.place.id
            dayIndex = stop.dayIndex
            session = stop.session
            setUpBufferMinutes = stop.setUpBufferMinutes
            note = stop.note
            driveNote = stop.driveNote
            dwellMinutes = stop.dwellMinutes
            fixedArrival = stop.fixedArrival?.iso
            kind = stop.kind
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            placeID = try c.decode(UUID.self, forKey: .placeID)
            dayIndex = try c.decode(Int.self, forKey: .dayIndex)
            session = try c.decode(LightWindowKind.self, forKey: .session)
            setUpBufferMinutes = try c.value(.setUpBufferMinutes, default: 20)
            note = try c.value(.note, default: "")
            driveNote = try c.value(.driveNote, default: "")
            dwellMinutes = try c.value(.dwellMinutes, default: 0)
            fixedArrival = try c.decodeIfPresent(String.self, forKey: .fixedArrival)
            kind = try c.decodeIfPresent(StopKind.self, forKey: .kind) ?? .light
        }

        func stop(places: [UUID: Place]) -> Stop? {
            guard let place = places[placeID] else { return nil }
            return Stop(id: id, place: place, dayIndex: dayIndex, session: session, setUpBufferMinutes: setUpBufferMinutes,
                        note: note, driveNote: driveNote, dwellMinutes: dwellMinutes,
                        fixedArrival: fixedArrival.flatMap { LocalTime(iso: $0) }, kind: kind)
        }
    }

    public struct CoordinateDTO: Codable, Hashable, Sendable {
        public var latitude: Double
        public var longitude: Double
    }

    public struct LicenceDTO: Codable, Hashable, Sendable {
        public var key: String
        public var mayStore: Bool
    }

    public struct CitationDTO: Codable, Hashable, Sendable {
        public var source: String
        public var url: URL?
        public var title: String
        public var retrievedAt: Date
        public var licence: LicenceDTO?

        private enum CodingKeys: String, CodingKey { case source, url, title, retrievedAt, licence }

        init(citation: Citation) {
            source = citation.source.rawValue
            url = citation.url
            title = citation.title
            retrievedAt = citation.retrievedAt
            licence = citation.licence.map { LicenceDTO(key: $0.key, mayStore: $0.mayStore) }
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            source = try c.decode(String.self, forKey: .source)
            url = try c.decodeIfPresent(URL.self, forKey: .url)
            title = try c.value(.title, default: "")
            retrievedAt = try c.value(.retrievedAt, default: .distantPast)
            licence = try c.decodeIfPresent(LicenceDTO.self, forKey: .licence)
        }

        var citation: Citation {
            Citation(source: SourceID(source), url: url, title: title, retrievedAt: retrievedAt,
                     licence: licence.map { LicenceTag(key: $0.key, mayStore: $0.mayStore) })
        }
    }

    public struct HorizonDTO: Codable, Hashable, Sendable {
        public var azimuthStepDegrees: Double
        public var elevationsDegrees: [Double]
    }

    public struct PlaceDTO: Codable, Hashable, Sendable {
        public var id: UUID
        public var curatedID: String?
        public var externalID: String?
        public var name: String
        public var locality: String
        public var coordinate: CoordinateDTO
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
        public var isSaved: Bool
        public var folderID: UUID?
        public var sortOrder: Double
        public var isPinned: Bool
        public var pinnedAt: Date?
        public var createdAt: Date
        public var updatedAt: Date
        public var sources: [String]
        public var citations: [CitationDTO]
        public var verification: Verification?
        public var discoveredAt: Date?
        public var horizon: HorizonDTO?

        private enum CodingKeys: String, CodingKey {
            case id, curatedID, externalID, name, locality, coordinate, timeZoneIdentifier, category, bestLight, facing
            case blurb, notes, walkInMinutes, elevationMeters, popularity, tags, origin, isSaved, folderID, sortOrder
            case isPinned, pinnedAt, createdAt, updatedAt, sources, citations, verification, discoveredAt, horizon
        }

        init(place p: Place) {
            id = p.id
            curatedID = p.curatedID
            externalID = p.externalID
            name = p.name
            locality = p.locality
            coordinate = CoordinateDTO(latitude: p.coordinate.latitude, longitude: p.coordinate.longitude)
            timeZoneIdentifier = p.timeZoneIdentifier
            category = p.category
            bestLight = p.bestLight
            facing = p.facing
            blurb = p.blurb
            notes = p.notes
            walkInMinutes = p.walkInMinutes
            elevationMeters = p.elevationMeters
            popularity = p.popularity
            tags = p.tags
            origin = p.origin
            isSaved = p.isSaved
            folderID = p.folderID
            sortOrder = p.sortOrder
            isPinned = p.isPinned
            pinnedAt = p.pinnedAt
            createdAt = p.createdAt
            updatedAt = p.updatedAt
            sources = p.sources.map(\.rawValue)
            citations = p.citations.map(CitationDTO.init(citation:))
            verification = p.verification
            discoveredAt = p.discoveredAt
            horizon = p.horizon.map { HorizonDTO(azimuthStepDegrees: $0.azimuthStepDegrees, elevationsDegrees: $0.elevationsDegrees) }
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            curatedID = try c.decodeIfPresent(String.self, forKey: .curatedID)
            externalID = try c.decodeIfPresent(String.self, forKey: .externalID)
            name = try c.decode(String.self, forKey: .name)
            locality = try c.value(.locality, default: "")
            coordinate = try c.decode(CoordinateDTO.self, forKey: .coordinate)
            timeZoneIdentifier = try c.decode(String.self, forKey: .timeZoneIdentifier)
            category = try c.decode(PlaceCategory.self, forKey: .category)
            bestLight = try c.value(.bestLight, default: [])
            facing = try c.decodeIfPresent(Double.self, forKey: .facing)
            blurb = try c.value(.blurb, default: "")
            notes = try c.value(.notes, default: "")
            walkInMinutes = try c.decodeIfPresent(Int.self, forKey: .walkInMinutes)
            elevationMeters = try c.decodeIfPresent(Double.self, forKey: .elevationMeters)
            popularity = try c.value(.popularity, default: 50)
            tags = try c.value(.tags, default: [])
            origin = try c.value(.origin, default: PlaceOrigin.user)
            isSaved = try c.value(.isSaved, default: false)
            folderID = try c.decodeIfPresent(UUID.self, forKey: .folderID)
            sortOrder = try c.value(.sortOrder, default: 0)
            isPinned = try c.value(.isPinned, default: false)
            pinnedAt = try c.decodeIfPresent(Date.self, forKey: .pinnedAt)
            createdAt = try c.value(.createdAt, default: .distantPast)
            updatedAt = try c.value(.updatedAt, default: .distantPast)
            sources = try c.value(.sources, default: [])
            citations = try c.value(.citations, default: [])
            verification = try c.decodeIfPresent(Verification.self, forKey: .verification)
            discoveredAt = try c.decodeIfPresent(Date.self, forKey: .discoveredAt)
            horizon = try c.decodeIfPresent(HorizonDTO.self, forKey: .horizon)
        }

        var place: Place {
            Place(id: id, curatedID: curatedID, externalID: externalID, name: name, locality: locality,
                  coordinate: Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude),
                  timeZoneIdentifier: timeZoneIdentifier, category: category, bestLight: bestLight, facing: facing,
                  blurb: blurb, notes: notes, walkInMinutes: walkInMinutes, elevationMeters: elevationMeters,
                  popularity: popularity, tags: tags, origin: origin, isSaved: isSaved, folderID: folderID,
                  sortOrder: sortOrder, isPinned: isPinned, pinnedAt: pinnedAt, createdAt: createdAt,
                  updatedAt: updatedAt, sources: sources.map { SourceID($0) }, citations: citations.map(\.citation),
                  verification: verification, discoveredAt: discoveredAt,
                  horizon: horizon.map { HorizonProfile(azimuthStepDegrees: $0.azimuthStepDegrees, elevationsDegrees: $0.elevationsDegrees) })
        }
    }

    public struct FolderDTO: Codable, Hashable, Sendable {
        public var id: UUID
        public var name: String
        public var kind: FolderKind
        public var sortOrder: Double
        public var createdAt: Date
        public var updatedAt: Date
        public var isPinned: Bool
        public var pinnedAt: Date?

        private enum CodingKeys: String, CodingKey { case id, name, kind, sortOrder, createdAt, updatedAt, isPinned, pinnedAt }

        init(folder f: Folder) {
            id = f.id
            name = f.name
            kind = f.kind
            sortOrder = f.sortOrder
            createdAt = f.createdAt
            updatedAt = f.updatedAt
            isPinned = f.isPinned
            pinnedAt = f.pinnedAt
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(UUID.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            kind = try c.value(.kind, default: FolderKind.trips)
            sortOrder = try c.value(.sortOrder, default: 0)
            createdAt = try c.value(.createdAt, default: .distantPast)
            updatedAt = try c.value(.updatedAt, default: .distantPast)
            isPinned = try c.value(.isPinned, default: false)
            pinnedAt = try c.decodeIfPresent(Date.self, forKey: .pinnedAt)
        }

        var folder: Folder {
            Folder(id: id, name: name, kind: kind, sortOrder: sortOrder, createdAt: createdAt, updatedAt: updatedAt,
                   isPinned: isPinned, pinnedAt: pinnedAt)
        }
    }

    public struct TombstoneDTO: Codable, Hashable, Sendable {
        /// "trip", "place" or "folder". Kept as a string so an entity from a newer writer still decodes.
        public var entity: String
        public var id: UUID
        public var deletedAt: Date

        init(tombstone t: LibraryTombstone) {
            entity = t.entity.rawValue
            id = t.id
            deletedAt = t.deletedAt
        }

        var tombstone: LibraryTombstone? {
            LibraryTombstone.Entity(rawValue: entity).map { LibraryTombstone(entity: $0, id: id, deletedAt: deletedAt) }
        }
    }
}
