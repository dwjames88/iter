import Foundation
import IterAstro
import IterConditions
import IterGo
import IterModel
import IterPlan
import IterSky
import IterSources
import IterStore
@testable import IterFeatures

/// 2027-01-15 00:00 UTC.
let goT0 = Date(timeIntervalSince1970: 1_799_971_200)
func goH(_ hours: Double) -> Date { goT0.addingTimeInterval(hours * 3600) }

let goOrigin = Coordinate(latitude: 40, longitude: -110)
func goOffset(east: Double) -> Coordinate {
    Coordinate(latitude: goOrigin.latitude, longitude: goOrigin.longitude + east / (111_195 * cos(goOrigin.latitude * .pi / 180)))
}
func goID(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

/// A fake router: every drive takes distance x 1.3 / 25 m/s.
final class GoFakeRouting: RoutingProvider, @unchecked Sendable {
    let descriptor = SourceCatalogue.appleDirections
    private func seconds(_ a: Coordinate, _ b: Coordinate) -> TimeInterval { a.distance(to: b) * 1.3 / 25 }
    func route(from: Coordinate, to: Coordinate, departing: Date?) async throws -> Route {
        Route(path: [from, to], seconds: seconds(from, to), meters: from.distance(to: to) * 1.3, departing: departing, isTrafficAware: true)
    }
    func eta(from: Coordinate, to: Coordinate, departing: Date) async throws -> ETA {
        let s = seconds(from, to)
        return ETA(seconds: s, arrival: departing.addingTimeInterval(s), departing: departing)
    }
}

/// Fake conditions: "no data" everywhere.
final class GoFakeConditions: TripConditionsProviding, @unchecked Sendable {
    let now: @Sendable () -> Date
    init(now: @escaping @Sendable () -> Date) { self.now = now }

    func live(for place: Place, target: LightWindowKind?, priority: ConditionsPriority) async -> LiveConditions {
        let reading = LiveSkyReading(kind: target, window: nil, score: nil, band: nil, forecastScore: nil, trend: .unknown, state: .noData,
                                     age: nil, confidence: .low, isStale: false)
        return LiveConditions(placeID: place.id, generatedAt: now(), reading: reading, current: nil, currentForecastHour: nil, strip: [],
                              notice: nil, nowcast: .none([]), observations: .none([]), forecastTier: .complete, forecastOfflineNote: nil)
    }

    func report(for place: Place, day: LocalDay, priority: ConditionsPriority) async -> SkyReport {
        let at = now()
        let sun = SunEvents(day: day, kind: .normal, solarNoon: at)
        let light = DayLight(day: day, coordinate: place.coordinate, timeZoneIdentifier: place.timeZoneIdentifier, sun: sun,
                             moon: MoonEvents(day: day, rise: nil, set: nil), moonPhase: MoonPhase(illumination: 0.5, cycle: 0.25), windows: [])
        return SkyReport(placeID: place.id, coordinate: place.coordinate, timeZoneIdentifier: place.timeZoneIdentifier, day: day, generatedAt: at,
                         tier: .complete, loading: [], forecast: .none([]), fieldProvenance: [], comparison: nil, forecastTTL: 3600, daylight: light,
                         observations: .none([]), stationReports: .none([]), alerts: .none([]), smoke: SmokeReport(), aurora: .none([]),
                         horizon: .none([]), bortle: nil, seeing: nil, gaps: [], provenanceLines: [], attributionKeys: [], pack: nil,
                         offlineNote: nil)
    }

    func buildTripPack(for trip: Trip) async throws -> Date { now() }
    func packBuiltAt(tripID: UUID) async -> Date? { nil }
}

/// Two light stops east of home, 20 and 40 km out.
struct GoWorld {
    let home: Place
    let stops: [Stop]
    let trip: Trip
    let input: GoTripInput

    init() {
        func place(_ name: String, _ east: Double) -> Place {
            Place(name: name, coordinate: goOffset(east: east), timeZoneIdentifier: "UTC", category: .landscape, origin: .user)
        }
        home = place("Home", 0)
        stops = [Stop(id: goID(1), place: place("S1", 20_000), dayIndex: 0, session: .goldenEvening),
                 Stop(id: goID(2), place: place("S2", 40_000), dayIndex: 0, session: .goldenEvening)]
        trip = Trip(id: goID(100), name: "Go trip", startDay: LocalDay(year: 2027, month: 1, day: 15), dayCount: 1, stops: stops, startPlaceID: home.id)
        let windows: SessionWindows = [stops[0].id: TimeSpan(start: goH(10), end: goH(11)), stops[1].id: TimeSpan(start: goH(17), end: goH(18))]
        var legs: [LegKey: Leg] = [:]
        var prev: (UUID, Coordinate) = (home.id, home.coordinate)
        for s in stops {
            legs[LegKey(prev.0, s.id)] = Leg(from: prev.1, to: s.place.coordinate, seconds: prev.1.distance(to: s.place.coordinate) * 1.3 / 25,
                                            meters: prev.1.distance(to: s.place.coordinate) * 1.3, isEstimate: false, path: [prev.1, s.place.coordinate])
            prev = (s.id, s.place.coordinate)
        }
        input = GoTripInput(trip: trip, start: home, windows: windows, plannedLegs: legs)
    }
}

/// The fakes, a store-backed (or in-memory) persistence and a way to build dependencies on the same set again (a relaunch).
@MainActor
final class GoRig {
    let world = GoWorld()
    let clock = ManualClock(goH(8))
    let location: ScriptedLocation
    let notifications: FakeNotificationScheduler
    let activity: FakeLiveActivityController
    let snapshotStore = InMemorySnapshotStore()
    let reloader = FakeWidgetReloader()
    let engineState = InMemoryEngineStateStore()
    let background = FakeBackgroundScheduler()
    let persistence: any RunPersisting
    let directory: URL
    let store: LibraryStore?

    init(location auth: LocationAuthorization = .always, notifications noteAuth: NotificationAuthorization = .authorized, useStore: Bool = true) throws {
        location = ScriptedLocation(clock: clock, authorization: auth)
        notifications = FakeNotificationScheduler(authorization: noteAuth)
        let c = clock
        activity = FakeLiveActivityController(clock: { c.now })
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("go-tests-\(UUID().uuidString)", isDirectory: true)
        if useStore {
            let s = LibraryStore(container: try IterStoreSchema.makeInMemoryContainer(), clock: { c.now })
            store = s
            persistence = StoreRunPersistence(store: s, directory: directory)
        } else {
            store = nil
            persistence = InMemoryRunPersistence()
        }
    }

    deinit { try? FileManager.default.removeItem(at: directory) }

    func dependencies() -> GoEngineDependencies {
        GoEngineDependencies(clock: clock, routing: GoFakeRouting(), conditions: GoFakeConditions(now: { [clock] in clock.now }), location: location,
                             notifications: notifications, activity: activity, snapshotStore: snapshotStore, widgetReloader: reloader,
                             persistence: persistence, engineState: engineState, power: FixedPower(), background: background)
    }

    func engine() -> GoEngine { GoEngine(dependencies()) }
    func model() -> GoModel { GoModel(dependencies: dependencies(), startsRunLoop: false) }
}
