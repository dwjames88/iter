import SwiftUI
import Testing
import IterData
import IterCore
import IterDesign
@testable import Iter

/// The whole sidebar built from `Components/Sidebar`, light and dark at 300 x 820. Files: `sidebar-redesign-*`.
@MainActor
@Suite(.serialized) struct SidebarComponentSnapshotTests {
    @Test(.enabled(if: Snapshot.enabled)) func sidebarRedesign() async throws {
        let model = Fixtures.model()
        let california = model.store.createFolder(name: "California", kind: .locations)
        model.store.setPinned(california, true)
        let trip = model.store.createTrip(name: "Canyon Country", startDay: LocalDay(year: 2027, month: 4, day: 3), dayCount: 4)
        model.store.setPinned(trip, true)
        let size = Snapshot.Size(name: "300x820", width: 300, height: 820)
        let view = Fixtures.host(SidebarView(), model: model)
        try await Snapshot.render(view, screen: "sidebar", state: "redesign", sizes: [size])
    }

    /// The selected state: Explore and a child folder selected (the harness draws a neutral pill, not the accent fill
    /// of a key window), so the rows are rendered with `.increased` background prominence on an accent fill, which is
    /// what the list gives a selected, emphasized row. The symbol must read white there and accent on the others.
    @Test(.enabled(if: Snapshot.enabled)) func sidebarSelected() async throws {
        let model = Fixtures.model()
        let size = Snapshot.Size(name: "300x820", width: 300, height: 820)
        let view = VStack(alignment: .leading, spacing: 4) {
            selectedRow("Explore", "binoculars", selected: true)
            selectedRow("All Locations", "mappin.and.ellipse", selected: false)
            selectedRow("California", "folder", selected: true)
            selectedRow("Canyon Country", "point.topleft.down.to.point.bottomright.curvepath", selected: false)
            Spacer()
        }
        .padding(12).frame(width: 300, height: 820, alignment: .top).background(Color(nsColor: .windowBackgroundColor))
        _ = model
        try await Snapshot.render(view, screen: "sidebar", state: "redesign-selected", sizes: [size], chrome: .bare)
    }

    private func selectedRow(_ title: String, _ image: String, selected: Bool) -> some View {
        SidebarRow(title, systemImage: image)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background(selected ? IterColor.accent : Color.clear, in: RoundedRectangle(cornerRadius: 8))
            .environment(\.backgroundProminence, selected ? .increased : .standard)
    }
}
