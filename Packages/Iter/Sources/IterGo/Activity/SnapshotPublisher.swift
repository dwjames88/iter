import Foundation
import IterGoActivity
#if canImport(WidgetKit) && os(iOS)
import WidgetKit
#endif

/// Reloads widget timelines. WidgetKit budgets reloads, so callers reload only when something visible changed.
public protocol WidgetReloading: Sendable {
    func reloadTimelines(ofKind kind: String)
}

#if canImport(WidgetKit) && os(iOS)
public struct WidgetKitReloader: WidgetReloading {
    public init() {}
    public func reloadTimelines(ofKind kind: String) { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
}
#endif

public final class FakeWidgetReloader: WidgetReloading, @unchecked Sendable {
    private let lock = NSLock()
    private var kinds: [String] = []
    public init() {}
    public var reloadedKinds: [String] { lock.withLock { kinds } }
    public func reloadTimelines(ofKind kind: String) { lock.withLock { kinds.append(kind) } }
}

/// Writes every snapshot to the App Group store; reloads the widget only when the phase, the next stop or the leave-by (to the
/// minute) changed.
@MainActor
public final class SnapshotPublisher {
    public static let widgetKind = "IterGoNext"

    private struct Shown: Equatable {
        var phase: GoPhase
        var nextStopID: UUID?
        var leaveByMinute: Int?
    }

    private let store: any GoSnapshotStoring
    private let reloader: any WidgetReloading
    private var shown: Shown?
    public private(set) var lastWriteError: (any Error)?

    public init(store: any GoSnapshotStoring, reloader: any WidgetReloading) {
        self.store = store
        self.reloader = reloader
    }

    /// Returns whether the widget timelines were reloaded.
    @discardableResult
    public func publish(_ snapshot: GoSnapshot) -> Bool {
        do {
            try store.write(snapshot)
            lastWriteError = nil
        } catch {
            lastWriteError = error
            return false
        }
        let now = Shown(phase: snapshot.phase, nextStopID: snapshot.next?.id,
                        leaveByMinute: snapshot.leave?.leaveBy.map { Int(($0.timeIntervalSince1970 / 60).rounded(.down)) })
        guard now != shown else { return false }
        shown = now
        reloader.reloadTimelines(ofKind: Self.widgetKind)
        return true
    }
}
