import Foundation

/// Runs the last of a burst of actions once the burst has been quiet for `delay`. A live window resize reports a new size
/// every frame; work that only matters for the size the window settles at (re-framing a map) goes through this, so it
/// runs once, not once per frame. A reference type on purpose: held in `@State`, scheduling does not invalidate a view.
@MainActor
public final class TrailingDebouncer {
    public let delay: Duration
    private var task: Task<Void, Never>?
    /// How many actions have actually run (tests and perf counters).
    public private(set) var fired = 0

    public init(delay: Duration) { self.delay = delay }

    /// Replaces any pending action with `action`, to run after `delay` with no further call.
    public func schedule(_ action: @escaping @MainActor () -> Void) {
        task?.cancel()
        let delay = delay
        task = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.fired += 1
            action()
        }
    }

    public func cancel() { task?.cancel(); task = nil }
}
