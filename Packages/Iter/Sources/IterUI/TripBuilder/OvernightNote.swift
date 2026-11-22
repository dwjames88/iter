import SwiftUI

/// "Overnight near Page, AZ" at the foot of a day card: a moon and the place, quiet and tertiary.
/// Figma part: overnight note.
public struct OvernightNote: View {
    /// The whole line, already phrased ("Overnight near Page, AZ").
    public let text: String

    public init(text: String) { self.text = text }

    /// Phrases "Overnight near <place>" itself.
    public init(place: String, locale: Locale = .current) {
        self.text = TripBuilderText.overnightNear(place, locale: locale)
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.zzz")
            Text(text).lineLimit(1)
        }
        .font(BuilderType.control)
        .foregroundStyle(IterColor.textTertiary)
        .accessibilityElement(children: .combine)
    }
}
