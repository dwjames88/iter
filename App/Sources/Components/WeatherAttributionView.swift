import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// Which provider (and model) a shown forecast came from. Built from a `Forecast`, or from the forecasts behind a
/// list of places, so a fallback is never hidden behind the provider the user chose.
struct ForecastSourceInfo: Hashable, Identifiable {
    var source: ForecastSource
    var model: String?
    /// nil in lists, where each place has its own fetch time.
    var fetchedAt: Date?
    var fallbackFrom: [ForecastSource]

    var id: String { "\(source.rawValue)/\(model ?? "")/\(fallbackFrom.map(\.rawValue).joined(separator: ","))" }

    init(source: ForecastSource, model: String? = nil, fetchedAt: Date? = nil, fallbackFrom: [ForecastSource] = []) {
        self.source = source
        self.model = model
        self.fetchedAt = fetchedAt
        self.fallbackFrom = fallbackFrom
    }

    init(_ forecast: Forecast, includesTime: Bool = true) {
        self.init(source: forecast.source, model: forecast.model, fetchedAt: includesTime ? forecast.fetchedAt : nil,
                  fallbackFrom: forecast.fallbackFrom)
    }

    /// The distinct sources behind the forecasts loaded for `coordinates`, in first-seen order.
    @MainActor static func distinct(for coordinates: [Coordinate], app: AppModel) -> [ForecastSourceInfo] {
        var seen: [ForecastSourceInfo] = []
        for coordinate in coordinates {
            guard let forecast = app.forecasts.state(for: coordinate).forecast else { continue }
            let info = ForecastSourceInfo(forecast, includesTime: false)
            if !seen.contains(where: { $0.id == info.id }) { seen.append(info) }
        }
        return seen
    }

    /// The provider the user has chosen, used for the attribution when no forecast is on screen yet.
    @MainActor static func configured(app: AppModel) -> ForecastSource {
        app.sampleDataEnabled ? .sample : app.forecasts.source
    }
}

/// "Windy · GFS · updated 19:40", or without the time in lists. Words, not a logo: the legal attribution sits beside it.
struct ForecastSourceLine: View {
    let info: ForecastSourceInfo

    init(info: ForecastSourceInfo) { self.info = info }

    init(source: ForecastSource, model: String? = nil, fetchedAt: Date? = nil, fallbackFrom: [ForecastSource] = []) {
        self.info = ForecastSourceInfo(source: source, model: model, fetchedAt: fetchedAt, fallbackFrom: fallbackFrom)
    }

    var body: some View {
        Text(text)
            .font(IterFont.caption)
            .foregroundStyle(IterColor.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var text: String {
        if let fetchedAt = info.fetchedAt {
            return LightText.sourceUpdated(info.source, model: info.model, fetchedAt: fetchedAt, fallbackFrom: info.fallbackFrom)
        }
        return LightText.sourceLabel(info.source, model: info.model, fallbackFrom: info.fallbackFrom)
    }
}

/// What each provider's licence requires wherever its data appears, plus Iter's own "modified data" notice.
/// Apple Weather: the mark and the legal link. OpenWeather: "Weather data © OpenWeather" linking to its licence page.
/// Windy: "Contains data from the Windy database" and a link to windy.com. Sample data says so instead.
struct WeatherAttributionView: View {
    let sources: [ForecastSource]
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme

    init(sources: [ForecastSource]) {
        var unique: [ForecastSource] = []
        for source in sources where !unique.contains(source) { unique.append(source) }
        self.sources = unique
    }

    init(source: ForecastSource) { self.init(sources: [source]) }

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.xxs) {
            ForEach(sources) { source in
                attribution(for: source)
            }
            if sources.contains(where: { $0 != .sample }) {
                Text("Light Index modified from forecast data", comment: "Value-added data notice under weather")
                    .font(IterFont.caption)
                    .foregroundStyle(IterColor.textTertiary)
            }
        }
    }

    @ViewBuilder private func attribution(for source: ForecastSource) -> some View {
        let info = model.attribution(for: source)
        switch source {
        case .sample:
            SampleDataLabel(style: .inline)
        case .appleWeather:
            if let info {
                HStack(spacing: IterSpace.sm) {
                    AsyncImage(url: colorScheme == .dark ? info.combinedMarkDarkURL : info.combinedMarkLightURL) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        Text(info.serviceName).font(IterFont.caption)
                    }
                    .frame(height: IterSize.iconSmall)
                    .accessibilityLabel(info.serviceName)
                    Link(String(localized: "Legal attribution", comment: "Link to Apple Weather legal attribution"), destination: info.legalPageURL)
                        .font(IterFont.caption)
                }
            }
        case .openWeather:
            let text = info?.requiredText ?? String(localized: "Weather data © OpenWeather", comment: "OpenWeather attribution required by its licence")
            if let url = info?.legalPageURL {
                Link(text, destination: url).font(IterFont.caption)
            } else {
                Text(text).font(IterFont.caption)
            }
        case .windy:
            // TODO(Windy logo): Windy's API terms also require its logo, unscaled and linking to windy.com. Iter does not
            // ship the logo asset yet, so the text and a visible windy.com link stand in until it is added.
            HStack(spacing: IterSpace.xs) {
                Text(info?.requiredText ?? String(localized: "Contains data from the Windy database", comment: "Windy attribution required by its API terms"))
                    .font(IterFont.caption)
                Link(String(localized: "Windy.com", comment: "Link to windy.com in the Windy attribution"), destination: WindyLink.home)
                    .font(IterFont.caption)
            }
        }
    }
}

/// The source line(s) and attribution together, for places that show many forecasts (lists, footers):
/// one line per distinct source, then the attribution. With no forecast loaded, only the configured provider's attribution.
struct ForecastSourceFooter: View {
    let infos: [ForecastSourceInfo]
    let configured: ForecastSource

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.xxs) {
            ForEach(infos) { info in
                if info.source != .sample { ForecastSourceLine(info: info) }
            }
            WeatherAttributionView(sources: infos.isEmpty ? [configured] : infos.map(\.source))
        }
    }
}

extension ForecastSourceFooter {
    /// For the forecasts behind `coordinates`.
    @MainActor init(app: AppModel, coordinates: [Coordinate]) {
        self.init(infos: ForecastSourceInfo.distinct(for: coordinates, app: app), configured: ForecastSourceInfo.configured(app: app))
    }
}
