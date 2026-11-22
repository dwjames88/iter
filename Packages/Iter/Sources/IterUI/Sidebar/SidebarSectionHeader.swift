import SwiftUI

/// A sidebar section's header: the system sidebar header style (small, bold, secondary), marked as a header for
/// VoiceOver. Use as the `header:` of a `Section` in a `.listStyle(.sidebar)` list. Figma part: Sidebar (11:1768),
/// section header.
public struct SidebarSectionHeader: View {
    let title: String

    public init(_ title: String) { self.title = title }

    public var body: some View {
        Text(title)
            .accessibilityAddTraits(.isHeader)
    }
}
