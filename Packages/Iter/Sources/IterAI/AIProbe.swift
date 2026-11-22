import Foundation

/// Headless availability check for the on-device model.
public enum AIProbe {
    /// Availability, and when available the time one trivial `respond` took.
    public static func describe(model: any LanguageModeling = FoundationModelsLanguageModel()) async -> String {
        let availability = await model.availability()
        guard availability.isAvailable else { return "AI unavailable: \(availability.unavailableReason?.rawValue ?? "unknown")" }
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let text = try await model.respond(prompt: AIPrompt(instructions: "Answer in one word.", prompt: "Say hello."),
                                               options: AICallOptions(timeout: .seconds(60), maxAttempts: 1))
            let elapsed = start.duration(to: clock.now)
            return "AI available; respond took \(elapsed): \"\(text.trimmingCharacters(in: .whitespacesAndNewlines))\""
        } catch {
            return "AI available; respond failed: \(error)"
        }
    }
}
