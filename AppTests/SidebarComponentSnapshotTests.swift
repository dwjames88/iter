import SwiftUI
import Testing
import IterData
import IterCore
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
}
