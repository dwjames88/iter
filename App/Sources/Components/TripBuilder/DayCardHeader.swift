import SwiftUI
import IterDesign

/// The sunrise and sunset of a day, each with its symbol: "Sunrise at 06:25", "Sunset at 18:01".
struct SunTimesRow: View {
    var sunrise: String?
    var sunset: String?

    var body: some View {
        if sunrise != nil || sunset != nil {
            HStack(spacing: 20) {
                if let sunrise { item("sunrise.fill", sunrise) }
                if let sunset { item("sunset.fill", sunset) }
            }
        }
    }

    private func item(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .font(BuilderType.body)
                .foregroundStyle(IterColor.textSecondary)
                .accessibilityHidden(true)
            Text(text)
                .font(BuilderType.body)
                .monospacedDigit()
                .foregroundStyle(IterColor.textSecondary)
                .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The top of a day card: the day and its date on the left, the day's totals on the right, the sun times under them.
struct DayCardHeader: View {
    /// "Day 1"
    let dayName: String
    /// "Tuesday, Oct 6"
    let date: String
    /// "2 stops • 5 h 26 min of driving"
    let totals: String
    var sunrise: String?
    var sunset: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                Text(dayName).font(BuilderType.heading).foregroundStyle(IterColor.textPrimary)
                Text(date).font(BuilderType.body).foregroundStyle(IterColor.textSecondary).lineLimit(1)
                Spacer(minLength: 8)
                Text(totals)
                    .font(BuilderType.caption)
                    .monospacedDigit()
                    .foregroundStyle(IterColor.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            SunTimesRow(sunrise: sunrise, sunset: sunset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

#Preview("Day header, light") { DayHeaderPreview().preferredColorScheme(.light) }
#Preview("Day header, dark") { DayHeaderPreview().preferredColorScheme(.dark) }

struct DayHeaderPreview: View {
    var body: some View {
        VStack(spacing: 12) {
            DayCardHeader(dayName: "Day 1", date: "Tuesday, Oct 6", totals: "1 stop", sunrise: "Sunrise at 06:25", sunset: "Sunset at 18:01")
            DayCardHeader(dayName: "Day 2", date: "Wednesday, Oct 7", totals: "2 stops • 5hr, 26m of driving", sunrise: "Sunrise at 07:21", sunset: "Sunset at 18:54")
        }
        .padding(16)
        .frame(width: 608)
        .background(IterColor.backgroundContent, in: RoundedRectangle(cornerRadius: BuilderMetrics.cardCorner, style: .continuous))
        .padding(16)
        .background(IterColor.backgroundWindow)
    }
}
