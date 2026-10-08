import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// Several map pins too close to tell apart at this zoom, drawn as one count. Borderless like the pins: the same
/// chip fill (the solid content colour) and shadow as the pin tail. A small dot in the
/// best member's band colour, before the count, says what is inside (none when no member is scored); clicking zooms
/// to fit the members (the map pane handles the click).
struct ExploreClusterView: View {
    let cluster: ExploreCluster


    var body: some View {
        HStack(spacing: IterSpace.xs) {
            if let score = cluster.bestScore {
                Circle().fill(IterColor.ramp(score: score)).frame(width: IterSpace.sm, height: IterSpace.sm)
                    .overlay(Circle().strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline))
            }
            Text(cluster.count, format: .number)
                .font(IterFont.captionStrong)
                .monospacedDigit()
                .foregroundStyle(IterColor.textPrimary)
        }
        .frame(minWidth: IterSize.badgeHeight, minHeight: IterSize.badgeHeight)
        .padding(.horizontal, IterSpace.xs)
        .background(IterColor.backgroundContent, in: Capsule())
        .shadow(radius: IterEvent.pinShadowRadius, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LightText.clusterDescription(count: cluster.count))
        .accessibilityAddTraits(.isButton)
    }

}
