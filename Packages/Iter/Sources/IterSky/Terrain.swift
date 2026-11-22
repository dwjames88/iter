import Foundation
import IterModel
import IterAstro

/// What the terrain skyline does to a window.
struct TerrainAssessment: Equatable, Sendable {
    /// Golden windows: the window after the skyline; nil when it is unchanged (less than 30 s lost).
    var effectiveSpan: TimeSpan?
    /// Seconds of a golden window the skyline takes.
    var lostSeconds: TimeInterval = 0
    /// `lostSeconds` as a fraction of the window, 0...1.
    var fractionLost: Double = 0
    /// Blue windows: the skyline elevation (degrees) toward the sun's azimuth at sunset (evening) or sunrise (morning).
    var skylineDegrees: Double?
}

/// Terrain horizon geometry. A flat horizon changes nothing: the sun is compared with the skyline raised from the level
/// horizon, relative to where the sun is at the window's natural end (sunset or sunrise), so refraction and the
/// sunrise definition do not count as terrain.
enum Terrain {
    /// Sun samples every three minutes across a window.
    static let stepSeconds: TimeInterval = 180
    /// Less than this lost counts as unchanged.
    static let minimumLoss: TimeInterval = 30

    static func assess(kind: LightWindowKind, span: TimeSpan, coordinate: Coordinate, horizon: HorizonProfile,
                       ephemeris: any Ephemeris) -> TerrainAssessment? {
        switch kind {
        case .night:
            return nil
        case .blueEvening, .blueMorning:
            let at = kind == .blueEvening ? span.start : span.end
            let azimuth = ephemeris.sunPosition(at: at, coordinate: coordinate).azimuth
            return TerrainAssessment(skylineDegrees: horizon.elevation(atAzimuth: azimuth))
        case .goldenEvening, .goldenMorning:
            return golden(evening: kind == .goldenEvening, span: span, coordinate: coordinate, horizon: horizon, ephemeris: ephemeris)
        }
    }

    private static func golden(evening: Bool, span: TimeSpan, coordinate: Coordinate, horizon: HorizonProfile,
                              ephemeris: any Ephemeris) -> TerrainAssessment {
        let duration = span.duration
        guard duration > 0 else { return TerrainAssessment() }
        var times: [Date] = []
        var t = span.start
        while t < span.end {
            times.append(t)
            t = t.addingTimeInterval(stepSeconds)
        }
        times.append(span.end)
        let positions = times.map { ephemeris.sunPosition(at: $0, coordinate: coordinate) }
        let natural = evening ? positions[positions.count - 1].altitude : positions[0].altitude
        let reference = min(0, natural)
        // margin > 0: the sun clears the skyline.
        let margins = positions.map { $0.altitude - (max(0, horizon.elevation(atAzimuth: $0.azimuth)) + reference) }

        func crossing(_ a: Int, _ b: Int) -> Date {
            let ma = margins[a], mb = margins[b]
            let f = ma == mb ? 0 : min(1, max(0, ma / (ma - mb)))
            return times[a].addingTimeInterval(times[b].timeIntervalSince(times[a]) * f)
        }

        let effective: TimeSpan?
        if evening {
            if let i = margins.firstIndex(where: { $0 < 0 }) {
                effective = TimeSpan(start: span.start, end: i == 0 ? span.start : crossing(i - 1, i))
            } else {
                effective = nil
            }
        } else {
            if let i = margins.lastIndex(where: { $0 < 0 }) {
                effective = TimeSpan(start: i == margins.count - 1 ? span.end : crossing(i, i + 1), end: span.end)
            } else {
                effective = nil
            }
        }
        guard let effective else { return TerrainAssessment() }
        let lost = duration - effective.duration
        guard lost >= minimumLoss else { return TerrainAssessment() }
        return TerrainAssessment(effectiveSpan: effective, lostSeconds: lost, fractionLost: min(1, lost / duration))
    }
}
