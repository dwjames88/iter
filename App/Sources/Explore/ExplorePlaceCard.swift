import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// The place card over the map for the selected spot (pattern #6): a pinned header (what it is, its next window),
/// then a scrolling body. It opens on images of the site; scrolling up reveals the spot page's own sections (weather,
/// light windows, sun and moon, facts) at compact density, then Save, Add to Trip and a link to the full page.
struct ExplorePlaceCard: View {
    let row: ExploreRow
    /// The card's size, set by the map pane from the pane's size (see `ExploreMapPane`).
    var size = CGSize(width: IterSize.placeCardWidth, height: IterSize.placeCardMaxHeight)
    /// Start scrolled to the actions at the bottom. Debug and snapshot aid; `-IterCardScrolled YES` sets it at launch.
    var startsScrolled = AppLaunch.cardScrolled
    var onClose: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.renderMode) private var renderMode

    private var spot: Spot { row.spot }
    /// The day of the row's next window; today at the spot when there is none.
    private var day: LocalDay { row.day ?? model.today(in: spot.timeZone) }
    private static let actionsID = "place-card-actions"

    /// How long after appearing the card keeps re-scrolling to the actions as its content grows (launch flag only).
    private static let settleWindow = Duration.seconds(4)
    private static let settleDelay = Duration.milliseconds(100)

    @State private var scrollSettling = false

    private struct ContentKey: Hashable { let spotID: String; let day: LocalDay }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: IterSpace.lg) {
                        SpotImages(spot: spot)
                        VStack(alignment: .leading, spacing: IterSpace.lg) {
                            PlaceCardSections(app: model, spot: spot, day: day)
                                .id(ContentKey(spotID: spot.id, day: day))
                            VStack(alignment: .leading, spacing: IterSpace.lg) {
                                actions
                                footer
                            }
                            .id(Self.actionsID)
                        }
                        .padding(.horizontal, IterGrid.inset)
                        .padding(.bottom, IterGrid.inset)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
                .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentSize.height }) { _, _ in
                    // The forecast and sections load and grow the content; keep the actions at the bottom meanwhile.
                    guard scrollSettling else { return }
                    Task {
                        try? await Task.sleep(for: Self.settleDelay)
                        proxy.scrollTo(Self.actionsID, anchor: .bottom)
                    }
                }
                .task(id: spot.id) {
                    guard startsScrolled else { return }
                    scrollSettling = true
                    try? await Task.sleep(for: Self.settleDelay)
                    proxy.scrollTo(Self.actionsID, anchor: .bottom)
                    try? await Task.sleep(for: Self.settleWindow)
                    scrollSettling = false
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .background(background)
        .layoutGrid()
        .clipShape(shape)
        .shadow(radius: IterSpace.xs)
        .environment(\.spotDensity, .compact)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Place card for \(spot.name)", comment: "VoiceOver"))
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: IterRadius.panel, style: .continuous) }

    // MARK: Header (pinned)

    private var header: some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            HStack(alignment: .top, spacing: IterSpace.sm) {
                VStack(alignment: .leading, spacing: IterSpace.xs) {
                    Text(spot.name).font(IterFont.titleSection).foregroundStyle(IterColor.textPrimary)
                        .lineLimit(2)
                    HStack(spacing: IterSpace.xs) {
                        if !spot.locality.isEmpty {
                            Text(spot.locality).lineLimit(1)
                            Text(verbatim: "·")
                        }
                        ProvenanceTag(origin: spot.origin)
                    }
                    .font(IterFont.secondary)
                    .foregroundStyle(IterColor.textSecondary)
                }
                Spacer(minLength: IterSpace.sm)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(IterColor.textTertiary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Deselect", comment: "Tooltip on the place card's close button"))
                .accessibilityLabel(Text("Close", comment: "VoiceOver"))
            }
            lightSummary
        }
        .padding(IterGrid.inset)
    }

    /// The card's one strong fact: the next window as the large event unit, "Tomorrow" beside it on the same baseline.
    @ViewBuilder private var lightSummary: some View {
        if let window = row.window {
            HStack(alignment: .firstTextBaseline, spacing: IterSpace.sm) {
                EventScore(window: window, zone: spot.timeZone, timeStyle: .start, variant: .large,
                           isLoading: row.isLoading, isTomorrow: LightText.isTomorrow(row))
                if LightText.isTomorrow(row) {
                    Text("Tomorrow", comment: "Place card: the next window is tomorrow")
                        .font(IterFont.secondary)
                        .foregroundStyle(IterColor.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(LightText.rowLight(row) ?? "")
        }
    }

    // MARK: Body parts

    private var actions: some View {
        HStack(spacing: IterSpace.sm) {
            if spot.origin != .user {
                saveButton
            }
            AddToTripMenu(spot: spot)
                .menuStyle(.button)
                .fixedSize()
            Spacer(minLength: 0)
        }
        .controlSize(.regular)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: IterSpace.sm) {
            if let forecast = model.forecasts.state(for: spot.coordinate).forecast {
                ForecastSourceLine(info: ForecastSourceInfo(forecast))
                    .font(IterFont.secondary)
            }
            Button {
                ExploreActions.open(spot, day: day, navigation: navigation)
            } label: {
                Text("Show Full Page", comment: "Place card: open the spot's full page")
                    .font(IterFont.secondary)
            }
            .buttonStyle(.link)
            .help(String(localized: "Open the spot page", comment: "Tooltip"))
        }
    }

    private var saveButton: some View {
        let saved = isSaved
        return Button {
            model.store.setSaved(spot, !saved)
        } label: {
            if saved {
                Label(String(localized: "Saved", comment: "Place card: the spot is saved"), systemImage: "bookmark.fill")
            } else {
                Label(String(localized: "Save", comment: "Place card: save the spot"), systemImage: "bookmark")
            }
        }
        .help(saved ? String(localized: "Remove from Saved", comment: "Tooltip") : String(localized: "Save this spot", comment: "Tooltip"))
    }

    private var isSaved: Bool {
        _ = model.store.revision
        return model.store.isSaved(spotID: spot.id)
    }

    private var background: AnyShapeStyle {
        // An offscreen render has no backdrop for materials.
        renderMode == .snapshot ? AnyShapeStyle(IterColor.backgroundContent) : AnyShapeStyle(.regularMaterial)
    }
}

/// The spot page's own sections for the card, at compact density. Owns its `SpotModel`; the card keys it by spot and
/// day so a new selection starts a new model.
private struct PlaceCardSections: View {
    @State private var page: SpotModel
    let spot: Spot

    init(app: AppModel, spot: Spot, day: LocalDay) {
        self.spot = spot
        _page = State(initialValue: SpotModel(app: app, spot: spot, initialDay: day))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.lg) {
            WhenToGoSection(page: page)
            DayWindowsSection(page: page)
            LightTimelineSection(page: page)
            SkyArcSection(page: page)
            HourlyWeatherSection(page: page)
            SpotFactsSection(spot: spot)
        }
        .environment(\.spotDensity, .compact)
        .task { await page.start() }
    }
}
