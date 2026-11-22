import SwiftUI
import IterModel

/// Trip mode, iPhone: the Live Sky Index now for the next window: the score on its ramp fill (a large `ScoreChip`),
/// the window's name, confidence and how fresh the observations are. Solid content card.
/// A nil score is "No live data": a named gap in the neutral grey, never a low score.
/// Go component (new, not yet drawn in Figma).
public struct LiveSkyCard: View {
    public let score: Int?
    public let kind: LightWindowKind
    public let windowStart: Date
    public let confidence: ConfidenceLevel
    public let updatedAt: Date
    public let now: Date
    public let zone: TimeZone
    public let locale: Locale

    public init(score: Int?, kind: LightWindowKind, windowStart: Date, confidence: ConfidenceLevel, updatedAt: Date,
                now: Date, zone: TimeZone, locale: Locale = .current) {
        self.score = score
        self.kind = kind
        self.windowStart = windowStart
        self.confidence = confidence
        self.updatedAt = updatedAt
        self.now = now
        self.zone = zone
        self.locale = locale
    }

    var ageText: String { DataText.ageText(of: updatedAt, now: now, locale: locale) }
    var title: String { String(localized: "Live Sky Index", bundle: .module, locale: locale, comment: "Trip mode: the real-time sky index") }
    var accessibilityText: String {
        let s = score.map { String(localized: "\($0) out of 100", bundle: .module, locale: locale, comment: "Score for VoiceOver") }
            ?? String(localized: "No live data", bundle: .module, locale: locale, comment: "Live index unavailable")
        return "\(title), \(LightText.name(kind)), \(s), \(confidence.phrase(locale: locale)), \(ageText)"
    }

    public var body: some View {
        HStack(spacing: IterSpace.md) {
            ScoreChip(kind: kind, start: windowStart, score: score, zone: zone, locale: locale, size: .large,
                      isLowConfidence: confidence == .low)
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                Text(verbatim: title).font(IterFont.captionStrong).foregroundStyle(IterColor.textSecondary)
                Text(verbatim: LightText.name(kind)).font(IterFont.headline).foregroundStyle(IterColor.textPrimary)
                if score == nil {
                    Label { Text("No Live Data", bundle: .module) } icon: { Image(systemName: "circle.dashed") }
                        .font(IterFont.captionStrong)
                        .foregroundStyle(IterColor.textSecondary)
                } else {
                    ConfidenceIndicator(confidence, locale: locale)
                }
                Text(verbatim: ageText).font(IterFont.caption).foregroundStyle(IterColor.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .goCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityText))
    }
}
