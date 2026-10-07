import SwiftUI
import IterCore
import IterDesign

/// What the status band says about a place's next window: a title ("Sunset in 2 h 14 m"), the score ("76"),
/// and the Light Index band that tints it. No band (no score, low confidence) means a neutral band, never a coloured one.
struct LightStatus: Equatable {
    var title: String
    var detail: String?
    /// VoiceOver only: the band word and the score.
    var spokenDetail: String?
    var band: LightBand?
    var symbol: String

    init(window: LightWindow?, isLoading: Bool, now: Date) {
        guard let window else {
            title = isLoading ? LightText.checkingForecast : String(localized: "No upcoming window", comment: "Status band: nothing to show")
            detail = nil
            spokenDetail = nil
            band = nil
            symbol = "sun.horizon"
            return
        }
        symbol = LightText.symbol(window.kind)
        let name = LightText.name(window.kind)
        if window.span.start > now {
            let wait = TimeText.duration(window.span.start.timeIntervalSince(now))
            title = String(localized: "\(name) in \(wait)", comment: "Status band: the next light window and how long until it starts, e.g. Sunset in 2 h 14 min")
        } else if window.span.end > now {
            title = String(localized: "\(name) now", comment: "Status band: the light window is under way")
        } else {
            title = name
        }
        if let score = window.assessment.lightScore {
            detail = score.value.formatted()
            spokenDetail = String(localized: "\(LightText.name(score.band)) · \(score.value)", comment: "Status band: band word and Light Index score, e.g. Great · 76")
            band = score.confidence == .low ? nil : score.band
        } else {
            detail = isLoading ? LightText.checkingForecast : String(localized: "No forecast yet", comment: "Status band: the window has no score")
            band = nil
        }
    }
}

/// The full-width status band under a detail header. A tinted ground in the next window's band colour (the ramp) with
/// primary text (the ramp fills are now dark, for white text), neutral when there is no confident score.
struct LightStatusBand: View {
    let status: LightStatus
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let wash = status.band.map { IterColor.ramp($0) }
        HStack(alignment: .firstTextBaseline, spacing: IterSpace.sm) {
            Image(systemName: status.symbol).accessibilityHidden(true)
            Text(status.title).font(.headline)
            Spacer(minLength: IterSpace.sm)
            if let detail = status.detail {
                Text(detail).font(.headline).monospacedDigit()
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .foregroundStyle(status.band == nil ? IterColor.textSecondary.color : IterColor.textPrimary.color)
        .padding(.horizontal, IterSpace.lg)
        .padding(.vertical, IterSpace.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((wash ?? IterColor.backgroundModule).opacity(wash == nil ? 1 : (scheme == .dark ? 0.2 : 0.35)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([status.title, status.spokenDetail ?? status.detail].compactMap { $0 }.joined(separator: ", "))
    }
}

/// The headline fact of a detail screen: the next window as the large event unit (symbol, score and start time in one
/// capsule; `EventScore` has no variant that hides the time, so no second big time is drawn), with the day and the
/// window's span beneath it.
struct LightHeadline: View {
    let window: LightWindow
    let zone: TimeZone
    var dayLabel: String?
    var isLoading = false
    var isTomorrow = false

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            EventScore(window: window, zone: zone, timeStyle: .start, variant: .large, isLoading: isLoading, isTomorrow: isTomorrow)
            Text([LightText.name(window.kind), dayLabel].compactMap { $0 }.joined(separator: " · "))
                .font(.headline)
                .foregroundStyle(IterColor.textPrimary)
            Text(String(localized: "Window \(TimeText.timeRange(window.span, in: zone))", comment: "Headline: the light window's start and end"))
                .font(.subheadline).monospacedDigit()
                .foregroundStyle(IterColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LightText.accessibilityDescription(window) + ", " + TimeText.time(window.span.start, in: zone))
    }
}
