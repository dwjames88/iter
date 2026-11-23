import Foundation
import IterModel
import IterPlan

/// The drives the builder worked out for one trip, kept on disk so Go starts from them (BLUEPRINT §10.7): planned leave-by and
/// arrival times with no network, and a road line to measure progress against. Keyed by the stop ids Build and Go both use
/// (the first leg starts at the trip's start place id), plus the drive mode. A leg is only trusted while the places it joins
/// are still where they were (`legs(for:start:)`).
public struct PlannedLegs: Codable, Equatable, Sendable {
    public static let currentFormat = 1
    /// The only mode the builder asks for today; stored so a walking or cycling plan could sit beside it later.
    public static let drivingMode = "driving"

    public struct Entry: Codable, Equatable, Sendable {
        public var from: UUID
        public var to: UUID
        public var mode: String
        /// When this drive was last computed (kept while the drive is unchanged).
        public var computedAt: Date
        public var leg: Leg

        public init(from: UUID, to: UUID, mode: String = PlannedLegs.drivingMode, computedAt: Date, leg: Leg) {
            self.from = from
            self.to = to
            self.mode = mode
            self.computedAt = computedAt
            self.leg = leg
        }

        public var key: LegKey { LegKey(from, to) }
    }

    public var format: Int
    public var tripID: UUID
    public var entries: [Entry]

    public init(format: Int = PlannedLegs.currentFormat, tripID: UUID, entries: [Entry]) {
        self.format = format
        self.tripID = tripID
        self.entries = entries
    }

    /// The driving legs that still fit the trip: both ends are a stop (or the start place) of `trip` and the stored leg begins and
    /// ends within `tolerance` metres of where those places are now. Anything else is dropped, so Go routes it itself.
    public func legs(for trip: Trip, start: Place?, tolerance: Double = 50) -> [LegKey: Leg] {
        var places: [UUID: Coordinate] = [:]
        for stop in trip.stops { places[stop.id] = stop.place.coordinate }
        if let start { places[start.id] = start.coordinate }
        var out: [LegKey: Leg] = [:]
        for entry in entries where entry.mode == Self.drivingMode {
            guard let a = places[entry.from], let b = places[entry.to],
                  a.distance(to: entry.leg.from) <= tolerance, b.distance(to: entry.leg.to) <= tolerance else { continue }
            out[entry.key] = entry.leg
        }
        return out
    }
}

/// Where a trip's planned legs live.
public protocol PlannedLegStoring: Sendable {
    func load(tripID: UUID) -> PlannedLegs?
    func save(_ legs: PlannedLegs)
}

/// One small file per trip beside the offline pack (`<OfflinePacks>/<tripID>.legs`, JSON, written atomically). A separate file
/// rather than a part of the conditions pack: the pack is rebuilt from scratch by Conditions on its own schedule and knows
/// nothing about routing, while legs change whenever the builder gets a drive answer. The `.legs` extension keeps the pack
/// loader (which reads `*.json`) from ever trying to read it.
public struct PlannedLegFileStore: PlannedLegStoring {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    private func url(_ tripID: UUID) -> URL { directory.appendingPathComponent("\(tripID.uuidString).legs") }

    public func load(tripID: UUID) -> PlannedLegs? {
        guard let data = try? Data(contentsOf: url(tripID)),
              let legs = try? JSONDecoder().decode(PlannedLegs.self, from: data),
              legs.format <= PlannedLegs.currentFormat, legs.tripID == tripID else { return nil }
        return legs
    }

    public func save(_ legs: PlannedLegs) {
        guard let data = try? JSONEncoder().encode(legs) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url(legs.tripID), options: .atomic)
    }
}

/// Keeps legs in memory (tests, and in-memory stores that have no folder to write to).
public final class InMemoryPlannedLegStore: PlannedLegStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var all: [UUID: PlannedLegs] = [:]
    public private(set) var saveCount = 0

    public init() {}

    public func load(tripID: UUID) -> PlannedLegs? { lock.withLock { all[tripID] } }

    public func save(_ legs: PlannedLegs) {
        lock.withLock {
            all[legs.tripID] = legs
            saveCount += 1
        }
    }
}
