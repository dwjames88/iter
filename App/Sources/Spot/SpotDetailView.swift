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
                SpotHeaderView(spot: liveSpot, nextEvent: page.upcomingWindows.first, today: page.today, zone: page.timeZone)
                LookAroundSection(coordinate: liveSpot.coordinate)
                SpotFactsSection(spot: liveSpot, page: page)
                LightTimelineSection(page: page)
                OutlookSection(page: page)
                HourlyWeatherSection(page: page)
                WindySection(coordinate: liveSpot.coordinate)
            }
            .padding(.horizontal, IterSpace.xl)
            .padding(.vertical, IterSpace.xl)
            .frame(maxWidth: SpotLayout.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(IterColor.backgroundWindow)
        .safeAreaInset(edge: .top, spacing: 0) { WeatherStatusBanner(status: model.weatherStatus) }
        .navigationTitle(liveSpot.name)
        .task { await page.start() }
        .onChange(of: liveSpot) { _, new in page.update(spot: new) }
    }

    /// The spot as the store has it now (a saved or own spot can be edited from this page).
    private var liveSpot: Spot {
        guard model.store.revision >= 0 else { return page.spot }
        return model.store.current(page.spot)
    }
}
