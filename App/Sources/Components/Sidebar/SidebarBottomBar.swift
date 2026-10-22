import SwiftUI
import IterDesign
import IterFeatures

/// The bar at the bottom of the sidebar: the info button (what the scores mean) at the leading edge, the "+" menu
/// (New Trip, New Location) at the trailing edge, and the sample-data banner above when sample weather is on.
/// Plain system buttons. Mac only.
struct SidebarBottomBar: View {
    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    @State private var showsLegend = false

    /// The glyphs are 14 pt boxes (design); the padding around them makes the hit target 24 pt.
    private let glyphBox: CGFloat = 14
    private let hitPadding: CGFloat = 5

    var body: some View {
        VStack(spacing: IterSpace.sm) {
            if model.sampleDataEnabled { SampleDataLabel(style: .banner) }
            HStack(alignment: .bottom) {
                legendButton
                Spacer()
                addMenu
            }
        }
        .padding(12)
    }

    private var legendButton: some View {
        Button { showsLegend.toggle() } label: {
            Image(systemName: "info.circle")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: glyphBox, height: glyphBox)
                .padding(hitPadding)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .foregroundStyle(IterColor.textPrimary)
        .help(Text("What the scores mean", comment: "Tooltip"))
        .accessibilityLabel(Text("What the scores mean", comment: "Button"))
        .popover(isPresented: $showsLegend, arrowEdge: .trailing) {
            ScoreLegendPopover(source: model.weather.settings.primary)
        }
    }

    private var addMenu: some View {
        Menu {
            Button(String(localized: "New Trip", comment: "Menu item")) {
                navigation.newTripRequest += 1
                if case .trip = navigation.selection {} else { navigation.selection = .trips }
            }
            Button(String(localized: "New Location", comment: "Menu item: drops a pin on the Explore map")) {
                navigation.show(.explore)
                navigation.addSpotModeRequest += 1
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: glyphBox, height: glyphBox)
                .padding(hitPadding)
                .contentShape(.rect)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(IterColor.textPrimary)
        .help(Text("New Trip or Location", comment: "Tooltip"))
        .accessibilityLabel(Text("New Trip or Location", comment: "Button"))
    }
}
