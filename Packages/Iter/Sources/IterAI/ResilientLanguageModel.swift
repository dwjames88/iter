import Foundation

/// Wraps another model with a per-attempt timeout, retries of retryable errors, prompt cancellation and a single
/// availability check per call. The inner model should honour cooperative cancellation (the Foundation Models adapter
/// and `FakeLanguageModel` do); one that does not delays the timeout until it returns.
public struct ResilientLanguageModel: LanguageModeling {
    private let base: any LanguageModeling

    public init(_ base: any LanguageModeling) { self.base = base }

    public func availability() async -> AIAvailability { await base.availability() }

    public func generate<Output: AIGenerable>(_ type: Output.Type, prompt: AIPrompt, options: AICallOptions) async throws -> Output {
        let base = self.base
        return try await run(options) { try await base.generate(type, prompt: prompt, options: options) }
    }

    public func respond(prompt: AIPrompt, options: AICallOptions) async throws -> String {
        let base = self.base
        return try await run(options) { try await base.respond(prompt: prompt, options: options) }
    }

    private func run<T: Sendable>(_ options: AICallOptions, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        if Task.isCancelled { throw AIError.cancelled }
        if case .unavailable(let reason) = await base.availability() { throw AIError.unavailable(reason) }
        var attempt = 0
        while true {
            attempt += 1
            if Task.isCancelled { throw AIError.cancelled }
            do {
                return try await attemptOnce(timeout: options.timeout, operation)
            } catch let error as AIError {
                if Task.isCancelled { throw AIError.cancelled }
                if !error.isRetryable || attempt >= options.maxAttempts { throw error }
            }
        }
    }

    /// One attempt: the operation raced against a timer; the loser is cancelled. Throws `AIError` only.
    private func attemptOnce<T: Sendable>(timeout: Duration, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        do {
            return try await Self.race(timeout: timeout, operation)
        } catch let error as AIError {
            throw error
        } catch is CancellationError {
            throw AIError.cancelled
        } catch {
            throw AIError.generation(error.localizedDescription)
        }
    }

    private static func race<T: Sendable>(timeout: Duration, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: Raced<T>.self) { group in
            group.addTask { .value(try await operation()) }
            group.addTask {
                try await Task.sleep(for: timeout)
                return .timer
            }
            defer { group.cancelAll() }
            guard let first = try await group.next() else { throw AIError.generation("no result") }
            switch first {
            case .value(let v): return v
            case .timer: throw AIError.timedOut
            }
        }
    }

    private enum Raced<T: Sendable>: Sendable {
        case value(T)
        case timer
    }
}
