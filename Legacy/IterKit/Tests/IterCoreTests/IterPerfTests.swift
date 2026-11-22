import Testing
@testable import IterCore

@Suite("Perf instrumentation")
struct IterPerfTests {
    @Test("lag bookkeeping counts hitches and the time beyond one frame")
    func lagBookkeeping() {
        var stats = LagStats()
        for ms in [1.0, 4.0, 16.0, 20.0, 60.0, -3.0] { stats.record(ms) }
        #expect(stats.samples == 6)
        #expect(stats.maxMilliseconds == 60)
        #expect(stats.hitches == 2)        // 20 and 60; exactly 16 is within budget
        #expect(stats.longHitches == 1)    // 60
        #expect(abs(stats.blockedMilliseconds - (4 + 44)) < 1e-9)
    }

    @Test("an empty window reports zeros")
    func emptyWindow() {
        let stats = LagStats()
        #expect(stats.samples == 0 && stats.hitches == 0 && stats.maxMilliseconds == 0)
        #expect(stats.summary.contains("h16=0"))
    }
}

@Suite("Step statistics")
struct StepStatsTests {
    @Test("median, p90 and max by nearest rank")
    func percentiles() {
        var s = StepStats()
        for ms in 1...10 { s.record(Double(ms)) }
        #expect(s.count == 10)
        #expect(s.medianMilliseconds == 5)
        #expect(s.p90Milliseconds == 9)
        #expect(s.maxMilliseconds == 10)
    }

    @Test("no samples reports zeros")
    func empty() {
        let s = StepStats()
        #expect(s.medianMilliseconds == 0 && s.p90Milliseconds == 0 && s.maxMilliseconds == 0)
    }
}
