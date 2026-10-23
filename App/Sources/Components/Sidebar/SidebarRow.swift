import SwiftUI
import IterDesign

/// A sidebar row: a title and an SF Symbol in the accent colour (monochrome, the selection foreground when the row is selected), an optional trailing accessory (for
/// example an offline badge), one line. The selection highlight is the list's own. Tag it at the call site.
struct SidebarRow<Accessory: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let accessory: () -> Accessory
    /// `.increased` when the row is selected in an emphasized (key) sidebar: the list fills it with the accent.
    @Environment(\.backgroundProminence) private var prominence

    init(_ title: String, systemImage: String, @ViewBuilder accessory: @escaping () -> Accessory) {
        self.title = title
        self.systemImage = systemImage
        self.accessory = accessory
    }

    var body: some View {
        Label {
            HStack(spacing: IterSpace.xs) {
                Text(title).fontWeight(.semibold).lineLimit(1)
                Spacer(minLength: 0)
                accessory()
            }
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.monochrome)
                // Accent on paper; on the accent selection fill follow the label's foreground (white) instead.
                .foregroundStyle(prominence == .increased ? AnyShapeStyle(.primary) : AnyShapeStyle(IterColor.accent))
        }
    }
}

extension SidebarRow where Accessory == EmptyView {
    init(_ title: String, systemImage: String) {
        self.init(title, systemImage: systemImage) { EmptyView() }
    }
}

#Preview("Rows, light") {
    List {
        SidebarRow("Explore", systemImage: "binoculars")
        SidebarRow("Canyon Country", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
            Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
        }
    }
    .listStyle(.sidebar).frame(width: 260, height: 120).preferredColorScheme(.light)
}

#Preview("Rows, dark") {
    List {
        SidebarRow("Explore", systemImage: "binoculars")
        SidebarRow("Canyon Country", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
            Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
        }
    }
    .listStyle(.sidebar).frame(width: 260, height: 120).preferredColorScheme(.dark)
}
