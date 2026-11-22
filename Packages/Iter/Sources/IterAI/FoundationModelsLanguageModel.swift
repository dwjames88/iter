import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The on-device adapter (Apple Intelligence, via Foundation Models). The only file that imports the framework besides
/// `FoundationModelsSchema.swift`. Stateless: a fresh session per call. Without the framework every call throws
/// `AIError.unavailable(.frameworkUnavailable)`.
public struct FoundationModelsLanguageModel: LanguageModeling {
    private let isDisabledInSettings: @Sendable () -> Bool

    /// - Parameter isDisabledInSettings: asked on every call; when true the model reports `.disabledInSettings`.
    public init(isDisabledInSettings: @escaping @Sendable () -> Bool = { false }) {
        self.isDisabledInSettings = isDisabledInSettings
    }

    public func availability() async -> AIAvailability {
        if isDisabledInSettings() { return .unavailable(.disabledInSettings) }
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available: return .available
        case .unavailable(let reason): return .unavailable(AIUnavailableReason(reason))
        @unknown default: return .unavailable(.unknown)
        }
        #else
        return .unavailable(.frameworkUnavailable)
        #endif
    }

    public func generate<Output: AIGenerable>(_ type: Output.Type, prompt: AIPrompt, options: AICallOptions) async throws -> Output {
        if case .unavailable(let reason) = await availability() { throw AIError.unavailable(reason) }
        #if canImport(FoundationModels)
        if Task.isCancelled { throw AIError.cancelled }
        let json: Data
        do {
            let schema = try FoundationModelsSchema.generationSchema(for: Output.aiSchema)
            let session = LanguageModelSession(instructions: prompt.instructions)
            let response = try await session.respond(to: prompt.prompt, schema: schema, options: Self.generationOptions(options))
            json = Data(response.content.jsonString.utf8)
        } catch {
            throw Self.map(error)
        }
        return try AISchemaValidation.decode(Output.self, from: json)
        #else
        throw AIError.unavailable(.frameworkUnavailable)
        #endif
    }

    public func respond(prompt: AIPrompt, options: AICallOptions) async throws -> String {
        if case .unavailable(let reason) = await availability() { throw AIError.unavailable(reason) }
        #if canImport(FoundationModels)
        if Task.isCancelled { throw AIError.cancelled }
        do {
            let session = LanguageModelSession(instructions: prompt.instructions)
            let response = try await session.respond(to: prompt.prompt, options: Self.generationOptions(options))
            return response.content
        } catch {
            throw Self.map(error)
        }
        #else
        throw AIError.unavailable(.frameworkUnavailable)
        #endif
    }

    #if canImport(FoundationModels)
    static func generationOptions(_ o: AICallOptions) -> GenerationOptions {
        GenerationOptions(temperature: o.temperature, maximumResponseTokens: o.maxResponseTokens)
    }

    /// Framework errors to `AIError`. Handles the macOS 26 `GenerationError` and the macOS 27 `LanguageModelError`.
    static func map(_ error: any Error) -> AIError {
        if let e = error as? AIError { return e }
        if error is CancellationError || Task.isCancelled { return .cancelled }
        if let e = error as? GenerationSchema.SchemaError { return .generation("schema: \(e.localizedDescription)") }
        if let e = error as? LanguageModelSession.GenerationError {
            switch e {
            case .exceededContextWindowSize: return .contextTooLong
            case .guardrailViolation: return .guardrail(e.localizedDescription)
            case .refusal: return .guardrail(e.localizedDescription)
            case .decodingFailure: return .decoding(e.localizedDescription)
            default: return .generation(e.localizedDescription)
            }
        }
        if #available(macOS 27, iOS 27, *), let e = error as? LanguageModelError {
            switch e {
            case .contextSizeExceeded: return .contextTooLong
            case .guardrailViolation, .refusal: return .guardrail(e.localizedDescription)
            case .timeout: return .timedOut
            default: return .generation(e.localizedDescription)
            }
        }
        return .generation(error.localizedDescription)
    }
    #endif
}

#if canImport(FoundationModels)
extension AIUnavailableReason {
    /// The exact mapping from the framework's reasons; anything new is `.unknown`.
    init(_ reason: SystemLanguageModel.Availability.UnavailableReason) {
        switch reason {
        case .deviceNotEligible: self = .deviceNotEligible
        case .appleIntelligenceNotEnabled: self = .appleIntelligenceNotEnabled
        case .modelNotReady: self = .modelNotReady
        @unknown default: self = .unknown
        }
    }
}
#endif
