import Foundation
import Observation

/// Things the app says once and never again: the iPhone's first-run guide and the "how to move your pin" tip. Each is a
/// persisted "seen" flag in a `UserDefaults` suite the composition root chooses: the standard one in the real app, a throwaway
/// one for in-memory (test, render, screenshot) runs, so those start clean every time and never leave a trace.
@MainActor @Observable
public final class OneTimeNotices {
    public enum Notice: String, CaseIterable, Sendable {
        case firstRunGuide = "IterSeenFirstRunGuide"
        case moveSpotTip = "IterSeenMoveSpotTip"
    }

    @ObservationIgnored private let defaults: UserDefaults
    /// What has been seen, mirrored here so views reading `hasSeen` update when `markSeen` runs.
    private var seen: Set<Notice>

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        seen = Set(Notice.allCases.filter { defaults.bool(forKey: $0.rawValue) })
    }

    /// A throwaway suite (tests, previews, in-memory runs).
    public static func ephemeral() -> OneTimeNotices {
        let name = "iter.notices.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return OneTimeNotices(defaults: d)
    }

    /// The suite for a launch: in-memory runs get a throwaway one so a stale flag cannot hide a screenshot's guide or tip.
    public static func forLaunch(inMemoryStore: Bool) -> OneTimeNotices {
        inMemoryStore ? .ephemeral() : OneTimeNotices(defaults: .standard)
    }

    public func hasSeen(_ notice: Notice) -> Bool { seen.contains(notice) }

    /// Remembers that the notice was shown (and dismissed, or acted on). Idempotent.
    public func markSeen(_ notice: Notice) {
        guard !seen.contains(notice) else { return }
        seen.insert(notice)
        defaults.set(true, forKey: notice.rawValue)
    }

    /// Whether the first-run guide shows at launch. `forced` is `-IterFirstRun YES` (always) or `NO` (never; screenshots and
    /// tests); with neither, an in-memory run never shows it and a real launch shows it until it has been seen.
    public static func shouldShowFirstRun(forced: Bool?, inMemoryStore: Bool, seen: Bool) -> Bool {
        if let forced { return forced }
        return !inMemoryStore && !seen
    }
}
