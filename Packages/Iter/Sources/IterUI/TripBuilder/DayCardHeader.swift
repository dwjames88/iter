import SwiftUI

/// The sunrise and sunset of a day, each with its symbol: "Sunrise at 06:25", "Sunset at 18:01".
/// Figma part: sun times row.
public struct SunTimesRow: View {
    public var sunrise: String?
    public var sunset: String?

    public init(sunrise: String? = nil, sunset: String? = nil) {
        self.sunrise = sunrise
        self.sunset = sunset
    }

    public var body: some View {
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
/// Figma part: day card header.
public struct DayCardHeader: View {
    /// "Day 1"
    public let dayName: String
    /// "Tuesday, Oct 6"
    public let date: String
    /// "2 stops • 5 hr, 26 min of driving"
    public let totals: String
    public var sunrise: String?
    public var sunset: String?

    public init(dayName: String, date: String, totals: String, sunrise: String? = nil, sunset: String? = nil) {
        self.dayName = dayName
        self.date = date
        self.totals = totals
        self.sunrise = sunrise
        self.sunset = sunset
    }

    public var body: some View {
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
