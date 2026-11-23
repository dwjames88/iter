import Foundation
import IterModel

/// A live ETA the engine holds: what the router said, when, and from where.
public struct GoLiveETA: Codable, Hashable, Sendable {
    public var stopID: UUID
    public var eta: ETA
    public var fetchedAt: Date
    public var origin: Coordinate
    /// Known only when the answer was a full route.
    public var meters: Double?

    public init(stopID: UUID, eta: ETA, fetchedAt: Date, origin: Coordinate, meters: Double? = nil) {
        self.stopID = stopID
        self.eta = eta
        self.fetchedAt = fetchedAt
        self.origin = origin
        self.meters = meters
    }
}

/// What the engine restores after a relaunch besides the store's run (the run, visits and sidecar live in `RunPersisting`).
public struct GoEngineState: Codable, Hashable, Sendable {
    public var ledger: NotificationLedger
    public var conditions: GoConditionsState
    public var lastETA: GoLiveETA?
    public var lastFix: LocationFix?
    /// The route line of the latest route request, for the deviation check.
    public var routePath: [Coordinate]

    public init(ledger: NotificationLedger = NotificationLedger(), conditions: GoConditionsState = GoConditionsState(),
                lastETA: GoLiveETA? = nil, lastFix: LocationFix? = nil, routePath: [Coordinate] = []) {
        self.ledger = ledger
        self.conditions = conditions
        self.lastETA = lastETA
        self.lastFix = lastFix
        self.routePath = routePath
    }
}

public protocol GoEngineStateStoring: Sendable {
    func load(runID: UUID) -> GoEngineState?
    func save(_ state: GoEngineState, runID: UUID)
    func clear(runID: UUID)
}

/// One JSON file per run in `directory` (Application Support in the app). Writes are atomic; reads never throw.
public struct FileEngineStateStore: GoEngineStateStoring {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    public func fileURL(runID: UUID) -> URL { directory.appendingPathComponent("go-engine-\(runID.uuidString).json") }

    public func load(runID: UUID) -> GoEngineState? {
        guard let data = try? Data(contentsOf: fileURL(runID: runID)) else { return nil }
        return try? JSONDecoder().decode(GoEngineState.self, from: data)
    }

    public func save(_ state: GoEngineState, runID: UUID) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: fileURL(runID: runID), options: .atomic)
    }

    public func clear(runID: UUID) { try? FileManager.default.removeItem(at: fileURL(runID: runID)) }
}

public final class InMemoryEngineStateStore: GoEngineStateStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var states: [UUID: GoEngineState] = [:]
    private var _saveCount = 0
    public init() {}
    public var saveCount: Int { lock.withLock { _saveCount } }
    public func load(runID: UUID) -> GoEngineState? { lock.withLock { states[runID] } }
    public func save(_ state: GoEngineState, runID: UUID) { lock.withLock { states[runID] = state; _saveCount += 1 } }
    public func clear(runID: UUID) { lock.withLock { states[runID] = nil } }
}
