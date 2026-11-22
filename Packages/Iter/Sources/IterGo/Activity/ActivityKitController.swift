#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation
import IterGoActivity

/// The real adapter over ActivityKit. Local updates only (`pushType: nil`): there is no push on a free Personal Team.
/// `Activity` is not Sendable, so this type never holds one across an await: each call finds the running activity itself.
@MainActor
public final class ActivityKitController: LiveActivityControlling {
    public init() {}

    public var areActivitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    public var isActive: Bool { !Self.running().isEmpty }

    public func start(tripID: UUID, tripName: String, content: GoActivityContent, staleDate: Date?) async throws {
        _ = try Activity.request(attributes: GoActivityAttributes(tripID: tripID, tripName: tripName),
                                 content: ActivityContent(state: content, staleDate: staleDate), pushType: nil)
    }

    public func update(_ content: GoActivityContent, staleDate: Date?) async {
        await Self.updateAll(ActivityContent(state: content, staleDate: staleDate))
    }

    public func end(_ content: GoActivityContent, dismissAt: Date?) async {
        let policy: ActivityUIDismissalPolicy = dismissAt.map { .after($0) } ?? .immediate
        await Self.endAll(ActivityContent(state: content, staleDate: nil), policy)
    }

    private nonisolated static func running() -> [Activity<GoActivityAttributes>] {
        Activity<GoActivityAttributes>.activities.filter { $0.activityState == .active || $0.activityState == .stale }
    }

    private nonisolated static func updateAll(_ content: ActivityContent<GoActivityContent>) async {
        for activity in running() { await activity.update(content) }
    }

    private nonisolated static func endAll(_ content: ActivityContent<GoActivityContent>, _ policy: ActivityUIDismissalPolicy) async {
        for activity in running() { await activity.end(content, dismissalPolicy: policy) }
    }
}
#endif
