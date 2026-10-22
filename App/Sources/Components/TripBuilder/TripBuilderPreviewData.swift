import Foundation
import IterCore

/// Plain values for the Trip Builder components' previews and snapshots (no store, no forecast).
enum TripBuilderPreviewData {
    static let zone = TimeZone(identifier: "America/Phoenix")!
    static let day = LocalDay(year: 2026, month: 10, day: 6)

    /// A golden-evening window starting 06:55 with the given score (nil: no forecast).
    static func window(_ kind: LightWindowKind = .goldenMorning, score: Int?) -> LightWindow {
        let start = day.at(hour: 6, minute: 55, in: zone)
        let span = TimeSpan(start: start, end: start.addingTimeInterval(35 * 60))
        guard let value = score else { return LightWindow(kind: kind, span: span, assessment: .noForecast(.beyondHorizon)) }
        let s = LightScore(value: value, band: LightBand(score: value), confidence: .high, range: value...value, contributors: [],
                           source: .sample, forecastFetchedAt: start, leadHours: 12)
        return LightWindow(kind: kind, span: span, assessment: .scored(s))
    }
}
