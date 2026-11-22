import Foundation

/// The seam over the system notification centre. Real: `UserNotificationScheduler`. Tests: `FakeNotificationScheduler`.
public protocol NotificationScheduling: Sendable {
    /// Schedules `request` (a nil `fireAt` delivers now). The same id replaces.
    func add(_ request: GoNotificationRequest) async throws
    func removePending(ids: [String]) async
    func removeAllPending() async
    func pendingIDs() async -> [String]
    func authorization() async -> NotificationAuthorization
    func requestAuthorization() async -> Bool
    func registerCategories() async
}

/// Records every call, in order. Delivered immediates are kept apart from pending ones.
public final class FakeNotificationScheduler: NotificationScheduling, @unchecked Sendable {
    public enum Call: Hashable, Sendable {
        case add(GoNotificationRequest)
        case removePending([String])
        case removeAllPending
        case requestAuthorization
        case registerCategories
    }

    public struct Failure: Error, Sendable { public init() {} }

    private let lock = NSLock()
    private var _calls: [Call] = []
    private var _pending: [String: GoNotificationRequest] = [:]
    private var _delivered: [GoNotificationRequest] = []
    private var _authorization: NotificationAuthorization
    private var _failingIDs: Set<String> = []

    public init(authorization: NotificationAuthorization = .authorized) { _authorization = authorization }

    public var calls: [Call] { lock.withLock { _calls } }
    /// Future requests currently scheduled, by id.
    public var pending: [String: GoNotificationRequest] { lock.withLock { _pending } }
    /// Requests delivered immediately, in order.
    public var delivered: [GoNotificationRequest] { lock.withLock { _delivered } }
    public var authorizationState: NotificationAuthorization {
        get { lock.withLock { _authorization } }
        set { lock.withLock { _authorization = newValue } }
    }
    /// Ids whose `add` throws.
    public var failingIDs: Set<String> {
        get { lock.withLock { _failingIDs } }
        set { lock.withLock { _failingIDs = newValue } }
    }

    public func add(_ request: GoNotificationRequest) async throws {
        try lock.withLock {
            _calls.append(.add(request))
            if _failingIDs.contains(request.id) { throw Failure() }
            if request.fireAt == nil {
                _delivered.append(request)
            } else {
                _pending[request.id] = request
            }
        }
    }

    public func removePending(ids: [String]) async {
        lock.withLock {
            _calls.append(.removePending(ids))
            for id in ids { _pending[id] = nil }
        }
    }

    public func removeAllPending() async {
        lock.withLock {
            _calls.append(.removeAllPending)
            _pending = [:]
        }
    }

    public func pendingIDs() async -> [String] { lock.withLock { _pending.keys.sorted() } }
    public func authorization() async -> NotificationAuthorization { lock.withLock { _authorization } }

    public func requestAuthorization() async -> Bool {
        lock.withLock {
            _calls.append(.requestAuthorization)
            if _authorization == .notDetermined { _authorization = .authorized }
            return _authorization == .authorized || _authorization == .provisional
        }
    }

    public func registerCategories() async { lock.withLock { _calls.append(.registerCategories) } }
}
