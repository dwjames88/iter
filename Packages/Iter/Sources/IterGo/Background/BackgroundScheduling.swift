import Foundation
#if os(iOS)
import BackgroundTasks
#endif

/// Asks the system for a background refresh. Best effort: iOS decides whether and when it runs (BLUEPRINT §10.6, §11).
/// While driving, the background location session keeps the app alive and no request is needed; otherwise the engine asks
/// for a refresh before each leave-soon time and about every 30 minutes within 2 h of a leave-by.
public protocol BackgroundScheduling: Sendable {
    /// Replaces any pending request. `earliest` is a hint, not a promise.
    func scheduleRefresh(earliest: Date)
    func cancel()
}

public enum GoBackground {
    public static let refreshTaskIdentifier = "com.dwjames.iter.go.refresh"
    /// Within this long of a leave-by the engine asks for a refresh every `nearInterval`.
    public static let nearWindow: TimeInterval = 2 * 3600
    public static let nearInterval: TimeInterval = 30 * 60

    /// When to ask the system to wake the app next, or nil when no refresh is wanted (driving, finished, nothing ahead).
    /// The earliest of: just before the next leave-soon time (leave-by minus 16 min), and, within 2 h of the leave-by, 30 min from now.
    public static func nextRefresh(now: Date, leaveBy: Date?) -> Date? {
        guard let leaveBy else { return nil }
        let untilLeave = leaveBy.timeIntervalSince(now)
        guard untilLeave > 0 else { return nil }
        let beforeSoon = leaveBy.addingTimeInterval(-16 * 60)
        var candidates: [Date] = []
        if beforeSoon > now { candidates.append(beforeSoon) }
        if untilLeave <= nearWindow { candidates.append(now.addingTimeInterval(nearInterval)) }
        guard let earliest = candidates.min() else { return nil }
        // Never asks to wake after the leave-by itself.
        return earliest < leaveBy ? earliest : max(now.addingTimeInterval(60), leaveBy.addingTimeInterval(-60))
    }
}

/// Records requests, for tests.
public final class FakeBackgroundScheduler: BackgroundScheduling, @unchecked Sendable {
    public enum Call: Hashable, Sendable {
        case schedule(Date)
        case cancel
    }
    private let lock = NSLock()
    private var _calls: [Call] = []
    public init() {}
    public var calls: [Call] { lock.withLock { _calls } }
    public var scheduled: [Date] { calls.compactMap { if case .schedule(let d) = $0 { d } else { nil } } }
    public var lastRequest: Date? { scheduled.last }
    public func scheduleRefresh(earliest: Date) { lock.withLock { _calls.append(.schedule(earliest)) } }
    public func cancel() { lock.withLock { _calls.append(.cancel) } }
}

#if os(iOS)
/// `BGTaskScheduler` adapter. The app calls `register(handler:)` once at launch (before the end of
/// `application(_:didFinishLaunching:)`), and lists `GoBackground.refreshTaskIdentifier` in `BGTaskSchedulerPermittedIdentifiers`.
/// iOS decides when (and whether) a refresh runs; nothing here can force it.
public struct BackgroundTaskScheduler: BackgroundScheduling {
    public init() {}

    /// The handler runs the refresh and must call `completion(true/false)` when done. The task's expiration cancels it.
    public static func register(handler: @escaping @Sendable (_ completion: @escaping @Sendable (Bool) -> Void) -> Void) {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: GoBackground.refreshTaskIdentifier, using: nil) { task in
            handler { success in task.setTaskCompleted(success: success) }
        }
    }

    public func scheduleRefresh(earliest: Date) {
        let request = BGAppRefreshTaskRequest(identifier: GoBackground.refreshTaskIdentifier)
        request.earliestBeginDate = earliest
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: GoBackground.refreshTaskIdentifier)
        try? BGTaskScheduler.shared.submit(request)
    }

    public func cancel() { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: GoBackground.refreshTaskIdentifier) }
}
#endif
