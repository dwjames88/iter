import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// Several map pins too close to tell apart at this zoom, drawn as one count. A thin ring in the best member's band
/// colour says what is inside; clicking zooms to fit the members (the map pane handles the click).
struct ExploreClusterView: View {
    let cluster: ExploreCluster

    var body: some View {
        Text(cluster.count, format: .number)
            .font(IterFont.captionStrong)
            .monospacedDigit()
            .foregroundStyle(IterColor.textPrimary)
            .frame(minWidth: IterSize.badgeHeight, minHeight: IterSize.badgeHeight)
            .padding(.horizontal, IterSpace.xs)
            .background(IterColor.backgroundContent, in: Capsule())
            .overlay {
                if let band = cluster.bestBand {
                    Capsule().strokeBorder(IterColor.ramp(band), lineWidth: IterStroke.thick)
                } else {
                    Capsule().strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(LightText.clusterDescription(count: cluster.count))
            .accessibilityAddTraits(.isButton)
    }
}
