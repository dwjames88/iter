import SwiftUI

/// A sidebar section's header: the system sidebar header style (small, bold, secondary), marked as a header for
/// VoiceOver. Use as the `header:` of a `Section` in a `.listStyle(.sidebar)` list.
struct SidebarSectionHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview("Header, light") {
    List { Section { Text("Row") } header: { SidebarSectionHeader("Locations") } }
        .listStyle(.sidebar).frame(width: 260, height: 120).preferredColorScheme(.light)
}

#Preview("Header, dark") {
    List { Section { Text("Row") } header: { SidebarSectionHeader("Locations") } }
        .listStyle(.sidebar).frame(width: 260, height: 120).preferredColorScheme(.dark)
}
