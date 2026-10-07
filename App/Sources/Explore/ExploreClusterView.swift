import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// Several map pins too close to tell apart at this zoom, drawn as one count. Borderless like the pins: the same
/// chip fill (material over the map, flat content colour in snapshots) and shadow as the pin tail. A small dot in the
/// best member's band colour, before the count, says what is inside (none when no member is scored); clicking zooms
/// to fit the members (the map pane handles the click).
struct ExploreClusterView: View {
    let cluster: ExploreCluster

    @Environment(\.renderMode) private var renderMode

    var body: some View {
        HStack(spacing: IterSpace.xs) {
            if let band = cluster.bestBand {
                Circle().fill(IterColor.ramp(band)).frame(width: IterSpace.sm, height: IterSpace.sm)
            }
            Text(cluster.count, format: .number)
                .font(IterFont.captionStrong)
                .monospacedDigit()
                .foregroundStyle(IterColor.textPrimary)
        }
        .frame(minWidth: IterSize.badgeHeight, minHeight: IterSize.badgeHeight)
        .padding(.horizontal, IterSpace.xs)
        .background(fill, in: Capsule())
        .shadow(radius: IterEvent.pinShadowRadius, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LightText.clusterDescription(count: cluster.count))
        .accessibilityAddTraits(.isButton)
    }

    private var fill: AnyShapeStyle {
        // An offscreen render has no backdrop for materials.
        renderMode == .snapshot ? AnyShapeStyle(IterColor.backgroundContent) : AnyShapeStyle(.regularMaterial)
    }
}
