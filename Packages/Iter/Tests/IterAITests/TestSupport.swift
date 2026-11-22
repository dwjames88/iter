import Foundation
import IterAI

struct Toy: AIGenerable, Equatable {
    var names: [String]
    var count: Int
    var kind: String?
    static let aiSchema = AISchema.object(name: "Toy", description: "A toy", properties: [
        AIProperty("names", .array(of: .string(description: "a name"), maxCount: 3)),
        AIProperty("count", .integer(range: 0...10)),
        AIProperty("kind", .string(choices: ["a", "b"]), optional: true),
    ])
}

let prompt = AIPrompt(instructions: "be brief", prompt: "go")

/// A model that fails a scripted number of times, counting attempts.
final class CountingModel: LanguageModeling {
    private let lock = NSLock()
    private nonisolated(unsafe) var _calls = 0
    let failures: [AIError]
    let availabilityValue: AIAvailability
    let hang: Bool
    init(failures: [AIError] = [], availability: AIAvailability = .available, hang: Bool = false) {
        self.failures = failures; self.availabilityValue = availability; self.hang = hang
    }
    var calls: Int { lock.withLock { _calls } }
    func availability() async -> AIAvailability { availabilityValue }
    private func step() async throws {
        let n = lock.withLock { _calls += 1; return _calls }
        if hang { try await Task.sleep(for: .seconds(60)) }
        if n <= failures.count { throw failures[n - 1] }
    }
    func generate<Output: AIGenerable>(_ type: Output.Type, prompt: AIPrompt, options: AICallOptions) async throws -> Output {
        try await step()
        throw AIError.generation("unreachable in tests")
    }
    func respond(prompt: AIPrompt, options: AICallOptions) async throws -> String {
        try await step()
        return "ok"
    }
}
