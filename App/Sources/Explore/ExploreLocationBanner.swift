import SwiftUI
import IterCore
import IterDesign
import IterFeatures
import IterServices

/// A quiet strip above the list while there is no location: it points to Settings, or says it is looking (Iter asks for location itself when the window appears).
/// The list below it is always usable (every spot, one section), so this never blocks.
struct ExploreLocationBanner: View {
    @Bindable var explore: ExploreModel
    @Environment(\.openURL) private var openURL

    var body: some View {
        if location.bannerState != .none {
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                content
            }
            .padding(.horizontal, IterSpace.md)
            .padding(.vertical, IterSpace.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ControlFill())
            .overlay(alignment: .bottom) { Divider() }
            .accessibilityElement(children: .contain)
        }
    }

    private var location: UserLocationModel { explore.app.location }

    @ViewBuilder private var content: some View {
        switch location.bannerState {
        case .none:
            EmptyView()
        case .openSettings:
            prompt(action: LightText.openLocationSettings, help: String(localized: "Open Location Services in System Settings", comment: "Tooltip")) {
                openURL(UserLocationModel.settingsURL)
            }
        case .finding:
            HStack(spacing: IterSpace.sm) {
                ProgressView().controlSize(.small)
                Text(LightText.findingLocation)
                    .font(IterFont.caption)
                    .foregroundStyle(IterColor.textSecondary)
            }
            .accessibilityElement(children: .combine)
        case .unavailable:
            HStack(spacing: IterSpace.sm) {
                Text(LightText.locationUnavailable)
                    .font(IterFont.caption)
                    .foregroundStyle(IterColor.textSecondary)
                Spacer(minLength: 0)
                Button(LightText.tryAgain) { location.refresh() }
                    .controlSize(.small)
                    .help(String(localized: "Look for your location again", comment: "Tooltip"))
            }
        }
    }

    private func prompt(action: String, help: String, perform: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: IterSpace.md) {
            VStack(alignment: .leading, spacing: IterSpace.xxs) {
                Text(LightText.locationPromptTitle)
                    .font(IterFont.subheadline.weight(.semibold))
                    .foregroundStyle(IterColor.textPrimary)
                Text(LightText.locationPromptDetail(radiusMiles: explore.radiusMiles))
                    .font(IterFont.caption)
                    .foregroundStyle(IterColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(action, action: perform)
                .controlSize(.small)
                .help(help)
        }
    }
}
