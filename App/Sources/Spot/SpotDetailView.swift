import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// The spot page, pushed onto a section's navigation stack from Explore, Saved, Scout and trips. It answers
/// "when should I be here?" in the first viewport, then shows the evidence: windows, timeline, sun and moon, weather.
struct SpotDetailView: View {
    @Environment(AppModel.self) private var model
    let spot: Spot
    var initialDay: LocalDay?

    var body: some View {
        SpotPage(app: model, spot: spot, initialDay: initialDay)
    }
}

struct SpotPage: View {
    @Environment(AppModel.self) private var model
    @State private var page: SpotModel

    init(app: AppModel, spot: Spot, initialDay: LocalDay?) {
        _page = State(initialValue: SpotModel(app: app, spot: spot, initialDay: initialDay))
    }

    /// For snapshots and previews: a page with its state already set.
    init(model: SpotModel) {
        _page = State(initialValue: model)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: IterSpace.xl) {
                SpotHeaderView(spot: liveSpot)
                WhenToGoSection(page: page)
                DayWindowsSection(page: page)
                LightTimelineSection(page: page)
                SkyArcSection(page: page)
                HourlyWeatherSection(page: page)
                WindySection(coordinate: liveSpot.coordinate)
                SpotFactsSection(spot: liveSpot)
                LookAroundSection(coordinate: liveSpot.coordinate)
            }
            .padding(.horizontal, IterSpace.xl)
            .padding(.vertical, IterSpace.xl)
            .frame(maxWidth: SpotLayout.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(IterColor.backgroundWindow)
        .navigationTitle(liveSpot.name)
        .task { await page.start() }
        .onChange(of: liveSpot) { _, new in page.update(spot: new) }
    }

    /// The spot as the store has it now (a user's spot can be edited from this page).
    private var liveSpot: Spot {
        let spot = page.spot
        guard spot.origin == .user, model.store.revision >= 0, let id = UUID(uuidString: spot.id), let record = model.store.place(id: id) else { return spot }
        return record.spot
    }
}
