import Foundation
import IterCore
import Testing
@testable import IterServices

enum ExplainerFixture {
    static func window(scored: Bool = true) -> LightWindow {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let span = TimeSpan(start: start, end: start.addingTimeInterval(3600))
        guard scored else { return LightWindow(kind: .goldenEvening, span: span, assessment: .noForecast(.beyondHorizon)) }
        let score = LightScore(
            value: 74, band: .great, confidence: .medium, range: 62...84,
            contributors: [
                LightContributor(factor: .midHighCloud, effect: .helps, points: 12, value: 0.45),
                LightContributor(factor: .lowCloud, effect: .hurts, points: -6, value: 0.3),
                LightContributor(factor: .visibility, effect: .neutral, points: 0, value: 24_000),
            ],
            source: .appleWeather, forecastFetchedAt: start.addingTimeInterval(-3 * 86400), leadHours: 72)
        return LightWindow(kind: .goldenEvening, span: span, assessment: .scored(score))
    }
}

@Suite("Light explainer")
struct LightExplainerTests {
    let facts = LightExplainer.facts(spotName: "Mesa Arch", kind: .goldenEvening, intentName: "Sunset",
                                     score: ExplainerFixture.window().assessment.lightScore!)

    @Test func factsCarryTheStructuredScore() {
        #expect(facts.contains("Score: 74"))
        #expect(facts.contains("62 to 84"))
        #expect(facts.contains("Confidence: medium"))
        #expect(facts.contains("mid and high cloud: 45 percent; helps; plus 12 points"))
        #expect(facts.contains("low cloud: 30 percent; hurts; minus 6 points"))
        #expect(facts.contains("24 kilometres"))
    }

    @Test func numbersInFactsPass() {
        let text = "A score of 74 sits in the great band, with a plausible range of 62 to 84. Mid and high cloud at 45 percent helps."
        #expect(LightExplainer.numbersAreGrounded(output: text, facts: facts))
    }

    @Test func inventedNumbersFail() {
        #expect(!LightExplainer.numbersAreGrounded(output: "Expect 18 degrees and a score of 74.", facts: facts))
        #expect(!LightExplainer.numbersAreGrounded(output: "A score of 75.", facts: facts))
        #expect(!LightExplainer.numbersAreGrounded(output: "Sunset at 7:42.", facts: facts))
    }

    @Test func textWithoutNumbersPasses() {
        #expect(LightExplainer.numbersAreGrounded(output: "Thin high cloud should catch the colour. Trust it moderately.", facts: facts))
    }

    @Test func numberExtraction() {
        #expect(LightExplainer.numbers(in: "74/100, 2.5 km, 1,5 and v2") == ["74", "100", "2.5", "1.5", "2"])
    }

    @Test func noForecastWindowThrowsWithoutTouchingTheModel() async {
        await #expect(throws: LightExplainerError.noForecast) {
            _ = try await LightExplainer().explain(spotName: "X", window: ExplainerFixture.window(scored: false), intentName: "Sunset")
        }
    }
}
