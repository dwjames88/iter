import Foundation

// The contract every AI use in Iter goes through (BLUEPRINT §3, §7). Callers never import FoundationModels: they describe
// the shape they want with `AISchema`, and an adapter (the on-device model, or a fake in tests) fills it.
//
// Grounding rule, enforced by the type system: `AISchema` has no floating-point type, so no structured answer can carry a
// latitude, longitude or any other measured number. Places the model names are only names; coordinates come from map
// sources (IterDiscovery verifies every one).

/// Why the on-device model cannot be used, specifically enough for the UI to say so.
public enum AIUnavailableReason: String, Codable, Sendable, Hashable, CaseIterable {
    /// The hardware cannot run Apple Intelligence.
    case deviceNotEligible
    /// Apple Intelligence is switched off in Settings.
    case appleIntelligenceNotEnabled
    /// The model is still downloading or preparing.
    case modelNotReady
    /// The OS or SDK has no Foundation Models framework (older OS, or the framework is not present at run time).
    case frameworkUnavailable
    /// The user turned AI off inside Iter.
    case disabledInSettings
    /// The framework reported a reason this build does not know.
    case unknown
}

public enum AIAvailability: Sendable, Hashable {
    case available
    case unavailable(AIUnavailableReason)

    public var isAvailable: Bool { self == .available }

    public var unavailableReason: AIUnavailableReason? {
        if case .unavailable(let r) = self { return r }
        return nil
    }
}

/// A small schema language for structured answers. Deliberately has no floating-point case (see the grounding rule).
public indirect enum AISchema: Sendable, Hashable {
    /// Text; `choices` makes it an enumeration the model must pick from.
    case string(description: String? = nil, choices: [String]? = nil)
    case integer(description: String? = nil, range: ClosedRange<Int>? = nil)
    case boolean(description: String? = nil)
    case array(of: AISchema, description: String? = nil, maxCount: Int? = nil)
    case object(name: String, description: String? = nil, properties: [AIProperty])
}

public struct AIProperty: Sendable, Hashable {
    public var name: String
    public var description: String?
    public var schema: AISchema
    public var isOptional: Bool

    public init(_ name: String, _ schema: AISchema, description: String? = nil, optional: Bool = false) {
        self.name = name
        self.schema = schema
        self.description = description
        self.isOptional = optional
    }
}

/// A type a structured call can produce: decodable from the JSON the schema describes. `aiSchema` must be `.object`,
/// and its property names must match the type's coding keys.
public protocol AIGenerable: Codable, Sendable {
    static var aiSchema: AISchema { get }
}

public struct AIPrompt: Sendable, Hashable {
    /// The system-style instructions (role, rules).
    public var instructions: String
    /// The user turn (the task and its data).
    public var prompt: String

    public init(instructions: String, prompt: String) {
        self.instructions = instructions
        self.prompt = prompt
    }
}

public struct AICallOptions: Sendable, Hashable {
    /// Per attempt.
    public var timeout: Duration
    /// Attempts in total (1 = no retry). Only retryable errors are retried.
    public var maxAttempts: Int
    /// nil = the framework default. Lower is more deterministic.
    public var temperature: Double?
    public var maxResponseTokens: Int?

    public init(timeout: Duration = .seconds(30), maxAttempts: Int = 2, temperature: Double? = nil, maxResponseTokens: Int? = nil) {
        self.timeout = timeout
        self.maxAttempts = max(1, maxAttempts)
        self.temperature = temperature
        self.maxResponseTokens = maxResponseTokens
    }

    public static let `default` = AICallOptions()
}

public enum AIError: Error, Sendable, Hashable, CustomStringConvertible {
    case unavailable(AIUnavailableReason)
    case timedOut
    case cancelled
    /// The prompt plus answer exceed the context window.
    case contextTooLong
    /// The framework's safety guardrails refused the content.
    case guardrail(String)
    /// The answer could not be decoded into the requested type.
    case decoding(String)
    /// Any other generation failure.
    case generation(String)

    /// Worth one more attempt: timeouts, decoding and generic generation failures.
    public var isRetryable: Bool {
        switch self {
        case .timedOut, .decoding, .generation: true
        case .unavailable, .cancelled, .contextTooLong, .guardrail: false
        }
    }

    public var description: String {
        switch self {
        case .unavailable(let r): "AI unavailable (\(r.rawValue))"
        case .timedOut: "AI timed out"
        case .cancelled: "AI call cancelled"
        case .contextTooLong: "AI context too long"
        case .guardrail(let s): "AI guardrail: \(s)"
        case .decoding(let s): "AI answer unreadable: \(s)"
        case .generation(let s): "AI generation failed: \(s)"
        }
    }
}

/// The one door to a language model. Implementations: the on-device Foundation Models adapter, `ResilientLanguageModel`
/// (timeout, retry, cancellation around another model) and fakes. Every method throws `AIError` only.
public protocol LanguageModeling: Sendable {
    func availability() async -> AIAvailability
    /// One structured answer of type `Output`.
    func generate<Output: AIGenerable>(_ type: Output.Type, prompt: AIPrompt, options: AICallOptions) async throws -> Output
    /// Free text (short explanations).
    func respond(prompt: AIPrompt, options: AICallOptions) async throws -> String
}
