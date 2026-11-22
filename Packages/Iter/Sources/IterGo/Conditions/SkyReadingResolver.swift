import Foundation
import IterModel
import IterSky
import IterConditions

// Turns the next stop's live reading and forecast report into the `GoSkyInfo` Go shows (BLUEPRINT §8.2, §10.3).

extension GoBand {
    public init(_ band: LightBand) {
        switch band {
        case .poor: self = .poor
        case .fair: self = .fair
        case .good: self = .good
        case .great: self = .great
        case .epic: self = .epic
        }
    }
}

extension GoConfidence {
    public init(_ confidence: Confidence) {
        self = GoConfidence(rawValue: confidence.rawValue) ?? .low
    }
}

extension GoTrend {
    public init(_ trend: LiveTrend) {
        self = GoTrend(rawValue: trend.rawValue) ?? .unknown
    }
}

/// How the Forecast Sky Index of one stop's window moved over the last refreshes. Keeps the last three samples.
public struct ForecastTrendTracker: Codable, Hashable, Sendable {
    public static let sampleLimit = 3
    /// Points between the oldest kept sample and the newest needed to call rising or falling.
    public static let threshold = 5

    public private(set) var samples: [String: [Int]]

    public init() { samples = [:] }

    static func key(_ stopID: UUID, _ kind: LightWindowKind) -> String { "\(stopID.uuidString)|\(kind.rawValue)" }

    public mutating func record(stopID: UUID, kind: LightWindowKind, score: Int) {
        var list = samples[Self.key(stopID, kind)] ?? []
        list.append(score)
        if list.count > Self.sampleLimit { list.removeFirst(list.count - Self.sampleLimit) }
        samples[Self.key(stopID, kind)] = list
    }

    public func samples(stopID: UUID, kind: LightWindowKind) -> [Int] { samples[Self.key(stopID, kind)] ?? [] }

    /// Unknown with fewer than two samples; else rising or falling when the newest is 5 or more points from the oldest.
    public func trend(stopID: UUID, kind: LightWindowKind) -> GoTrend {
        let list = samples(stopID: stopID, kind: kind)
        guard list.count >= 2, let first = list.first, let last = list.last else { return .unknown }
        let change = last - first
        if change >= Self.threshold { return .rising }
        if change <= -Self.threshold { return .falling }
        return .steady
    }

    public mutating func forget(stopID: UUID) {
        let prefix = stopID.uuidString + "|"
        for key in samples.keys where key.hasPrefix(prefix) { samples[key] = nil }
    }
}

public enum SkyReadingResolver {
    /// The sky for `stop`'s window. A live reading with a score wins; else the stop's window from the forecast report
    /// (with its trend from `history`); else `.noData`.
    public static func resolve(stop: Stop, live: LiveConditions?, report: SkyReport?, history: ForecastTrendTracker, now: Date) -> GoSkyInfo {
        if let live, let score = live.reading.score {
            let reading = live.reading
            let basis: GoSkyInfo.Basis
            switch reading.state {
            case .blended: basis = .blended
            case .observationOnly: basis = .observationOnly
            case .forecastOnly, .noData: basis = .forecastOnly
            }
            return GoSkyInfo(stopID: stop.id, windowKind: reading.kind ?? stop.session, windowStart: reading.window?.start,
                             windowEnd: reading.window?.end, liveScore: score, forecastScore: reading.forecastScore,
                             band: GoBand(LightBand(score: score)), confidence: GoConfidence(reading.confidence),
                             trend: GoTrend(reading.trend), basis: basis, asOf: now.addingTimeInterval(-(reading.age ?? 0)),
                             notice: live.notice?.text ?? report?.offlineNote, isStale: reading.isStale)
        }
        if let report, let window = report.daylight.window(stop.session), let score = window.score {
            let skyScore = window.assessment.skyScore
            return GoSkyInfo(stopID: stop.id, windowKind: stop.session, windowStart: window.span.start, windowEnd: window.span.end,
                             liveScore: nil, forecastScore: score, band: GoBand(LightBand(score: score)),
                             confidence: skyScore.map { GoConfidence($0.confidence) } ?? .low,
                             trend: history.trend(stopID: stop.id, kind: stop.session), basis: .nextWindowForecast,
                             asOf: report.generatedAt, notice: report.offlineNote ?? live?.notice?.text,
                             isStale: skyScore?.isStale ?? false)
        }
        return GoSkyInfo(stopID: stop.id, windowKind: stop.session, windowStart: nil, windowEnd: nil, liveScore: nil, forecastScore: nil,
                         band: nil, confidence: .low, trend: .unknown, basis: .noData, asOf: nil, notice: "No live data", isStale: false)
    }
}
