import Foundation

/// The shell's own launch switches, beside `LaunchOptions` (which owns the contract ones).
///
/// `-IterSmokeQuitAfter N`: once the first window's content has loaded, print `smoke: ready ...` and quit after N seconds
/// (`scripts/smoke-mac.sh` waits for that line). Parsed from the process arguments only, like `LaunchOptions`.
struct SmokeSwitches: Equatable {
    /// Seconds to stay up after the ready line; nil when the switch is absent or not a positive number.
    var quitAfter: Double?

    init(arguments: [String]) {
        guard let i = arguments.firstIndex(of: "-IterSmokeQuitAfter"), i + 1 < arguments.count,
              let seconds = Double(arguments[i + 1]), seconds > 0, seconds.isFinite else {
            quitAfter = nil
            return
        }
        quitAfter = seconds
    }

    static var current: SmokeSwitches { SmokeSwitches(arguments: ProcessInfo.processInfo.arguments) }
}
