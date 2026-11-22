import Foundation
import Testing
@testable import IterAI

@Suite struct FakeTests {
    @Test func scriptedValueDecodesAndIsRecorded() async throws {
        let fake = FakeLanguageModel()
        try fake.script(Toy(names: ["a", "b"], count: 2, kind: "a"))
        let opts = AICallOptions(temperature: 0.1)
        let toy = try await fake.generate(Toy.self, prompt: prompt, options: opts)
        #expect(toy == Toy(names: ["a", "b"], count: 2, kind: "a"))
        #expect(fake.calls == [FakeLanguageModelCall(kind: .generate, typeName: "Toy", prompt: prompt, options: opts)])
    }

    @Test func queueBeatsScriptAndHandlerIsLast() async throws {
        let fake = FakeLanguageModel(generateHandler: { name, _ in Data(#"{"names":["h"],"count":1}"#.utf8) },
                                     respondHandler: { $0.prompt + "!" })
        try fake.enqueue(Toy(names: ["q"], count: 0, kind: nil))
        #expect(try await fake.generate(Toy.self, prompt: prompt, options: .default).names == ["q"])
        #expect(try await fake.generate(Toy.self, prompt: prompt, options: .default).names == ["h"])
        #expect(try await fake.respond(prompt: prompt, options: .default) == "go!")
        fake.enqueue(text: "queued")
        #expect(try await fake.respond(prompt: prompt, options: .default) == "queued")
        #expect(fake.calls.map(\.kind) == [.generate, .generate, .respond, .respond])
    }

    @Test(arguments: [#"{"names":[],"count":11}"#, #"{"names":["a","b","c","d"],"count":1}"#, #"{"names":[]}"#,
                      #"{"names":[],"count":1,"kind":"z"}"#, #"{"names":[],"count":1.5}"#])
    func outOfSchemaFailsWithDecoding(json: String) async {
        let fake = FakeLanguageModel()
        fake.enqueue(json: json)
        do { _ = try await fake.generate(Toy.self, prompt: prompt, options: .default); Issue.record("should throw") }
        catch let AIError.decoding(_) {} catch { Issue.record("wrong error \(error)") }
    }

    @Test func unscriptedAndErrorsAndAvailability() async {
        let fake = FakeLanguageModel(availability: .unavailable(.deviceNotEligible))
        #expect(await fake.availability() == .unavailable(.deviceNotEligible))
        fake.setAvailability(.available)
        fake.enqueue(error: .guardrail("blocked"))
        await #expect(throws: AIError.guardrail("blocked")) { try await fake.respond(prompt: prompt, options: .default) }
        await #expect(throws: AIError.self) { try await fake.generate(Toy.self, prompt: prompt, options: .default) }
    }

    @Test func delayHonoursCancellation() async {
        let fake = FakeLanguageModel(delay: .seconds(30))
        fake.enqueue(text: "late")
        let task = Task { try await fake.respond(prompt: prompt, options: .default) }
        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        let result = await task.result
        #expect(throws: AIError.cancelled) { try result.get() }
    }
}
