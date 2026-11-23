import Foundation
import IterModel

/// The Live Activity's `ContentState`: a deliberately tiny projection of `GoSnapshot` (ActivityKit allows 4 KB for the whole
/// payload, and a test holds the worst case under 2 KB). Available on every platform so the Mac tests can encode it.
/// Countdowns use `leaveBy`/`eta` with timer-style text, so the activity ticks with no updates.
public struct GoActivityContent: Codable, Hashable, Sendable {
    public static let maxNameLength = 40

    public var phase: GoPhase
    /// The stop Go is heading to (or about to), truncated to 40 characters.
    public var nextStopName: String?
    public var status: GoLeaveStatus?
    public var leaveBy: Date?
    public var eta: Date?
    public var windowKind: LightWindowKind?
    public var windowStart: Date?
    public var liveScore: Int?
    public var forecastScore: Int?
    public var band: GoBand?
    public var confidence: GoConfidence?
    public var trend: GoTrend?
    /// When the numbers were last refreshed (the ETA or conditions fetch): "updated 12 min ago" via `Text(.relative)`.
    public var dataAsOf: Date
    /// Whole minutes late, when late or missed.
    public var lateMinutes: Int?
    public var isOffline: Bool
    public var isPowerSaving: Bool
    /// While an automatic transition can still be undone.
    public var undoExpiresAt: Date?
    /// The stop `nextStopName` refers to.
    public var stopID: UUID?
    /// That stop's own zone, so times are shown where the stop is.
    public var timeZoneIdentifier: String?
    /// The window end of the stop you are at while at a stop, else of the sky's or next stop's window.
    public var windowEnd: Date?
    /// Sample data: the widget calls the score "Sample", never "Live". nil in the real app.
    public var isSampleData: Bool?

    public init(phase: GoPhase, nextStopName: String? = nil, status: GoLeaveStatus? = nil, leaveBy: Date? = nil, eta: Date? = nil,
                windowKind: LightWindowKind? = nil, windowStart: Date? = nil, liveScore: Int? = nil, forecastScore: Int? = nil,
                band: GoBand? = nil, confidence: GoConfidence? = nil, trend: GoTrend? = nil, dataAsOf: Date, lateMinutes: Int? = nil,
                isOffline: Bool = false, isPowerSaving: Bool = false, undoExpiresAt: Date? = nil, stopID: UUID? = nil,
                timeZoneIdentifier: String? = nil, windowEnd: Date? = nil, isSampleData: Bool? = nil) {
        self.phase = phase
        self.nextStopName = nextStopName.map(Self.truncated)
        self.status = status
        self.leaveBy = leaveBy
        self.eta = eta
        self.windowKind = windowKind
        self.windowStart = windowStart
        self.liveScore = liveScore
        self.forecastScore = forecastScore
        self.band = band
        self.confidence = confidence
        self.trend = trend
        self.dataAsOf = dataAsOf
        self.lateMinutes = lateMinutes
        self.isOffline = isOffline
        self.isPowerSaving = isPowerSaving
        self.undoExpiresAt = undoExpiresAt
        self.stopID = stopID
        self.timeZoneIdentifier = timeZoneIdentifier
        self.windowEnd = windowEnd
        self.isSampleData = isSampleData
    }

    public init(snapshot s: GoSnapshot) {
        let stop = s.next ?? s.current
        let sky = s.sky
        let asOfs = [s.freshness.etaAsOf, s.freshness.conditionsAsOf].compactMap { $0 }
        self.init(phase: s.phase, nextStopName: stop?.name, status: s.leave?.status, leaveBy: s.leave?.leaveBy, eta: s.drive?.arrival,
                  windowKind: sky?.windowKind ?? stop?.windowKind, windowStart: sky?.windowStart ?? stop?.windowStart,
                  liveScore: sky?.liveScore, forecastScore: sky?.forecastScore, band: sky?.band,
                  confidence: sky.map(\.confidence), trend: sky.map(\.trend), dataAsOf: asOfs.max() ?? s.generatedAt,
                  lateMinutes: s.leave?.lateBySeconds.map { Int(($0 / 60).rounded()) }, isOffline: s.freshness.isOffline,
                  isPowerSaving: s.freshness.isPowerSaving, undoExpiresAt: s.undo?.expiresAt, stopID: stop?.id,
                  timeZoneIdentifier: stop?.timeZoneIdentifier,
                  windowEnd: s.phase == .atStop ? (s.current?.windowEnd ?? sky?.windowEnd ?? stop?.windowEnd) : (sky?.windowEnd ?? stop?.windowEnd),
                  isSampleData: s.isSampleData)
    }

    static func truncated(_ name: String) -> String {
        name.count <= maxNameLength ? name : String(name.prefix(maxNameLength - 1)) + "\u{2026}"
    }
}
