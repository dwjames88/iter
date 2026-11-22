import SwiftUI

/// A sidebar row: a title and an SF Symbol in the accent colour (monochrome, the primary foreground when the row is
/// selected), an optional trailing accessory (for example a count or an offline badge), one line. The selection
/// highlight is the list's own. Tag it at the call site. Figma part: Sidebar (11:1768), row.
public struct SidebarRow<Accessory: View>: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    @ViewBuilder let accessory: () -> Accessory
    /// `.increased` when the row is selected in an emphasized (key) sidebar: the list fills it with the accent.
    @Environment(\.backgroundProminence) private var prominence

    /// - Parameter isSelected: forces the selected look outside a `List` (inside one, the list's prominence drives it).
    public init(_ title: String, systemImage: String, isSelected: Bool = false,
                @ViewBuilder accessory: @escaping () -> Accessory) {
        self.title = title
        self.systemImage = systemImage
        self.isSelected = isSelected
        self.accessory = accessory
    }

    public var body: some View {
        Label {
            HStack(spacing: IterSpace.xs) {
                Text(title).fontWeight(.semibold).lineLimit(1)
                Spacer(minLength: 0)
                accessory()
            }
        } icon: {
            Image(systemName: systemImage)
                .symbolRenderingMode(.monochrome)
                // Accent on paper; on the accent selection fill follow the label's foreground instead.
                .foregroundStyle(prominence == .increased || isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(IterColor.accent))
        }
    }
}

extension SidebarRow where Accessory == EmptyView {
    public init(_ title: String, systemImage: String, isSelected: Bool = false) {
        self.init(title, systemImage: systemImage, isSelected: isSelected) { EmptyView() }
    }
}

extension SidebarRow where Accessory == Text {
    /// A row with a trailing count in secondary text.
    public init(_ title: String, systemImage: String, count: Int, isSelected: Bool = false) {
        self.init(title, systemImage: systemImage, isSelected: isSelected) {
            Text(count, format: .number).foregroundStyle(.secondary).monospacedDigit()
        }
    }
}
