import Foundation
import IterGoActivity

/// The seam over ActivityKit. Real: `ActivityKitController` (iOS). Tests: `FakeLiveActivityController`.
@MainActor
public protocol LiveActivityControlling: AnyObject {
    var areActivitiesEnabled: Bool { get }
    /// An activity of ours is running (not ended).
    var isActive: Bool { get }
    func start(tripID: UUID, tripName: String, content: GoActivityContent, staleDate: Date?) async throws
    func update(_ content: GoActivityContent, staleDate: Date?) async
    /// Ends with a final state; `dismissAt == nil` removes it at once.
    func end(_ content: GoActivityContent, dismissAt: Date?) async
}

/// Records every call with the time the fake's clock gave.
@MainActor
public final class FakeLiveActivityController: LiveActivityControlling {
    public enum Call: Hashable, Sendable {
        case start(tripID: UUID, tripName: String, content: GoActivityContent, staleDate: Date?)
        case update(GoActivityContent, staleDate: Date?)
        case end(GoActivityContent, dismissAt: Date?)
    }

    public struct Failure: Error, Sendable { public init() {} }

    public private(set) var calls: [Call] = []
    public private(set) var callTimes: [Date] = []
    public var areActivitiesEnabled = true
    public private(set) var isActive = false
    public var failNextStart = false
    public var clock: @MainActor () -> Date

    public init(clock: @escaping @MainActor () -> Date = { Date() }) { self.clock = clock }

    public func start(tripID: UUID, tripName: String, content: GoActivityContent, staleDate: Date?) async throws {
        record(.start(tripID: tripID, tripName: tripName, content: content, staleDate: staleDate))
        if failNextStart {
            failNextStart = false
            throw Failure()
        }
        isActive = true
    }

    public func update(_ content: GoActivityContent, staleDate: Date?) async { record(.update(content, staleDate: staleDate)) }

    public func end(_ content: GoActivityContent, dismissAt: Date?) async {
        record(.end(content, dismissAt: dismissAt))
        isActive = false
    }

    private func record(_ call: Call) {
        calls.append(call)
        callTimes.append(clock())
    }
}
