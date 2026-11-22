import SwiftUI

/// The bar at the bottom of the sidebar: the info button at the leading edge (its `legend` opens in a popover), the "+"
/// menu (`addItems`: New Trip, New Location) at the trailing edge, and an optional `banner` above (the sample-data
/// notice). Plain borderless buttons, no glass. Figma part: Sidebar (11:1768), bottom bar.
public struct SidebarBottomBar<Legend: View, AddItems: View, Banner: View>: View {
    let infoLabel: String
    let addLabel: String
    let legend: Legend
    let addItems: AddItems
    let banner: Banner
    @State private var showsLegend = false

    /// The glyphs are 14 pt boxes (design); the padding around them makes the hit target 24 pt.
    private let glyphBox: CGFloat = 14
    private let hitPadding: CGFloat = 5

    public init(infoLabel: String, addLabel: String,
                @ViewBuilder legend: () -> Legend, @ViewBuilder addItems: () -> AddItems,
                @ViewBuilder banner: () -> Banner) {
        self.infoLabel = infoLabel
        self.addLabel = addLabel
        self.legend = legend()
        self.addItems = addItems()
        self.banner = banner()
    }

    public var body: some View {
        VStack(spacing: IterSpace.sm) {
            banner
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
        .help(infoLabel)
        .accessibilityLabel(infoLabel)
        .popover(isPresented: $showsLegend, arrowEdge: .trailing) { legend }
    }

    private var addMenu: some View {
        Menu {
            addItems
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .frame(width: glyphBox, height: glyphBox)
                .padding(hitPadding)
                .contentShape(.rect)
        }
        #if os(macOS)
        .menuStyle(.borderlessButton)
        #else
        .buttonStyle(.borderless)
        #endif
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(IterColor.textPrimary)
        .help(addLabel)
        .accessibilityLabel(addLabel)
    }
}

extension SidebarBottomBar where Banner == EmptyView {
    public init(infoLabel: String, addLabel: String,
                @ViewBuilder legend: () -> Legend, @ViewBuilder addItems: () -> AddItems) {
        self.init(infoLabel: infoLabel, addLabel: addLabel, legend: legend, addItems: addItems, banner: { EmptyView() })
    }
}
