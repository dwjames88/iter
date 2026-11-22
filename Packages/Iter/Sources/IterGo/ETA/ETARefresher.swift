import Foundation
import IterModel
import IterSources

/// What the refresher needs to know about the run to decide and to ask.
public struct ETARefreshContext: Sendable {
    public var phase: GoPhase
    public var leaveBy: Date?
    public var remainingDriveSeconds: TimeInterval?
    public var isStationary: Bool
    public var power: PowerState

    public init(phase: GoPhase, leaveBy: Date? = nil, remainingDriveSeconds: TimeInterval? = nil, isStationary: Bool = false,
                power: PowerState = .normal) {
        self.phase = phase
        self.leaveBy = leaveBy
        self.remainingDriveSeconds = remainingDriveSeconds
        self.isStationary = isStationary
        self.power = power
    }
}

public struct ETAOutcome: Hashable, Sendable {
    public enum Result: Hashable, Sendable {
        case eta(ETA)
        case route(Route)
        case failed(SourceError)
    }
    public var stopID: UUID
    public var requestedAt: Date
    public var completedAt: Date
    public var result: Result
    /// The departure the question was asked for.
    public var departing: Date
}

public enum ETARequestKind: String, Hashable, Sendable {
    /// Due by the cadence.
    case scheduled
    /// App foreground or user pull.
    case forced
    /// Route line refresh after a deviation.
    case route
}

public struct ETARequestRecord: Hashable, Sendable {
    public var kind: ETARequestKind
    public var startedAt: Date
    /// nil while in flight, or when the request was cancelled because the target stop changed.
    public var finishedAt: Date?
}

/// Asks the routing provider for the live ETA, one request at a time. `MapKitThrottle` already spaces provider calls;
/// this decides when a call is worth making at all.
@MainActor
public final class ETARefresher {
    public static let minimumForcedSpacing: TimeInterval = 30
    public static let backoffBase: TimeInterval = 60
    public static let backoffCap: TimeInterval = 10 * 60

    public private(set) var latest: ETAOutcome?
    /// True after an `.offline` failure until a request succeeds. The engine computes the offline estimate itself.
    public private(set) var isOffline = false
    public private(set) var backoffUntil: Date?
    public private(set) var requestLog: [ETARequestRecord] = []
    /// The most requests ever in flight at once. Cancelled requests stop counting when cancelled.
    public private(set) var maxConcurrentObserved = 0
    public var isInFlight: Bool { current != nil }

    public let outcomes: AsyncStream<ETAOutcome>
    private let continuation: AsyncStream<ETAOutcome>.Continuation

    private let routing: any RoutingProvider
    private let clock: any SourceClock

    private struct InFlight { var token: UUID; var task: Task<Void, Never>; var logIndex: Int }
    private var current: InFlight?
    private var activeCount = 0
    private var targetStop: UUID?
    private var lastRequestAt: Date?
    private var lastRequestCoordinate: Coordinate?
    private var lastRouteAt: Date?
    private var rateLimitStreak = 0

    public init(routing: any RoutingProvider, clock: any SourceClock) {
        self.routing = routing
        self.clock = clock
        (outcomes, continuation) = AsyncStream.makeStream(of: ETAOutcome.self, bufferingPolicy: .unbounded)
    }

    /// Starts a request when the cadence says one is due and nothing is in flight. Returns whether it started.
    @discardableResult
    public func refreshIfDue(from fix: LocationFix, to stop: (id: UUID, coordinate: Coordinate), context: ETARefreshContext) -> Bool {
        adoptTarget(stop.id)
        guard current == nil else { return false }
        let now = clock.now
        let moved = lastRequestCoordinate.map { fix.coordinate.distance(to: $0) } ?? 0
        let untilLeaveBy = context.leaveBy.map { $0.timeIntervalSince(now) }
        guard let due = ETARefreshPolicy.nextRefresh(
            lastRequestAt: lastRequestAt, now: now, phase: context.phase, untilLeaveBy: untilLeaveBy,
            remainingDriveSeconds: context.remainingDriveSeconds, movedSinceLastRequestM: moved,
            isStationary: context.isStationary, power: context.power, backoffUntil: backoffUntil), due <= now else { return false }
        start(kind: .scheduled, from: fix, to: stop, context: context)
        return true
    }

    /// App came to the foreground or the user pulled to refresh: ask now. Still one in flight at a time, at least
    /// 30 s after the last request, and never inside a rate-limit backoff. Idle, paused and finished never ask.
    @discardableResult
    public func forceRefresh(from fix: LocationFix, to stop: (id: UUID, coordinate: Coordinate), context: ETARefreshContext) -> Bool {
        adoptTarget(stop.id)
        guard current == nil, !blocked(context.phase) else { return false }
        let now = clock.now
        if let last = lastRequestAt, now.timeIntervalSince(last) < Self.minimumForcedSpacing { return false }
        if let backoffUntil, backoffUntil > now { return false }
        start(kind: .forced, from: fix, to: stop, context: context)
        return true
    }

    /// Refreshes the route line (after a deviation of more than 1 km). Same single slot; skipped inside a backoff and
    /// within 30 s of the previous route request.
    @discardableResult
    public func requestRoute(from fix: LocationFix, to stop: (id: UUID, coordinate: Coordinate), context: ETARefreshContext) -> Bool {
        adoptTarget(stop.id)
        guard current == nil, !blocked(context.phase) else { return false }
        let now = clock.now
        if let last = lastRouteAt, now.timeIntervalSince(last) < Self.minimumForcedSpacing { return false }
        if let backoffUntil, backoffUntil > now { return false }
        start(kind: .route, from: fix, to: stop, context: context)
        return true
    }

    /// Drops the in-flight request, if any (its result will be ignored).
    public func cancel() { cancelInFlight() }

    /// Waits for the in-flight request to finish (for tests).
    public func settle() async {
        while let task = current?.task { await task.value }
    }

    // MARK: Internals

    private func blocked(_ phase: GoPhase) -> Bool { phase == .idle || phase == .paused || phase == .finished }

    private func adoptTarget(_ id: UUID) {
        guard targetStop != id else { return }
        // Whatever was asked about the old stop is stale.
        cancelInFlight()
        targetStop = id
        lastRequestAt = nil
        lastRequestCoordinate = nil
    }

    private func cancelInFlight() {
        guard let flight = current else { return }
        flight.task.cancel()
        current = nil
        activeCount -= 1
    }

    private func start(kind: ETARequestKind, from fix: LocationFix, to stop: (id: UUID, coordinate: Coordinate), context: ETARefreshContext) {
        let now = clock.now
        let departing = ETARefreshPolicy.departureDate(now: now, leaveBy: context.leaveBy, phase: context.phase)
        let token = UUID()
        lastRequestAt = now
        lastRequestCoordinate = fix.coordinate
        if kind == .route { lastRouteAt = now }
        requestLog.append(ETARequestRecord(kind: kind, startedAt: now, finishedAt: nil))
        let logIndex = requestLog.count - 1
        activeCount += 1
        maxConcurrentObserved = max(maxConcurrentObserved, activeCount)

        let routing = routing
        let origin = fix.coordinate, destination = stop.coordinate, stopID = stop.id
        let task = Task { [weak self] in
            let result: ETAOutcome.Result
            do {
                switch kind {
                case .route:
                    result = .route(try await routing.route(from: origin, to: destination, departing: departing))
                case .scheduled, .forced:
                    result = .eta(try await routing.eta(from: origin, to: destination, departing: departing))
                }
            } catch let error as SourceError {
                result = .failed(error)
            } catch is CancellationError {
                result = .failed(.cancelled)
            } catch {
                result = .failed(.invalidRequest(String(describing: error)))
            }
            self?.finish(token: token, stopID: stopID, requestedAt: now, departing: departing, result: result)
        }
        current = InFlight(token: token, task: task, logIndex: logIndex)
    }

    private func finish(token: UUID, stopID: UUID, requestedAt: Date, departing: Date, result: ETAOutcome.Result) {
        guard let flight = current, flight.token == token else { return }   // cancelled or superseded
        current = nil
        activeCount -= 1
        let now = clock.now
        requestLog[flight.logIndex].finishedAt = now

        switch result {
        case .eta, .route:
            rateLimitStreak = 0
            backoffUntil = nil
            isOffline = false
        case .failed(.rateLimited(let retryAfter)):
            rateLimitStreak += 1
            let exponential = min(Self.backoffCap, Self.backoffBase * pow(2, Double(rateLimitStreak - 1)))
            var until = now.addingTimeInterval(exponential)
            if let retryAfter, retryAfter > until { until = min(retryAfter, now.addingTimeInterval(Self.backoffCap)) }
            backoffUntil = until
        case .failed(.offline):
            isOffline = true
        case .failed:
            break
        }

        let outcome = ETAOutcome(stopID: stopID, requestedAt: requestedAt, completedAt: now, result: result, departing: departing)
        latest = outcome
        continuation.yield(outcome)
    }
}
