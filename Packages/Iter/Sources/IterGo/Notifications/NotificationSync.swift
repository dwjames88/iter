import Foundation

/// What one sync did, for tests and logs.
public struct NotificationSyncReport: Hashable, Sendable {
    public var added: [String] = []
    public var removed: [String] = []
    /// Desired and already in place: left alone.
    public var kept: [String] = []
    public var delivered: [String] = []
    public var failed: [String] = []
    public var removedAll = false
    /// Notifications are denied: nothing was scheduled or delivered.
    public var skippedDenied = false
}

/// Applies `NotificationPlan`s to a scheduler by diffing against the ledger it holds. Persist `ledger` with the run.
public actor NotificationSync {
    private let scheduler: any NotificationScheduling
    public private(set) var ledger: NotificationLedger

    public init(scheduler: any NotificationScheduling, ledger: NotificationLedger = NotificationLedger()) {
        self.scheduler = scheduler
        self.ledger = ledger
    }

    /// Plans from `input` against the held ledger, then applies the plan.
    @discardableResult
    public func sync(_ input: NotificationPlanInput) async -> NotificationSyncReport {
        await apply(NotificationPlanner.plan(input, ledger: ledger))
    }

    /// `plan` must have been made from this sync's current ledger.
    @discardableResult
    public func apply(_ plan: NotificationPlan) async -> NotificationSyncReport {
        var report = NotificationSyncReport()
        if await scheduler.authorization() == .denied {
            report.skippedDenied = true
            return report
        }
        var newLedger = plan.ledger

        if plan.removeAll {
            let before = await scheduler.pendingIDs()
            await scheduler.removeAllPending()
            report.removedAll = true
            report.removed = Array(Set(before).union(ledger.scheduled.keys)).sorted()
            ledger = newLedger
            return report
        }

        let inPlace = Set(await scheduler.pendingIDs())
        let desired = Set(plan.pending.map(\.id))
        let known = inPlace.filter { GoNotificationKind.kind(ofID: $0) != nil }.union(ledger.scheduled.keys)
        let stale = known.subtracting(desired).sorted()
        if !stale.isEmpty {
            await scheduler.removePending(ids: stale)
            report.removed = stale
        }

        for request in plan.pending {
            if let before = ledger.scheduled[request.id], before.fireAt == request.fireAt, before.contentHash == request.contentHash,
               inPlace.contains(request.id) {
                report.kept.append(request.id)
                continue
            }
            do {
                try await scheduler.add(request)
                report.added.append(request.id)
            } catch {
                report.failed.append(request.id)
                newLedger.scheduled[request.id] = nil
            }
        }

        for request in plan.immediate {
            do {
                try await scheduler.add(request)
                report.delivered.append(request.id)
            } catch {
                report.failed.append(request.id)
                newLedger.delivered[request.id] = nil
                newLedger.lastImmediateAt = ledger.lastImmediateAt
            }
        }
        ledger = newLedger
        return report
    }
}
