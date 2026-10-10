import Testing
@testable import IterCore

@Suite("Trailing debouncer")
@MainActor
struct TrailingDebouncerTests {
    @Test("a burst of 50 calls runs only the last one, once")
    func burst() async {
        let d = TrailingDebouncer(delay: .milliseconds(40))
        var seen: [Int] = []
        for i in 0..<50 { d.schedule { seen.append(i) }; await Task.yield() }
        #expect(seen.isEmpty)
        try? await Task.sleep(for: .milliseconds(200))
        #expect(seen == [49])
        #expect(d.fired == 1)
    }

    @Test("a cancelled action never runs")
    func cancelled() async {
        let d = TrailingDebouncer(delay: .milliseconds(20))
        var ran = false
        d.schedule { ran = true }
        d.cancel()
        try? await Task.sleep(for: .milliseconds(100))
        #expect(!ran && d.fired == 0)
    }

    @Test("calls spaced further apart than the delay each run")
    func spaced() async {
        let d = TrailingDebouncer(delay: .milliseconds(20))
        var n = 0
        d.schedule { n += 1 }
        try? await Task.sleep(for: .milliseconds(100))
        d.schedule { n += 1 }
        try? await Task.sleep(for: .milliseconds(100))
        #expect(n == 2)
    }
}
