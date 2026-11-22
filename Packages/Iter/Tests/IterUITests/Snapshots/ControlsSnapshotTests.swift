import SwiftUI
import Testing
@testable import IterUI

@MainActor
@Suite("Controls snapshots")
struct ControlsSnapshotTests {
    @Test func glassCircleButton() async throws {
        let view = VStack(alignment: .leading, spacing: 16) {
            ForEach([32.0, 36.0], id: \.self) { d in
                HStack(spacing: 16) {
                    ForEach(["square.and.arrow.up", "xmark", "ellipsis"], id: \.self) { name in
                        Button {} label: { Image(systemName: name) }
                            .buttonStyle(GlassCircleButtonStyle(diameter: d))
                    }
                }
            }
        }
        .padding(20)
        try await Snapshot.assertMatches(view, name: "controls-glass-circle-button", size: CGSize(width: 190, height: 130),
                                         background: IterColor.backgroundWindow)
    }

    @Test func placeActions() async throws {
        let view = HStack(spacing: 8) {
            Button {} label: { Label("Add to Trip", systemImage: "plus") }.placeAction(isProminent: true)
            Button {} label: { Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill") }.placeAction()
            Button {} label: { Label("Open in Maps", systemImage: "map") }.placeAction()
            Button {} label: { Label("Share", systemImage: "square.and.arrow.up") }.placeAction()
        }
        .padding(16)
        try await Snapshot.assertMatches(view, name: "controls-place-actions", size: CGSize(width: 372, height: 84),
                                         background: IterColor.backgroundWindow)
    }

    @Test func mapStack() async throws {
        let view = MapControlStack(actions: {
            MapControlButton(title: "Windy", systemImage: "wind") {}
            MapControlButton(title: "Add Spot", systemImage: "mappin.and.ellipse", isOn: true) {}
        }, controls: {
            MapControlButton(title: "Map Style", systemImage: "map") {}
            MapControlButton(title: "Show Your Location", systemImage: "location") {}
        }, accessories: {
            Image(systemName: "plus.magnifyingglass").frame(width: 36, height: 36)
        })
        try await Snapshot.assertMatches(view, name: "controls-map-stack", size: CGSize(width: 80, height: 260),
                                         background: IterColor.backgroundContent)
    }
}
