import Foundation
import Testing
import IterSourcesLive

// Truncated, corrupted and junk input must produce typed errors (or a clean partial decode), never a crash.

/// Deterministic generator so failures reproduce.
private struct LCG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

private func parse(_ bytes: [UInt8]) -> Result<GRIB2File, GRIB2Error> {
    do throws(GRIB2Error) { return .success(try GRIB2File(data: Data(bytes))) } catch { return .failure(error) }
}

private func err(_ bytes: [UInt8]) -> GRIB2Error? {
    if case .failure(let e) = parse(bytes) { return e }
    return nil
}

@Suite struct GRIB2RobustnessTests {
    @Test func truncationAtEveryOffsetThrows() throws {
        for name in ["hrrr-W-20261122t12z-f06", "gfs-S-20261122t06z-f006"] {
            let full = [UInt8](try GRIB2Fixtures.data(name))
            let whole = try GRIB2File(data: Data(full))
            let boundaries = Set(whole.messageOffsets.dropFirst())
            for cut in 0..<full.count {
                let result = parse(Array(full[0..<cut]))
                if boundaries.contains(cut) {
                    guard case .success(let f) = result else { Issue.record("\(name): cut at message boundary \(cut) threw"); continue }
                    #expect(f.messageOffsets.count == boundaries.filter { $0 <= cut }.count)
                } else if case .success = result {
                    Issue.record("\(name): truncation at \(cut) of \(full.count) did not throw")
                }
            }
        }
    }

    @Test func truncationOfEveryFixtureOnASample() throws {
        for name in GRIB2Fixtures.all {
            let full = [UInt8](try GRIB2Fixtures.data(name))
            let offsets = whole(full)
            for cut in stride(from: 1, to: full.count, by: 11) where !offsets.contains(cut) {
                if case .success = parse(Array(full[0..<cut])) { Issue.record("\(name): truncation at \(cut) did not throw") }
            }
        }
    }

    private func whole(_ full: [UInt8]) -> Set<Int> {
        guard case .success(let f) = parse(full) else { return [] }
        return Set(f.messageOffsets)
    }

    @Test func bitFlipsNeverCrash() throws {
        var rng = LCG(state: 42)
        for name in ["hrrr-W-20261122t12z-f01", "gfs-W-20261122t06z-f003"] {
            let full = [UInt8](try GRIB2Fixtures.data(name))
            for _ in 0..<3000 {
                var bytes = full
                for _ in 0..<Int.random(in: 1...3, using: &rng) {
                    bytes[Int.random(in: 0..<bytes.count, using: &rng)] ^= UInt8(1 << Int.random(in: 0..<8, using: &rng))
                }
                if case .success(let f) = parse(bytes) {
                    for field in f.fields { _ = field.value(atLat: 36.5, lon: -118.3); _ = field.nearestIndex(lat: 47, lon: 8.5) }
                }
            }
        }
    }

    @Test func garbageNeverCrashes() {
        var rng = LCG(state: 7)
        #expect(err([]) == .badMagic(offset: 0))
        #expect(err(Array("not a grib file".utf8)) == .badMagic(offset: 0))
        for _ in 0..<2000 {
            var bytes = (0..<Int.random(in: 0..<400, using: &rng)).map { _ in UInt8.random(in: 0...255, using: &rng) }
            if Bool.random(using: &rng), bytes.count > 20 { bytes.replaceSubrange(0..<4, with: Array("GRIB".utf8)) }
            if Bool.random(using: &rng), bytes.count > 20 { bytes[7] = 2 }
            _ = parse(bytes)
        }
    }

    @Test func headerErrorsAreTyped() throws {
        let good = [UInt8](try GRIB2Fixtures.data("gfs-S-20261122t06z-f006"))
        var edition1 = good; edition1[7] = 1
        #expect(err(edition1) == .unsupportedEdition(1))
        var noEnd = good; noEnd[noEnd.count - 1] = 0x38
        #expect(err(noEnd) == .missingEndMarker(offset: good.count - 4))
        var hugeLength = good; for i in 8..<16 { hugeLength[i] = 0xFF }
        #expect(err(hugeLength) == .sectionLengthOutOfRange(section: 0, length: Int.max))
        var badSection = good; badSection[16] = 0xFF  // section 1 length far past the message
        if case .failure(let e) = parse(badSection), case .sectionLengthOutOfRange(let s, _) = e { #expect(s == 1) } else {
            Issue.record("expected sectionLengthOutOfRange")
        }
    }

    @Test func junkAndPaddingBetweenMessagesAreSkipped() throws {
        let one = [UInt8](try GRIB2Fixtures.data("gfs-S-20261122t06z-f003"))
        let two = [UInt8](try GRIB2Fixtures.data("gfs-S-20261122t06z-f006"))
        let single = try GRIB2File(data: Data(one)).fields.count, perFile = try GRIB2File(data: Data(one)).messageOffsets.count
        let junk = Array("padding\0\0 GRI junk 7777".utf8)
        let combined = junk + one + [UInt8](repeating: 0, count: 17) + two + junk
        guard case .success(let f) = parse(combined) else { Issue.record("combined input failed"); return }
        #expect(f.messageOffsets.count == 2 * perFile && f.messageOffsets.first == junk.count)
        #expect(f.messageOffsets.contains(junk.count + one.count + 17))
        #expect(f.fields.count == single + (try GRIB2File(data: Data(two))).fields.count)
        // A cut-off "GRI" at the end is a truncated message, not padding.
        #expect(err(one + Array("GRI".utf8)) == .truncated(section: 0, offset: one.count))
    }
}
