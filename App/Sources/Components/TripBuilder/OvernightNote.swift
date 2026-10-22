import SwiftUI
import IterDesign

/// "Overnight near Page, AZ" at the foot of a day card: a moon and the place, quiet and tertiary.
struct OvernightNote: View {
    /// The whole line, already phrased ("Overnight near Page, AZ").
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "moon.zzz")
            Text(text).lineLimit(1)
        }
        .font(BuilderType.control)
        .foregroundStyle(IterColor.textTertiary)
        .accessibilityElement(children: .combine)
    }
}

#Preview("Overnight note, light") { OvernightNote(text: "Overnight near Page, AZ").padding(IterSpace.xl).background(IterColor.backgroundContent).preferredColorScheme(.light) }
#Preview("Overnight note, dark") { OvernightNote(text: "Overnight near Page, AZ").padding(IterSpace.xl).background(IterColor.backgroundContent).preferredColorScheme(.dark) }
