import SwiftUI
import IterCore
import IterDesign

/// Where a spot came from: Curated, Added by you, Apple Maps, Scout.
struct ProvenanceTag: View {
    let origin: SpotOrigin

    var body: some View {
        Text(LightText.name(origin))
            .font(IterFont.caption)
            .foregroundStyle(IterColor.textSecondary)
            .padding(.horizontal, IterSpace.xs)
            .padding(.vertical, IterSpace.xxs)
            .overlay(Capsule().strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline))
    }
}
