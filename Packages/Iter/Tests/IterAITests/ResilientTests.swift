import Foundation
import Testing
@testable import IterAI

@Suite struct ResilientTests {
    @Test func timeoutFiresAndIsRetried() async {
        let inner = CountingModel(hang: true)
        let model = ResilientLanguageModel(inner)
        await #expect(throws: AIError.timedOut) {
            try await model.respond(prompt: prompt, options: AICallOptions(timeout: .milliseconds(50), maxAttempts: 3))
        }
        #expect(inner.calls == 3)
    }

    @Test func retryableErrorSucceedsOnSecondAttempt() async throws {
        let inner = CountingModel(failures: [.generation("flaky")])
        let text = try await ResilientLanguageModel(inner).respond(prompt: prompt, options: AICallOptions(maxAttempts: 2))
        #expect(text == "ok")
        #expect(inner.calls == 2)
    }

    @Test(arguments: [AIError.guardrail("no"), .contextTooLong])
    func nonRetryableIsNotRetried(error: AIError) async {
        let inner = CountingModel(failures: [error, error, error])
        await #expect(throws: error) {
            try await ResilientLanguageModel(inner).respond(prompt: prompt, options: AICallOptions(maxAttempts: 3))
        }
        #expect(inner.calls == 1)
    }

    @Test func attemptsAreCapped() async {
        let inner = CountingModel(failures: Array(repeating: .generation("x"), count: 10))
        await #expect(throws: AIError.generation("x")) {
            try await ResilientLanguageModel(inner).respond(prompt: prompt, options: AICallOptions(maxAttempts: 4))
        }
        #expect(inner.calls == 4)
    }

    @Test func cancellationReturnsFastAndIsNotRetried() async {
        let inner = CountingModel(hang: true)
        let model = ResilientLanguageModel(inner)
        let clock = ContinuousClock()
        let start = clock.now
        let task = Task { try await model.respond(prompt: prompt, options: AICallOptions(timeout: .seconds(30), maxAttempts: 3)) }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        let result = await task.result
        #expect(start.duration(to: clock.now) < .seconds(5))
        #expect(throws: AIError.cancelled) { try result.get() }
        #expect(inner.calls == 1)
    }

    @Test func unavailableShortCircuits() async {
        let inner = CountingModel(availability: .unavailable(.modelNotReady))
        let model = ResilientLanguageModel(inner)
        await #expect(throws: AIError.unavailable(.modelNotReady)) { try await model.respond(prompt: prompt, options: .default) }
        await #expect(throws: AIError.unavailable(.modelNotReady)) { try await model.generate(Toy.self, prompt: prompt, options: .default) }
        #expect(inner.calls == 0)
    }

    @Test func wrapsFakeEndToEnd() async throws {
        let fake = FakeLanguageModel()
        fake.enqueue(json: #"{"names":[],"count":99}"#) // out of range: decoding, retryable
        try fake.enqueue(Toy(names: ["a"], count: 2, kind: nil))
        let toy = try await ResilientLanguageModel(fake).generate(Toy.self, prompt: prompt, options: AICallOptions(maxAttempts: 2))
        #expect(toy.count == 2)
        #expect(fake.callCount == 2)
    }
}
