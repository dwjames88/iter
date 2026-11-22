import Foundation

/// When the overnight drive into a new area happens, chosen per transfer (keyed by the arriving day).
public enum TransferTiming: String, Codable, Sendable, CaseIterable {
    /// Drive on the day of the shoot; leave-by is worked backward from the first stop's arrival.
    case morning
    /// Drive after the previous stop's session ends, and sleep near the destination.
    case eveningBefore
}

/// What a stop is for. Lodging and waypoints are not driven by light.
public enum StopKind: String, Codable, CaseIterable, Hashable, Sendable {
    case light
    case lodging
    case waypoint
}

/// Which time zone a trip's days are read in. Reserved: today it is always the place's own zone.
public enum TimeZonePolicy: String, Codable, CaseIterable, Hashable, Sendable {
    case spot
}

/// A stop in a trip, as a value: one place, one day, one light session.
public struct Stop: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var place: Place
    /// 0-based day within the trip.
    public var dayIndex: Int
    /// The window this stop is for. Every stop has one (assigned by default from the place's best light).
    public var session: LightWindowKind
    /// Minutes before the window starts that you want to be set up (default 20).
    public var setUpBufferMinutes: Int
    public var note: String
    /// A note about the drive INTO this stop. Stored on the arriving stop so it travels with the stop when reordered.
    public var driveNote: String
    /// How long you stay, in minutes. 0 means "until the window ends".
    public var dwellMinutes: Int
    /// A user-fixed arrival time, for stops not driven by light (lodging, a meal).
    public var fixedArrival: LocalTime?
    public var kind: StopKind

    public init(id: UUID = UUID(), place: Place, dayIndex: Int, session: LightWindowKind, setUpBufferMinutes: Int = 20,
                note: String = "", driveNote: String = "", dwellMinutes: Int = 0, fixedArrival: LocalTime? = nil,
                kind: StopKind = .light) {
        self.id = id
        self.place = place
        self.dayIndex = dayIndex
        self.session = session
        self.setUpBufferMinutes = setUpBufferMinutes
        self.note = note
        self.driveNote = driveNote
        self.dwellMinutes = dwellMinutes
        self.fixedArrival = fixedArrival
        self.kind = kind
    }

    private enum CodingKeys: String, CodingKey {
        case id, place, dayIndex, session, setUpBufferMinutes, note, driveNote, dwellMinutes, fixedArrival, kind
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        place = try c.decode(Place.self, forKey: .place)
        dayIndex = try c.decode(Int.self, forKey: .dayIndex)
        session = try c.decode(LightWindowKind.self, forKey: .session)
        setUpBufferMinutes = try c.decodeIfPresent(Int.self, forKey: .setUpBufferMinutes) ?? 20
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        driveNote = try c.decodeIfPresent(String.self, forKey: .driveNote) ?? ""
        dwellMinutes = try c.decodeIfPresent(Int.self, forKey: .dwellMinutes) ?? 0
        fixedArrival = try c.decodeIfPresent(LocalTime.self, forKey: .fixedArrival)
        kind = try c.decodeIfPresent(StopKind.self, forKey: .kind) ?? .light
    }
}

/// A trip as a value: what the scheduler, the exporter and tests work on. The SwiftData `TripRecord` converts to this.
public struct Trip: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var startDay: LocalDay
    /// At least 1.
    public var dayCount: Int
    /// Ordered within each day; the array order across days is day-major.
    public var stops: [Stop]
    public var notes: String
    /// Timing of the transfer into each arriving day (a day after the first). Only non-morning entries need be stored.
    public var transferTimings: [Int: TransferTiming]

    // Library metadata
    public var folderID: UUID?
    public var sortOrder: Double
    public var isPinned: Bool
    public var pinnedAt: Date?
    /// Defaults to `.distantPast`: this target never reads the clock, so callers stamp real dates.
    public var createdAt: Date
    public var updatedAt: Date

    // V5
    /// Where day 1 starts, for a first-stop leave-by.
    public var startPlaceID: UUID?
    public var timeZonePolicy: TimeZonePolicy

    public init(id: UUID = UUID(), name: String, startDay: LocalDay, dayCount: Int, stops: [Stop] = [], notes: String = "",
                transferTimings: [Int: TransferTiming] = [:], folderID: UUID? = nil, sortOrder: Double = 0,
                isPinned: Bool = false, pinnedAt: Date? = nil, createdAt: Date = .distantPast, updatedAt: Date = .distantPast,
                startPlaceID: UUID? = nil, timeZonePolicy: TimeZonePolicy = .spot) {
        self.id = id
        self.name = name
        self.startDay = startDay
        self.dayCount = max(1, dayCount)
        self.stops = stops
        self.notes = notes
        self.transferTimings = transferTimings
        self.folderID = folderID
        self.sortOrder = sortOrder
        self.isPinned = isPinned
        self.pinnedAt = pinnedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.startPlaceID = startPlaceID
        self.timeZonePolicy = timeZonePolicy
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, startDay, dayCount, stops, notes, transferTimings, folderID, sortOrder, isPinned, pinnedAt
        case createdAt, updatedAt, startPlaceID, timeZonePolicy
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        startDay = try c.decode(LocalDay.self, forKey: .startDay)
        dayCount = max(1, try c.decodeIfPresent(Int.self, forKey: .dayCount) ?? 1)
        stops = try c.decodeIfPresent([Stop].self, forKey: .stops) ?? []
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        transferTimings = try c.decodeIfPresent([Int: TransferTiming].self, forKey: .transferTimings) ?? [:]
        folderID = try c.decodeIfPresent(UUID.self, forKey: .folderID)
        sortOrder = try c.decodeIfPresent(Double.self, forKey: .sortOrder) ?? 0
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        pinnedAt = try c.decodeIfPresent(Date.self, forKey: .pinnedAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        startPlaceID = try c.decodeIfPresent(UUID.self, forKey: .startPlaceID)
        timeZonePolicy = try c.decodeIfPresent(TimeZonePolicy.self, forKey: .timeZonePolicy) ?? .spot
    }

    /// The timing of the transfer into `day`: morning when absent, and always morning for the first day.
    public func transferTiming(intoDay day: Int) -> TransferTiming {
        day > 0 ? (transferTimings[day] ?? .morning) : .morning
    }

    public func stops(onDay index: Int) -> [Stop] { stops.filter { $0.dayIndex == index } }
    public func day(_ index: Int) -> LocalDay { startDay.adding(days: index) }
}
