import Foundation
import IterModel
import IterSources
import IterSky
import IterPlan
import IterConditions

// The conditions loop of the trip-mode engine (BLUEPRINT §10.6): decides what is due, fetches it in priority order, and
// folds the answers into one `GoConditionsState` the engine copies into the snapshot.

/// What the loop remembers between runs and relaunches. Inside `GoConditionsState` so persisting that persists this.
public struct ConditionsMemory: Codable, Hashable, Sendable {
    public var tripID: UUID?
    public var cadence: ConditionsCadenceMemory
    public var alertState: ConditionsAlertState
    public var trends: ForecastTrendTracker

    public init(tripID: UUID? = nil, cadence: ConditionsCadenceMemory = ConditionsCadenceMemory(),
                alertState: ConditionsAlertState = ConditionsAlertState(), trends: ForecastTrendTracker = ForecastTrendTracker()) {
        self.tripID = tripID
        self.cadence = cadence
        self.alertState = alertState
        self.trends = trends
    }
}

/// Everything conditions contributes to the Go snapshot. Codable so the engine can persist it across a relaunch.
public struct GoConditionsState: Codable, Hashable, Sendable {
    public var hereLive: LiveConditions?
    public var nextLive: LiveConditions?
    public var nextReport: SkyReport?
    public var sky: GoSkyInfo?
    /// Where you are (first, when known) and at the next stop.
    public var weather: [GoWeatherInfo]
    public var alerts: [GoAlertInfo]
    /// Changes raised by the latest refresh only; the next refresh replaces them.
    public var changes: [ConditionsChange]
    public var packBuiltAt: Date?
    /// Why the last pack build failed, if it did.
    public var packError: String?
    /// The freshest input behind the sky and weather.
    public var conditionsAsOf: Date?
    public var isStale: Bool
    public var isOffline: Bool
    /// When the loop next wants to run.
    public var nextDueAt: Date?
    public var memory: ConditionsMemory

    public init(hereLive: LiveConditions? = nil, nextLive: LiveConditions? = nil, nextReport: SkyReport? = nil, sky: GoSkyInfo? = nil,
                weather: [GoWeatherInfo] = [], alerts: [GoAlertInfo] = [], changes: [ConditionsChange] = [], packBuiltAt: Date? = nil,
                packError: String? = nil, conditionsAsOf: Date? = nil, isStale: Bool = false, isOffline: Bool = false,
                nextDueAt: Date? = nil, memory: ConditionsMemory = ConditionsMemory()) {
        self.hereLive = hereLive
        self.nextLive = nextLive
        self.nextReport = nextReport
        self.sky = sky
        self.weather = weather
        self.alerts = alerts
        self.changes = changes
        self.packBuiltAt = packBuiltAt
        self.packError = packError
        self.conditionsAsOf = conditionsAsOf
        self.isStale = isStale
        self.isOffline = isOffline
        self.nextDueAt = nextDueAt
        self.memory = memory
    }
}

/// What the engine tells the loop each time.
public struct ConditionsContext: Sendable {
    public var trip: Trip?
    public var phase: GoPhase
    public var nextStop: Stop?
    /// The rest of today's stops, including `nextStop` when it is today.
    public var todayRemaining: [Stop]
    public var fix: LocationFix?
    public var power: PowerState

    public init(trip: Trip?, phase: GoPhase, nextStop: Stop?, todayRemaining: [Stop] = [], fix: LocationFix? = nil,
                power: PowerState = .normal) {
        self.trip = trip
        self.phase = phase
        self.nextStop = nextStop
        self.todayRemaining = todayRemaining
        self.fix = fix
        self.power = power
    }
}

public struct ConditionsUpdate: Sendable {
    public var state: GoConditionsState
    /// The items fetched by this call, in the order they ran.
    public var fetched: [ConditionsItem]
    /// Requests sent to the provider by this call (for the request budget).
    public var requestCount: Int
    /// True when another refresh was running, so nothing was fetched.
    public var skipped: Bool

    public init(state: GoConditionsState, fetched: [ConditionsItem] = [], requestCount: Int = 0, skipped: Bool = false) {
        self.state = state
        self.fetched = fetched
        self.requestCount = requestCount
        self.skipped = skipped
    }
}

@MainActor
public final class ConditionsLoop {
    /// Stable id of the synthetic "Here" place.
    public static let herePlaceID = UUID(uuidString: "0F1E2D3C-4B5A-4978-8695-A4B3C2D1E0F9")!

    private let provider: any TripConditionsProviding
    private let clock: any SourceClock
    public private(set) var state = GoConditionsState()
    private var isRefreshing = false
    private var seededTripID: UUID?

    public init(provider: any TripConditionsProviding, clock: any SourceClock) {
        self.provider = provider
        self.clock = clock
    }

    /// Continue from a persisted state (after a relaunch).
    public func restore(_ saved: GoConditionsState) { state = saved }

    /// The synthetic place at the fix, in the next stop's zone.
    public static func herePlace(fix: LocationFix, timeZoneIdentifier: String) -> Place {
        Place(id: herePlaceID, name: "Here", coordinate: fix.coordinate, timeZoneIdentifier: timeZoneIdentifier, category: .landscape,
              origin: .user)
    }

    /// Builds the trip's offline pack. The engine calls it once at run start. A failure is recorded in `state.packError` and a retry
    /// is scheduled; it never throws. Returns the build time, or nil on failure or when a refresh is already running.
    @discardableResult
    public func refreshPack(trip: Trip) async -> Date? {
        guard !isRefreshing else { return nil }
        isRefreshing = true
        defer { isRefreshing = false }
        resetIfNewTrip(trip.id)
        return await buildPack(trip)
    }

    /// Fetches whatever is due, in priority order, and returns the state. A call while another is running returns the current
    /// state without fetching.
    public func refreshIfDue(context: ConditionsContext) async -> ConditionsUpdate {
        guard !isRefreshing else { return ConditionsUpdate(state: state, skipped: true) }
        isRefreshing = true
        defer { isRefreshing = false }

        if let trip = context.trip { resetIfNewTrip(trip.id) }
        guard ConditionsCadence.isActive(context.phase) else {
            state.nextDueAt = nil
            return ConditionsUpdate(state: state)
        }
        await seedPackTime(context.trip)

        let next = context.nextStop
        if state.memory.cadence.nextStopID != next?.id {
            // A different next stop: what we hold is about another place.
            state.nextLive = nil
            state.nextReport = nil
            state.sky = nil
            state.alerts = []
        }

        let now = clock.now
        let due = ConditionsCadence.due(now: now, phase: context.phase, power: context.power, memory: state.memory.cadence,
                                        nextStopID: next?.id, hasTodayStops: !context.todayRemaining.isEmpty, fix: context.fix)
        var fetched: [ConditionsItem] = []
        var requests = 0
        var changes: [ConditionsChange] = []
        var nextFetched = false
        let tz = next?.place.timeZoneIdentifier ?? context.trip?.stops.first?.place.timeZoneIdentifier ?? "UTC"

        for item in due {
            switch item {
            case .hereLive:
                guard let fix = context.fix else { continue }
                state.hereLive = await provider.live(for: Self.herePlace(fix: fix, timeZoneIdentifier: tz), target: nil, priority: .onScreen)
                state.memory.cadence.hereCoordinate = fix.coordinate
                requests += 1
            case .nextLive:
                guard let next else { continue }
                state.nextLive = await provider.live(for: next.place, target: next.session, priority: .onScreen)
                nextFetched = true
                requests += 1
            case .nextForecast:
                guard let next else { continue }
                let report = await provider.report(for: next.place, day: day(of: next, trip: context.trip, now: now), priority: .onScreen)
                state.nextReport = report
                if let score = report.daylight.window(next.session)?.score {
                    state.memory.trends.record(stopID: next.id, kind: next.session, score: score)
                }
                nextFetched = true
                requests += 1
            case .todayForecast:
                for stop in context.todayRemaining where stop.id != next?.id {
                    let report = await provider.report(for: stop.place, day: day(of: stop, trip: context.trip, now: now), priority: .activeTrip)
                    requests += 1
                    if stop.kind == .light, let score = report.daylight.window(stop.session)?.score,
                       let change = ConditionsChangeDetector.observe(state: &state.memory.alertState, stop: stop, score: score, live: nil,
                                                                    now: clock.now) {
                        changes.append(change)
                    }
                }
            case .pack:
                guard let trip = context.trip else { continue }
                _ = await buildPack(trip)
                requests += 1
            }
            if item != .pack { state.memory.cadence.setLastFetch(item, clock.now) }
            fetched.append(item)
        }
        if next != nil, nextFetched || due.contains(.nextLive) { state.memory.cadence.nextStopID = next?.id }
        if next == nil { state.memory.cadence.nextStopID = nil }

        let after = clock.now
        if let next {
            // Resolved when something about the next stop was fetched; otherwise the earlier reading stands (its `asOf` is fixed).
            if nextFetched || state.sky == nil {
                state.sky = SkyReadingResolver.resolve(stop: next, live: state.nextLive, report: state.nextReport,
                                                       history: state.memory.trends, now: after)
            }
            state.alerts = ConditionsWeather.alerts(from: state.nextReport, now: after)
            if nextFetched, next.kind == .light, let score = state.sky?.displayScore, state.sky?.basis != .noData,
               let change = ConditionsChangeDetector.observe(state: &state.memory.alertState, stop: next, score: score,
                                                             live: state.nextLive, now: after) {
                changes.insert(change, at: 0)
            }
        } else {
            state.sky = nil
            state.alerts = []
        }
        state.changes = changes
        state.weather = weather(next: next)
        let live = [state.hereLive, state.nextLive].compactMap { $0 }
        state.isOffline = ConditionsWeather.isOffline(live: live, reports: [state.nextReport].compactMap { $0 })
        let asOf = ([state.nextLive?.generatedAt, state.nextReport?.generatedAt, state.hereLive?.generatedAt]).compactMap { $0 }.max()
        state.conditionsAsOf = asOf
        let staleAfter = 3 * ConditionsCadence.interval(for: .nextLive, power: context.power)
        state.isStale = next != nil && (asOf.map { after.timeIntervalSince($0) > staleAfter } ?? true || state.sky?.isStale == true)
        state.nextDueAt = ConditionsCadence.nextDue(now: after, phase: context.phase, power: context.power, memory: state.memory.cadence,
                                                    nextStopID: next?.id, hasTodayStops: !context.todayRemaining.isEmpty, fix: context.fix)
        return ConditionsUpdate(state: state, fetched: fetched, requestCount: requests)
    }

    // MARK: Private

    private func day(of stop: Stop, trip: Trip?, now: Date) -> LocalDay {
        trip?.day(stop.dayIndex) ?? LocalDay(now, in: stop.place.timeZone)
    }

    private func weather(next: Stop?) -> [GoWeatherInfo] {
        var list: [GoWeatherInfo] = []
        if let here = state.hereLive, let w = ConditionsWeather.info(from: here, subject: .here) { list.append(w) }
        if let next, let live = state.nextLive, let w = ConditionsWeather.info(from: live, subject: .stop(next.id)) { list.append(w) }
        return list
    }

    private func resetIfNewTrip(_ id: UUID) {
        if let current = state.memory.tripID, current != id {
            state = GoConditionsState()
            seededTripID = nil
        }
        state.memory.tripID = id
    }

    /// An existing pack counts as a fetch of the pack item, so a relaunch does not rebuild it at once.
    private func seedPackTime(_ trip: Trip?) async {
        guard let trip, seededTripID != trip.id else { return }
        seededTripID = trip.id
        guard state.memory.cadence.lastFetch(.pack) == nil, let built = await provider.packBuiltAt(tripID: trip.id) else { return }
        state.packBuiltAt = built
        state.memory.cadence.setLastFetch(.pack, built)
    }

    private func buildPack(_ trip: Trip) async -> Date? {
        do {
            let built = try await provider.buildTripPack(for: trip)
            state.packBuiltAt = built
            state.packError = nil
            state.memory.cadence.setLastFetch(.pack, clock.now)
            return built
        } catch {
            state.packError = String(describing: error)
            // Due again after the retry interval, not a whole pack interval.
            let interval = ConditionsCadence.packRetryInterval
            state.memory.cadence.setLastFetch(.pack, clock.now.addingTimeInterval(interval - ConditionsCadence.interval(for: .pack, power: .normal)))
            return nil
        }
    }
}
