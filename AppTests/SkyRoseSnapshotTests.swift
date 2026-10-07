import SwiftUI
import Testing
import IterCore
import IterData
import IterDesign
import IterFeatures
@testable import Iter

/// The Sun and moon module alone (Mac panel and Mac spot page), at the states that matter for the rose.
@MainActor
@Suite(.serialized) struct SkyRoseSnapshotTests {
    private static let denver = TimeZone(identifier: "America/Denver")!
    private static let day = LocalDay(year: 2026, month: 10, day: 6)

    private struct State {
        let name: String
        let facing: Double?
        let hour: Int
        let minute: Int
        var viewUp = false
    }

    private static let states = [
        State(name: "morning-sunrise-in-view", facing: 100, hour: 8, minute: 0),
        State(name: "sunset-in-view", facing: 263, hour: 18, minute: 45),
        State(name: "sunset-missed", facing: 190, hour: 18, minute: 45),
        State(name: "view-up", facing: 190, hour: 18, minute: 45, viewUp: true),
        State(name: "no-facing", facing: nil, hour: 12, minute: 30),
    ]

    private func page(_ state: State, model: AppModel) async -> SpotModel {
        var spot = CuratedSpots.spot(id: "mesa-arch")!
        spot.facing = state.facing
        let page = SpotModel(app: model, spot: spot, initialDay: Self.day)
        await page.start()
        page.setTime(Self.day.at(hour: state.hour, minute: state.minute, in: Self.denver))
        return page
    }

    private func render(density: SpotDensity, width: CGFloat, height: CGFloat, padding: CGFloat, prefix: String) async throws {
        for state in Self.states {
            let model = Fixtures.model(weather: .sample)
            let page = await page(state, model: model)
            let view = LightTimelineSection(page: page, viewUp: state.viewUp)
                .environment(\.spotDensity, density)
                .padding(.horizontal, padding)
                .frame(width: width, alignment: .top)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(IterColor.backgroundWindow)
            try await Snapshot.render(Fixtures.host(view, model: model), screen: "skyrose", state: "\(prefix)-\(state.name)",
                                      sizes: [Snapshot.Size(name: "\(Int(width))x\(Int(height))", width: width, height: height)],
                                      settle: .milliseconds(500), chrome: .bare)
        }
    }

    @Test(.enabled(if: Snapshot.enabled)) func panel() async throws {
        try await render(density: .panel, width: 360, height: 1500, padding: 0, prefix: "panel")
    }

    @Test(.enabled(if: Snapshot.enabled)) func page() async throws {
        let column = SpotLayout.contentMaxWidth
        try await render(density: .page, width: column + IterSpace.xl * 2, height: 1250, padding: IterSpace.xl, prefix: "page")
    }
}
