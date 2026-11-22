import Testing
import IterAI

// Smoke test: the contract links. The AI worker replaces this file with real tests.
@Test func IterAILinks() {
    #expect(AIAvailability.available.isAvailable)
    #expect(AIError.timedOut.isRetryable)
}
