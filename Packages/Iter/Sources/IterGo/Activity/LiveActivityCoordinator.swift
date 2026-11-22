import Foundation
import IterGoActivity

/// Drives a `LiveActivityControlling` from snapshots using `GoActivityPolicy`.
@MainActor
public final class LiveActivityCoordinator {
    private let controller: any LiveActivityControlling
    private var lastContent: GoActivityContent?
    private var lastMarker: GoActivityMarker?
    private var lastUpdateAt: Date?
    private var lastStartAttemptAt: Date?
    public private(set) var lastStartError: (any Error)?

    public init(controller: any LiveActivityControlling) { self.controller = controller }

    public func apply(snapshot: GoSnapshot, power: PowerState, now: Date) async {
        var content = GoActivityContent(snapshot: snapshot)
        content.isPowerSaving = content.isPowerSaving || power.isSaving
        let marker = GoActivityMarker(snapshot: snapshot)
        let stale = GoActivityPolicy.staleDate(for: snapshot)

        if snapshot.phase == .idle || GoActivityPolicy.shouldEnd(snapshot) {
            if controller.isActive {
                await controller.end(content, dismissAt: snapshot.phase == .finished ? now.addingTimeInterval(GoActivityPolicy.dismissalDelay) : nil)
            }
            reset()
            return
        }

        guard controller.isActive else {
            lastContent = nil
            lastMarker = nil
            guard controller.areActivitiesEnabled, let tripID = snapshot.tripID, GoActivityPolicy.shouldStart(snapshot, now: now) else { return }
            if let attempt = lastStartAttemptAt, now.timeIntervalSince(attempt) < GoActivityPolicy.updateInterval { return }
            lastStartAttemptAt = now
            do {
                try await controller.start(tripID: tripID, tripName: snapshot.tripName, content: content, staleDate: stale)
                lastStartError = nil
                lastContent = content
                lastMarker = marker
                lastUpdateAt = now
            } catch {
                lastStartError = error
            }
            return
        }

        if content == lastContent { return }
        let due = lastMarker.map {
            GoActivityPolicy.shouldUpdate(previous: $0, current: marker, lastUpdateAt: lastUpdateAt, now: now, powerSaving: content.isPowerSaving)
        } ?? true
        guard due else { return }
        await controller.update(content, staleDate: stale)
        lastContent = content
        lastMarker = marker
        lastUpdateAt = now
    }

    private func reset() {
        lastContent = nil
        lastMarker = nil
        lastUpdateAt = nil
        lastStartAttemptAt = nil
    }
}
