import Foundation
import FoundationModels
import IterCore

/// Why a scout run produced nothing. Structured, never user-facing text: the app phrases each case.
public enum ScoutError: Error, Sendable, Equatable {
    case unavailable(ScoutAvailability)
    /// The tools found nothing, or the model picked nothing that could be grounded.
    case noResults
    /// The on-device model's safety guardrails blocked the request or the answer.
    case guardrail
    case contextTooLong
    case unsupportedLanguage
    case failed(String)
}

extension ScoutError {
    /// Maps whatever the Foundation Models framework threw. Returns nil for cancellation, which callers rethrow as is.
    static func map(_ error: any Error) -> ScoutError? {
        if error is CancellationError { return nil }
        if let known = error as? ScoutError { return known }

        // A tool that threw is wrapped; look through it (a cancelled tool is a cancelled run).
        if let wrapped = error as? LanguageModelSession.ToolCallError {
            return map(wrapped.underlyingError)
        }

        if #available(macOS 27.0, iOS 27.0, *), let e = error as? LanguageModelError {
            switch e {
            case .contextSizeExceeded: return .contextTooLong
            case .guardrailViolation, .refusal: return .guardrail
            case .unsupportedLanguageOrLocale: return .unsupportedLanguage
            default: return .failed(e.localizedDescription)
            }
        }

        // `GenerationError` is deprecated from macOS 27 but is what macOS 26 throws.
        if let e = error as? LanguageModelSession.GenerationError {
            switch e {
            case .exceededContextWindowSize: return .contextTooLong
            case .guardrailViolation, .refusal: return .guardrail
            case .unsupportedLanguageOrLocale: return .unsupportedLanguage
            case .assetsUnavailable: return .unavailable(.modelNotReady)
            default: return .failed(e.localizedDescription)
            }
        }
        // Unknown type: keep the type name so a new framework error is diagnosable from logs.
        return .failed("\(type(of: error)): \(error.localizedDescription)")
    }
}

/// Maps the framework's availability to the app's. Pure, so it can be tested without the device state.
enum ScoutAvailabilityMapping {
    static func map(_ availability: SystemLanguageModel.Availability) -> ScoutAvailability {
        switch availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .deviceNotEligible
            case .appleIntelligenceNotEnabled: return .appleIntelligenceNotEnabled
            case .modelNotReady: return .modelNotReady
            @unknown default: return .unavailable(String(describing: reason))
            }
        }
    }
}
