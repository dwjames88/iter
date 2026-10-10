import SwiftUI
import IterCore
import IterDesign

/// A light window as a row, the way Maps presents a feature on a place card (Create a Custom Route): a round badge with
/// the window's symbol on the colours of that light, a title, and a quiet line under it.
struct LightWindowRow: View {
    let window: LightWindow
    let zone: TimeZone
    /// "Today", "Tomorrow" or a day name.
    let day: String
    var isLoading = false

    var body: some View {
        HStack(spacing: IterSpace.md) {
            LightWindowBadge(kind: window.kind)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(LightText.name(window.kind)) at \(TimeText.time(window.span.start, in: zone))",
                     comment: "Place card: a light window and its start time, e.g. Sunset at 18:14")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                subtitle
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(IterSpace.md)
        .background(ModuleFill(), in: RoundedRectangle(cornerRadius: IterRadius.panel, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var subtitle: some View {
        if isLoading {
            Text("\(day) · Loading the forecast", comment: "Place card: the window's day while its score loads")
        } else if let score = window.score {
            Text("\(day) · Light score \(score)", comment: "Place card: the window's day and its Light Index score")
                .monospacedDigit()
        } else {
            Text("\(day) · No score yet", comment: "Place card: the window's day when it has no score")
        }
    }
}

/// The round badge: the window's symbol in white on a gradient of that light, as Maps' feature badges are.
struct LightWindowBadge: View {
    let kind: LightWindowKind
    var size: CGFloat = 32

    var body: some View {
        Circle()
            .fill(LinearGradient(colors: colors, startPoint: .top, endPoint: .bottom))
            .overlay {
                Image(systemName: LightText.symbol(kind))
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    /// The sky of each window: warm gold to coral for the golden hours, dusk blues for the blue hours, ink for night.
    private var colors: [Color] {
        switch kind {
        case .goldenMorning: [Color(red: 1.00, green: 0.80, blue: 0.36), Color(red: 0.98, green: 0.49, blue: 0.24)]
        case .goldenEvening: [Color(red: 0.99, green: 0.66, blue: 0.27), Color(red: 0.88, green: 0.30, blue: 0.27)]
        case .blueMorning: [Color(red: 0.55, green: 0.66, blue: 0.95), Color(red: 0.36, green: 0.42, blue: 0.85)]
        case .blueEvening: [Color(red: 0.42, green: 0.48, blue: 0.90), Color(red: 0.24, green: 0.25, blue: 0.62)]
        case .night: [Color(red: 0.25, green: 0.27, blue: 0.52), Color(red: 0.11, green: 0.12, blue: 0.30)]
        }
    }
}
