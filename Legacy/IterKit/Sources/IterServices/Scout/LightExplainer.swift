import Foundation
import FoundationModels
import IterCore

public enum LightExplainerError: Error, Sendable, Equatable {
    case unavailable
    /// The window has no score, so there is nothing to explain; the app shows the reason instead.
    case noForecast
    /// The model wrote a number that is not in the facts it was given.
    case ungroundedNumbers
    case failed(String)
}

@Generable
struct Explanation: Equatable {
    @Guide(description: "Two or three calm, plain sentences. Use only the facts given. No hype, no advice about gear, no numbers that are not in the facts.")
    var text: String
}

/// Explains a light score in plain language. Built only from the structured score; the model adds no facts of its own.
public struct LightExplainer: Sendable {
    public init() {}

    public func isAvailable() -> Bool {
        SystemLanguageModel.default.availability == .available
    }

    static let instructions = """
    You explain a photographer's light forecast in two or three calm sentences, using only the facts provided. \
    Do not add any number, time, place or weather condition that is not in the facts. No hype, no exclamation marks.
    """

    static let task = """
    Write the explanation as plain prose in this order: the place and its score with the band; \
    the input that helps most and the input that hurts most, each with its value; then how far to trust the score, from the confidence and range.
    """

    public func explain(spotName: String, window: LightWindow, intentName: String) async throws -> String {
        guard case .scored(let score) = window.assessment else { throw LightExplainerError.noForecast }
        guard isAvailable() else { throw LightExplainerError.unavailable }

        let facts = Self.facts(spotName: spotName, kind: window.kind, intentName: intentName, score: score)
        var lastOutput = ""
        for _ in 0..<2 {
            try Task.checkCancellation()
            do {
                let session = LanguageModelSession(model: .default, instructions: Self.instructions)
                let response = try await session.respond(to: "Facts:\n\(facts)\n\n\(Self.task)", generating: Explanation.self)
                let text = response.content.text.trimmingCharacters(in: .whitespacesAndNewlines)
                lastOutput = text
                if !text.isEmpty, Self.numbersAreGrounded(output: text, facts: facts) { return text }
            } catch {
                guard let mapped = ScoutError.map(error) else { throw CancellationError() }
                throw LightExplainerError.failed(String(describing: mapped))
            }
        }
        _ = lastOutput
        throw LightExplainerError.ungroundedNumbers
    }

    // MARK: Facts

    static func facts(spotName: String, kind: LightWindowKind, intentName: String, score: LightScore) -> String {
        var lines = [
            "Place: \(spotName)",
            "Shooting for: \(intentName)",
            "Window: \(windowLabel(kind))",
            "Score: \(score.value) on a scale from 0 (poor) to 100 (epic)",
            "Band: \(score.band)",
            "Confidence: \(score.confidence.rawValue)",
            "Plausible range: \(score.range.lowerBound) to \(score.range.upperBound)",
            "Forecast lead: about \(Int(score.leadHours.rounded())) hours",
        ]
        if score.contributors.isEmpty {
            lines.append("Inputs: none recorded")
        } else {
            lines.append("Inputs, strongest first:")
            for c in score.contributors {
                let points = c.points == 0 ? "no change" : "\(c.points > 0 ? "plus" : "minus") \(abs(c.points)) points"
                lines.append("- \(factorLabel(c.factor)): \(valueText(c)); \(c.effect.rawValue); \(points)")
            }
        }
        return lines.joined(separator: "\n")
    }

    static func windowLabel(_ kind: LightWindowKind) -> String {
        switch kind {
        case .blueMorning: "blue hour before sunrise"
        case .goldenMorning: "golden hour after sunrise"
        case .goldenEvening: "golden hour before sunset"
        case .blueEvening: "blue hour after sunset"
        case .night: "night"
        }
    }

    static func factorLabel(_ factor: LightContributor.Factor) -> String {
        switch factor {
        case .lowCloud: "low cloud"
        case .midHighCloud: "mid and high cloud"
        case .totalCloud: "total cloud"
        case .clearSky: "clear sky"
        case .precipitation: "chance of rain"
        case .visibility: "visibility"
        case .moonlight: "moonlight"
        case .darkSky: "dark sky"
        case .wind: "wind"
        case .sunAlignment: "sun alignment with the view"
        }
    }

    static func valueText(_ c: LightContributor) -> String {
        switch c.factor {
        case .lowCloud, .midHighCloud, .totalCloud, .clearSky, .precipitation:
            return "\(Int((c.value * 100).rounded())) percent"
        case .moonlight, .darkSky:
            return "\(Int((c.value * 100).rounded())) percent of the moon lit"
        case .visibility:
            return c.value >= 1000 ? "\(Int((c.value / 1000).rounded())) kilometres" : "\(Int(c.value.rounded())) metres"
        case .wind:
            return "\(Int(c.value.rounded())) kilometres per hour"
        case .sunAlignment:
            return "\(Int(c.value.rounded())) degrees apart"
        }
    }

    // MARK: Number check

    /// Every number in `output` must also appear in `facts`.
    static func numbersAreGrounded(output: String, facts: String) -> Bool {
        let allowed = Set(numbers(in: facts))
        return numbers(in: output).allSatisfy(allowed.contains)
    }

    static func numbers(in text: String) -> [String] {
        var result: [String] = []
        var current = ""
        func flush() {
            if !current.isEmpty { result.append(current); current = "" }
        }
        let chars = Array(text)
        for (i, ch) in chars.enumerated() {
            if ch.isNumber, ch.isASCII || ch.wholeNumberValue != nil {
                current.append(ch)
            } else if (ch == "." || ch == ","), !current.isEmpty, i + 1 < chars.count, chars[i + 1].isNumber {
                current.append(".")
            } else {
                flush()
            }
        }
        flush()
        return result
    }
}
