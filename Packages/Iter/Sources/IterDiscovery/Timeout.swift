import Foundation

/// Runs `operation` under a deadline. The operation and a timer race inside a task group, so cancelling the caller cancels
/// both, and the loser is cancelled as soon as the winner finishes. Throws `DeadlineExceeded` when the timer wins.
struct DeadlineExceeded: Error {}

func withDeadline<T: Sendable>(_ limit: Duration, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
    try await withThrowingTaskGroup(of: DeadlineResult<T>.self) { group in
        group.addTask { .value(try await operation()) }
        group.addTask {
            try await Task.sleep(for: limit)
            return .expired
        }
        defer { group.cancelAll() }
        guard let first = try await group.next() else { throw CancellationError() }
        switch first {
        case .value(let v): return v
        case .expired: throw DeadlineExceeded()
        }
    }
}

private enum DeadlineResult<T: Sendable>: Sendable {
    case value(T)
    case expired
}
