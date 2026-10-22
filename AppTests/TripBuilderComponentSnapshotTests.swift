import SwiftUI
import Testing
import IterCore
import IterDesign
@testable import Iter

/// The Trip Builder components one by one, light and dark: files `tbc-<component>-<scheme>-<W>x<H>.png`.
@MainActor
@Suite(.serialized) struct TripBuilderComponentSnapshotTests {
    private let settle = Duration.milliseconds(300)

    private func render<V: View>(_ name: String, width: CGFloat, height: CGFloat, ground: Color = IterColor.backgroundWindow,
                                 @ViewBuilder _ content: () -> V) async throws {
        let view = content()
            .frame(width: width, height: height, alignment: .topLeading)
            .background(ground)
        try await Snapshot.render(view, screen: "tbc", state: name,
                                  sizes: [Snapshot.Size(name: "\(Int(width))x\(Int(height))", width: width, height: height)],
                                  settle: settle, chrome: .bare)
    }

    @Test(.enabled(if: Snapshot.enabled)) func headerCard() async throws {
        try await render("header-card", width: 672, height: 150) { HeaderCardPreview() }
    }

    @Test(.enabled(if: Snapshot.enabled)) func daySelector() async throws {
        try await render("day-selector", width: 672, height: 140) {
            VStack(spacing: 0) {
                DaySelector(items: DaySelectorPreview.items, selectedDay: 0) { _ in }
                DaySelector(items: DaySelectorPreview.items, selectedDay: nil) { _ in }
            }
        }
    }

    @Test(.enabled(if: Snapshot.enabled)) func dayHeader() async throws {
        try await render("day-header", width: 672, height: 200) { DayHeaderPreview() }
    }

    @Test(.enabled(if: Snapshot.enabled)) func stopCard() async throws {
        try await render("stop-card", width: 672, height: 520) { StopCardPreview(selected: true) }
    }

    @Test(.enabled(if: Snapshot.enabled)) func driveSegments() async throws {
        try await render("drive-segments", width: 672, height: 330) { DriveSegmentsPreview() }
    }

    @Test(.enabled(if: Snapshot.enabled)) func footer() async throws {
        try await render("footer", width: 672, height: 150) {
            VStack(spacing: 16) {
                footer(overnight: nil)
                footer(overnight: "Overnight near Page, AZ")
            }
            .padding(BuilderMetrics.panelInset)
        }
    }

    private func footer(overnight: String?) -> some View {
        HStack(spacing: 8) {
            AddStopButton {}
            Spacer(minLength: 8)
            if let overnight { OvernightNote(text: overnight) }
        }
        .padding(12 + BuilderMetrics.bodyInset)
        .background(DayCardBackground(position: .only, inset: 0))
    }

    @Test(.enabled(if: Snapshot.enabled)) func badges() async throws {
        try await render("badges", width: 320, height: 80) {
            HStack(spacing: IterSpace.lg) {
                NumberBadge(number: 1)
                NumberBadge(number: 2, style: .neutral)
                DriveBadge()
                FindHotelsButton(coordinate: Coordinate(latitude: 36.9, longitude: -111.45))
            }
            .padding(BuilderMetrics.panelInset)
        }
    }
}
