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

    public static func report(_ label: String) {
        let snapshot = counters.withLock { $0 }
        let text = snapshot.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        log.notice("perf counts[\(label, privacy: .public)] t=\(sinceLaunch, privacy: .public)ms \(text, privacy: .public)")
    }

    /// Times `body` as a signpost interval.
    @discardableResult
    public static func interval<T>(_ name: StaticString, _ body: () throws -> T) rethrows -> T {
        let state = signposter.beginInterval(name)
        defer { signposter.endInterval(name, state) }
        return try body()
    }
}
