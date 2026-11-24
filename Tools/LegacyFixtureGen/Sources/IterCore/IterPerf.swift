import Foundation
import os
import Synchronization

/// Performance markers: `os_signpost` points of interest (visible in Instruments) plus a `perf` log line for each
/// milestone with the milliseconds since the process started. Cheap enough to leave on; nothing is user-visible.
///
/// Read them with `log stream --predicate 'subsystem == "com.dwjames.iter" AND category == "perf"'`, or record
/// `xcrun xctrace record --template "Time Profiler" --instrument "Points of Interest" --instrument Hangs`.
public enum IterPerf {
    public static let signposter = OSSignposter(subsystem: "com.dwjames.iter", category: .pointsOfInterest)
    public static let log = Logger(subsystem: "com.dwjames.iter", category: "perf")

    private static let seen = Mutex<Set<String>>([])
    private static let counters = Mutex<[String: Int]>([:])

    /// When this process started (from the kernel), so milestones are measured from launch, not from first use.
    public static let processStart: Date = {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return Date() }
        let tv = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
    }()

    /// Milliseconds since the process started.
    public static var sinceLaunch: Int { Int(Date().timeIntervalSince(processStart) * 1000) }

    /// A milestone, logged every time.
    public static func mark(_ name: StaticString, _ detail: @autoclosure () -> String = "") {
        signposter.emitEvent(name)
        let d = detail()
        log.notice("perf \(String(describing: name), privacy: .public) t=\(sinceLaunch, privacy: .public)ms \(d, privacy: .public)")
    }

    /// A milestone logged only the first time `key` is seen.
    public static func once(_ key: String, _ detail: @autoclosure () -> String = "") {
        let first = seen.withLock { $0.insert(key).inserted }
        guard first else { return }
        signposter.emitEvent("once", "\(key, privacy: .public)")
        let d = detail()
        log.notice("perf once \(key, privacy: .public) t=\(sinceLaunch, privacy: .public)ms \(d, privacy: .public)")
    }

    /// Counts calls (body evaluations, rebuilds); `report()` logs the totals.
    public static func count(_ key: String) {
        counters.withLock { $0[key, default: 0] += 1 }
    }

    /// The current counter totals (tests and scripts that want a number, not a log line).
    public static func counterValues() -> [String: Int] {
        counters.withLock { $0 }
    }

    /// Zeroes every counter (a script that wants the counts for one phase).
    public static func resetCounters() { counters.withLock { $0.removeAll() } }

    /// Logs every counter, and the main-thread lag figures while the monitor runs. `resetLag` starts a fresh lag window
    /// afterwards, so each report covers the work since the previous one.
    public static func report(_ label: String, resetLag: Bool = false) {
        let snapshot = counters.withLock { $0 }
        var text = snapshot.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        if lagMonitorRunning {
            let lag = lagSnapshot()
            text += " lag[\(lag.summary)]"
            if resetLag { resetLagStats() }
        }
        log.notice("perf counts[\(label, privacy: .public)] t=\(sinceLaunch, privacy: .public)ms \(text, privacy: .public)")
    }

    /// Times `body` as a signpost interval.
    @discardableResult
    public static func interval<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try body()
    }

    // MARK: Main-thread lag

    private static let lagStats = Mutex(LagStats())
    private static let lagTimer = Mutex<(any DispatchSourceTimer)?>(nil)
    /// True while a probe block is waiting for the main queue; a new one is posted only once the last has run, so a
    /// long stall is measured once rather than as a pile of late blocks.
    private static let probeInFlight = Mutex(false)

    /// Whether the lag monitor is running.
    public static var lagMonitorRunning: Bool { lagTimer.withLock { $0 != nil } }

    /// True when a development run asked for measurement (`-IterPerfScript YES` or `-IterPerfProbe YES`).
    public static var measurementRequested: Bool {
        UserDefaults.standard.bool(forKey: "IterPerfScript") || UserDefaults.standard.bool(forKey: "IterPerfProbe")
    }

    /// Starts the main-thread lag monitor: a utility-queue timer posts a timestamped block to the main queue every
    /// `interval` and records how late it ran. Idempotent. Nothing calls it in normal use; the perf scripts and
    /// `-IterPerfProbe` do.
    public static func startLagMonitor(interval: Duration = .milliseconds(5)) {
        lagTimer.withLock { timer in
            guard timer == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "com.dwjames.iter.perf.lag", qos: .utility))
            source.schedule(deadline: .now() + .milliseconds(100), repeating: .nanoseconds(Int(interval / .nanoseconds(1))), leeway: .milliseconds(1))
            source.setEventHandler {
                let claimed = probeInFlight.withLock { busy -> Bool in
                    if busy { return false }
                    busy = true
                    return true
                }
                guard claimed else { return }
                let sent = DispatchTime.now().uptimeNanoseconds
                DispatchQueue.main.async {
                    let lateBy = Double(DispatchTime.now().uptimeNanoseconds &- sent) / 1_000_000
                    lagStats.withLock { $0.record(lateBy) }
                    probeInFlight.withLock { $0 = false }
                }
            }
            source.resume()
            timer = source
        }
    }

    /// Starts the monitor when a development run asked for measurement; otherwise does nothing.
    public static func startLagMonitorIfRequested() {
        if measurementRequested { startLagMonitor() }
    }

    public static func lagSnapshot() -> LagStats { lagStats.withLock { $0 } }

    public static func resetLagStats() { lagStats.withLock { $0 = LagStats() } }

    // MARK: Timed interactions

    /// Times one interaction on the main thread: runs `mutation`, then waits for the main queue to turn twice (so
    /// SwiftUI's update pass for it has run) and logs `perf step <name> sync=<ms> settle=<ms>` with a signpost interval.
    /// `sync` is the mutation itself; `settle` is the time until the UI had caught up, which is what a user waits for.
    @MainActor
    public static func step(_ name: String, _ mutation: () -> Void) async {
        let state = signposter.beginInterval("step", "\(name, privacy: .public)")
        let start = ContinuousClock.now
        mutation()
        let synced = ContinuousClock.now
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async { DispatchQueue.main.async { continuation.resume() } }
        }
        let settled = ContinuousClock.now
        signposter.endInterval("step", state)
        let sync = milliseconds(synced - start), settle = milliseconds(settled - start)
        log.notice("perf step \(name, privacy: .public) sync=\(sync, format: .fixed(precision: 1), privacy: .public)ms settle=\(settle, format: .fixed(precision: 1), privacy: .public)ms")
    }

    private static func milliseconds(_ d: Duration) -> Double {
        let c = d.components
        return Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15
    }
}

/// Main-thread lag figures: how late probe blocks ran against the 16 ms frame budget. Pure bookkeeping, so it is tested
/// without a clock.
public struct LagStats: Sendable, Equatable {
    public static let frameMilliseconds = 16.0
    public static let longMilliseconds = 50.0

    public private(set) var samples = 0
    public private(set) var maxMilliseconds = 0.0
    /// Total lag beyond one frame, summed over the samples that were late.
    public private(set) var blockedMilliseconds = 0.0
    /// Samples later than 16 ms (every hitch, long ones included).
    public private(set) var hitches = 0
    /// Samples later than 50 ms.
    public private(set) var longHitches = 0

    public init() {}

    public mutating func record(_ lateByMilliseconds: Double) {
        let ms = max(0, lateByMilliseconds)
        samples += 1
        maxMilliseconds = max(maxMilliseconds, ms)
        if ms > Self.frameMilliseconds {
            hitches += 1
            blockedMilliseconds += ms - Self.frameMilliseconds
        }
        if ms > Self.longMilliseconds { longHitches += 1 }
    }

    public var summary: String {
        "max=\(Self.format(maxMilliseconds))ms blocked=\(Self.format(blockedMilliseconds))ms h16=\(hitches) h50=\(longHitches) n=\(samples)"
    }

    private static func format(_ v: Double) -> String { String(format: "%.1f", v) }
}

/// Per-step durations of a repeated scripted action (the window resize sweep): median, 90th percentile and max, in
/// milliseconds. Pure bookkeeping, so it is tested without a clock.
public struct StepStats: Sendable, Equatable {
    public private(set) var samples: [Double] = []
    public init() {}

    public mutating func record(_ milliseconds: Double) { samples.append(max(0, milliseconds)) }

    public var count: Int { samples.count }
    public var maxMilliseconds: Double { samples.max() ?? 0 }
    public var medianMilliseconds: Double { percentile(0.5) }
    public var p90Milliseconds: Double { percentile(0.9) }

    /// Nearest-rank percentile (`p` in 0...1); 0 for no samples.
    public func percentile(_ p: Double) -> Double {
        guard !samples.isEmpty else { return 0 }
        let sorted = samples.sorted()
        let rank = Int((p * Double(sorted.count)).rounded(.up))
        return sorted[min(sorted.count - 1, max(0, rank - 1))]
    }

    public var summary: String {
        String(format: "n=%d median=%.1fms p90=%.1fms max=%.1fms", count, medianMilliseconds, p90Milliseconds, maxMilliseconds)
    }
}
