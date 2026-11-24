import Foundation
import IterModel
import IterConditions
import IterSky
import IterSources
import IterStore

/// Straight-line routing from a formula (distance x 1.3 at 25 m/s), for previews, snapshots and the sample-data mode. It never
/// touches the network. `scale` stretches every drive (a large one makes a drive that cannot fit).
public struct BuildPreviewRouting: RoutingProvider {
    public let descriptor = SourceCatalogue.appleDirections
    public var scale: Double

    public init(scale: Double = 1) { self.scale = scale }

    public func route(from: Coordinate, to: Coordinate, departing: Date?) async throws -> Route {
        Self.route(from: from, to: to, departing: departing, scale: scale)
    }

    public func eta(from: Coordinate, to: Coordinate, departing: Date) async throws -> ETA {
        let r = Self.route(from: from, to: to, departing: departing, scale: scale)
        return ETA(seconds: r.seconds, arrival: departing.addingTimeInterval(r.seconds), departing: departing)
    }

    static func route(from: Coordinate, to: Coordinate, departing: Date?, scale: Double) -> Route {
        let meters = from.distance(to: to) * 1.3
        return Route(path: [from, to], seconds: meters / 25 * scale, meters: meters, departing: departing,
                     isTrafficAware: departing != nil)
    }
}

/// A conditions source with fixed answers (previews and tests of screens): never loads anything.
@MainActor
public final class BuildPreviewConditions: BuildConditionsSource {
    public var samples: [SlotKey: ConditionsSample] = [:]

    public struct SlotKey: Hashable, Sendable {
        public var placeID: UUID
        public var day: LocalDay
        public init(placeID: UUID, day: LocalDay) {
            self.placeID = placeID
            self.day = day
        }
    }

    public init() {}
    public func setActiveTrip(_ placeIDs: Set<UUID>) {}
    public func setVisible(_ placeIDs: Set<UUID>) {}
    public func request(_ place: Place, day: LocalDay, priority: ConditionsPriority) {}
    public func sample(placeID: UUID, day: LocalDay) -> ConditionsSample { samples[SlotKey(placeID: placeID, day: day)] ?? .empty }
}

/// `BuildModel`s in fixed states for the screens worker, previews and snapshots: the four-day "Canyon Country" trip (6 stops,
/// 5 drives) on fixed dates with fake drives and scores, in an in-memory library. Nothing here touches the network, the real
/// store or the clock; the models are not opened (no lookups run), so they are complete the moment they are returned.
@MainActor
public enum BuildPreviewData {
    /// What the model shows.
    public enum Variant: Sendable, CaseIterable {
        /// Every drive known (typical and with traffic) and every forecast complete.
        case ready
        /// No drive known yet: estimates, each drive loading.
        case loadingDrives
        /// Every drive failed for a passing reason, waiting to retry.
        case driveFailed
        /// Drives far longer than the sessions allow: "Drive doesn't fit" on the drives and conflicts on the days.
        case driveDoesNotFit
        /// Some stops have a quick score that a better forecast is still improving; the rest have none yet.
        case scoresLoading
        /// A sunset stop listed before a sunrise stop on day 3: the light-first suggestion and an out-of-order warning.
        case backwardsDay
        /// A three-day trip with no stops.
        case empty
    }

    /// The first day of the sample trip (Tuesday, October 6, 2026).
    public nonisolated static let startDay = LocalDay(year: 2026, month: 10, day: 6)
    /// The clock the sample models use: Monday, October 5, 2026, 10:00 in Denver, the day before the trip.
    public nonisolated static let now = Date(timeIntervalSince1970: 1_791_216_000)

    /// The sample trip's model. `selectedDay` is 0-based; `selectedStop` is the 1-based stop number (the map pin's number).
    /// `startPlace` gives the trip a start place ("Salt Lake City") so day 1 has a first leave-by.
    public static func canyonCountry(_ variant: Variant = .ready, selectedDay: Int? = nil, selectedStop: Int? = nil,
                                     startPlace: Bool = false, isSampleData: Bool = false) -> BuildModel {
        let library: LibraryStore
        do {
            library = LibraryStore(container: try IterStoreSchema.makeInMemoryContainer(), clock: { BuildPreviewData.now })
        } catch {
            preconditionFailure("The in-memory preview store did not open: \(error)")
        }
        let record: TripRecord
        if variant == .empty {
            record = library.trips.create(name: "Canyon Country", startDay: startDay, dayCount: 3)
        } else if let template = TripTemplates.template(id: "canyon-country") {
            record = library.trips.create(from: template, startDay: startDay)
        } else {
            preconditionFailure("The Canyon Country template is missing")
        }
        if startPlace {
            let home = library.places.createUserSpot(name: "Salt Lake City", locality: "UT",
                                                     coordinate: Coordinate(latitude: 40.7608, longitude: -111.8910),
                                                     timeZoneIdentifier: "America/Denver")
            library.trips.setStartPlace(record, to: home.id)
        }
        let conditions = BuildPreviewConditions()
        let scale = variant == .driveDoesNotFit ? 30.0 : 1.0
        let model = BuildModel(tripID: record.id, library: library, conditions: conditions, packs: nil,
                               routing: BuildPreviewRouting(scale: scale), now: { BuildPreviewData.now },
                               engine: LightEngine(ephemeris: MemoizedEphemeris.shared), isSampleData: isSampleData)
        if variant == .backwardsDay,
           let delicate = model.stops.first(where: { $0.name == "Delicate Arch" }) {
            model.moveStop(delicate.id, toDay: 2, index: 0)
        }
        fillScores(conditions, model: model, variant: variant)
        model.refreshIfChanged()
        switch variant {
        case .ready, .driveDoesNotFit, .scoresLoading, .backwardsDay, .empty: model.seedDrives(scale: scale, failing: false)
        case .driveFailed: model.seedDrives(scale: scale, failing: true)
        case .loadingDrives: break
        }
        if let selectedDay { model.selectDay(selectedDay) }
        if let selectedStop, let stop = model.stops.first(where: { $0.number == selectedStop }) { model.selectStop(stop.id) }
        return model
    }

    /// The sample scores: the session's own score for each stop, a little lower for its other windows.
    private static let sessionScores: [String: Int] = [
        "Horseshoe Bend": 82, "Monument Valley": 64, "Dead Horse Point": 91, "Mesa Arch": 58, "Delicate Arch": 76, "Goblin Valley": 47,
    ]

    private static func fillScores(_ conditions: BuildPreviewConditions, model: BuildModel, variant: Variant) {
        guard let trip = model.trip else { return }
        var index = 0
        for stop in trip.stops {
            defer { index += 1 }
            let base = sessionScores[stop.place.name] ?? 60
            var scores: [LightWindowKind: Int] = [:]
            for kind in LightWindowKind.allCases { scores[kind] = max(0, base - (kind == stop.session ? 0 : 14 + 3 * kind.hashValueFree)) }
            let key = BuildPreviewConditions.SlotKey(placeID: stop.place.id, day: trip.day(stop.dayIndex))
            switch variant {
            case .scoresLoading:
                // Every other stop has a quick score; the NOAA forecast is still loading for it.
                if index % 2 == 0 { conditions.samples[key] = ConditionsSample(tier: .quick, scores: scores, pendingSources: [.noaaNOMADS]) }
            default:
                conditions.samples[key] = ConditionsSample(tier: .complete, scores: scores)
            }
        }
    }
}

private extension LightWindowKind {
    /// A stable small number per window kind (not `hashValue`, which changes between runs).
    var hashValueFree: Int {
        switch self {
        case .blueMorning: 1
        case .goldenMorning: 2
        case .goldenEvening: 3
        case .blueEvening: 4
        case .night: 5
        }
    }
}

extension BuildModel {
    /// Previews: puts every drive the plan wants in the cache (or marks the typical ones as failed) and recomputes until stable.
    func seedDrives(scale: Double, failing: Bool) {
        for _ in 0..<4 {
            var seeded = false
            for want in pendingWants where fetcher.leg(for: want.key, from: want.from, to: want.to) == nil {
                if failing {
                    guard want.key.bucket == nil else { continue }
                    fetcher.seed(want.key, from: want.from, to: want.to, fetch: .failed(attempt: 0, retryAt: now().addingTimeInterval(30)))
                } else {
                    let route = BuildPreviewRouting.route(from: want.from, to: want.to, departing: want.departing, scale: scale)
                    fetcher.seed(want.key, from: want.from, to: want.to, route: route)
                }
                seeded = true
            }
            if !seeded { break }
            recompute()
        }
    }
}
