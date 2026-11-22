import SwiftUI
import Testing
@testable import IterUI

@MainActor
@Suite("Sidebar snapshots")
struct SidebarSnapshotTests {
    /// Selected row: the list's selection fill behind the row (a plain `List` is not needed to show the state).
    private func selected<V: View>(@ViewBuilder _ row: () -> V) -> some View {
        row()
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(IterColor.selection, in: .rect(cornerRadius: 10, style: .continuous))
    }

    private var bottomBar: some View {
        SidebarBottomBar(infoLabel: "What the scores mean", addLabel: "New Trip or Location",
                         legend: { Text("Legend").padding() },
                         addItems: { Button("New Trip") {}; Button("New Location") {} })
    }

    @Test func parts() async throws {
        let view = VStack(alignment: .leading, spacing: 10) {
            SidebarSectionHeader("Locations").font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
            SidebarRow("Explore", systemImage: "binoculars")
            SidebarRow("Saved Locations", systemImage: "mappin.and.ellipse", count: 24)
            selected { SidebarRow("All Trips", systemImage: "map", isSelected: true, accessory: { EmptyView() }) }
            SidebarDisclosureRow("All Locations", systemImage: "mappin.and.ellipse", tag: 0,
                                 storageKey: "snap.expanded", hasChildren: true) {
                SidebarRow("California", systemImage: "folder")
            }
            SidebarDisclosureRow("All Trips", systemImage: "map", tag: 1,
                                 storageKey: "snap.none", hasChildren: false) { EmptyView() }
            SidebarSearchField(text: .constant(""), prompt: "Search Places or Ask Iter")
            SidebarSearchField(text: .constant("Moab"), prompt: "Search Places or Ask Iter")
            bottomBar
        }
        .padding(12)
        try await Snapshot.assertMatches(view, name: "sidebar-parts", size: CGSize(width: 280, height: 430),
                                         background: IterColor.backgroundWindow)
    }

    @Test func panel() async throws {
        let view = VStack(alignment: .leading, spacing: 0) {
            SidebarSearchField(text: .constant(""), prompt: "Search Places or Ask Iter")
                .padding(.horizontal, 12).padding(.top, 12)
            VStack(alignment: .leading, spacing: 4) {
                section("Explore") { SidebarRow("Explore", systemImage: "binoculars") }
                section("Locations") {
                    SidebarRow("All Locations", systemImage: "mappin.and.ellipse", count: 24)
                    SidebarRow("California", systemImage: "folder", count: 9).padding(.leading, 20)
                }
                section("Trips") {
                    selected { SidebarRow("All Trips", systemImage: "map", count: 2, isSelected: true) }
                    SidebarRow("Canyon Country", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .padding(.leading, 20)
                }
            }
            .padding(.horizontal, 12).padding(.top, 16)
            Spacer(minLength: 0)
            bottomBar
        }
        try await Snapshot.assertMatches(view, name: "sidebar-panel", size: CGSize(width: 280, height: 700),
                                         background: IterColor.backgroundWindow)
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ rows: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            SidebarSectionHeader(title).font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.top, 8)
            rows().padding(.horizontal, 8)
        }
    }
}
