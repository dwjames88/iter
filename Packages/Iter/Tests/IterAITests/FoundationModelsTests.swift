import Foundation
import Testing
@testable import IterAI
#if canImport(FoundationModels)
import FoundationModels

@Suite struct FoundationModelsTests {
    @Test func everySchemaCaseConverts() throws {
        let schemas: [AISchema] = [
            .string(), .string(description: "d", choices: ["x", "y"]), .integer(), .integer(range: 1...3), .boolean(),
            .array(of: .string(), maxCount: 4), .array(of: .boolean()),
            .object(name: "O", description: "o", properties: [AIProperty("a", .string(), optional: true)]),
            Toy.aiSchema,
            // Repeated object names and nesting.
            .object(name: "Outer", properties: [
                AIProperty("a", .object(name: "Inner", properties: [AIProperty("v", .integer(range: 0...9))])),
                AIProperty("b", .array(of: .object(name: "Inner", properties: [AIProperty("v", .boolean())]), maxCount: 2)),
                AIProperty("c", .string(choices: ["p"])), AIProperty("d", .string(choices: ["q"])),
            ]),
        ]
        for schema in schemas {
            _ = FoundationModelsSchema.dynamicSchema(for: schema)
            if case .object = schema { _ = try FoundationModelsSchema.generationSchema(for: schema) }
        }
    }

    @Test func reasonMappingIsExhaustive() {
        #expect(AIUnavailableReason(.deviceNotEligible) == .deviceNotEligible)
        #expect(AIUnavailableReason(.appleIntelligenceNotEnabled) == .appleIntelligenceNotEnabled)
        #expect(AIUnavailableReason(.modelNotReady) == .modelNotReady)
    }

    @Test func disabledInSettingsShortCircuits() async {
        let model = FoundationModelsLanguageModel(isDisabledInSettings: { true })
        #expect(await model.availability() == .unavailable(.disabledInSettings))
        await #expect(throws: AIError.unavailable(.disabledInSettings)) { try await model.respond(prompt: prompt, options: .default) }
        await #expect(throws: AIError.unavailable(.disabledInSettings)) { try await model.generate(Toy.self, prompt: prompt, options: .default) }
    }

    @Test func cancellationMapsToCancelled() {
        #expect(FoundationModelsLanguageModel.map(CancellationError()) == .cancelled)
        #expect(FoundationModelsLanguageModel.map(AIError.timedOut) == .timedOut)
    }
}
#endif

@Suite struct LiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["ITER_LIVE_AI"] == "1"))
    func liveModel() async throws {
        print("AIProbe: \(await AIProbe.describe())")
        let model = ResilientLanguageModel(FoundationModelsLanguageModel())
        guard await model.availability().isAvailable else { return }
        let toy = try await model.generate(Toy.self, prompt: AIPrompt(instructions: "Fill the fields.",
            prompt: "Give up to three famous mountain names in names, and set count to how many you gave."),
            options: AICallOptions(timeout: .seconds(60), maxAttempts: 2, temperature: 0.2))
        print("Live generate: \(toy)")
        #expect(toy.names.count <= 3)
    }
}
