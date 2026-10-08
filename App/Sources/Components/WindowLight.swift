import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// A light window named by its symbol (list rows, pins, cards, trip stops). The word stays available as the tooltip
/// and the VoiceOver label; headings on the spot page keep the word itself.
struct WindowSymbol: View {
    let kind: LightWindowKind
    var font: Font = .system(size: IterSize.windowSymbol)
    /// nil: the standalone colour, which is `light/blueHour` for the blue-hour windows and `text/secondary` otherwise.
    var color: AnyShapeStyle? = nil

    private var standaloneColor: AnyShapeStyle {
        switch kind {
        case .blueMorning, .blueEvening: AnyShapeStyle(IterColor.blueHour)
        case .goldenMorning, .goldenEvening, .night: AnyShapeStyle(IterColor.textSecondary)
        }
    }

    var body: some View {
        Image(systemName: LightText.symbol(kind))
            .symbolRenderingMode(.monochrome)
            .font(font)
            .foregroundStyle(color ?? standaloneColor)
            .help(LightText.name(kind))
            .accessibilityLabel(LightText.name(kind))
    }
}

extension IterSize {
    /// Window symbols in compact places (rows, cards, trip stops).
    static let windowSymbol: CGFloat = 16
}

/// The one place a screen says there is no weather: no key, offline, or a provider error. Rows keep their last
/// cached score under it, or leave the score slot empty; nothing per row says "No forecast".
struct WeatherStatusBanner: View {
    let status: WeatherStatus
    @Environment(AppModel.self) private var model
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #else
    @Environment(\.openIterSettings) private var openSettings
    #endif

    var body: some View {
        if let message = WeatherStatusText.message(status) {
            HStack(alignment: .center, spacing: IterSpace.sm) {
                Image(systemName: WeatherStatusText.symbol(status))
                    .foregroundStyle(IterColor.textSecondary)
                    .accessibilityHidden(true)
                Text(message)
                    .font(IterFont.caption)
                    .foregroundStyle(IterColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if WeatherStatusText.offersSetup(status) {
                    Button(String(localized: "Set Up Weather…", comment: "Weather banner: opens the weather setup guide")) {
                        model.onboarding.present(at: .weather)
                    }
                    .controlSize(.small)
                    .help(String(localized: "Set up OpenWeather", comment: "Tooltip"))
                } else if WeatherStatusText.offersSettings(status) {
                    Button(String(localized: "Settings…", comment: "Weather banner: open Settings ▸ Weather")) { openSettings() }
                        .controlSize(.small)
                        .help(String(localized: "Open Settings", comment: "Tooltip"))
                }
            }
            .padding(.horizontal, IterSpace.md)
            .padding(.vertical, IterSpace.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ControlFill())
            .overlay(alignment: .bottom) { Divider() }
            .accessibilityElement(children: .combine)
        }
    }
}

enum WeatherStatusText {
    /// nil when weather is working (no banner).
    static func message(_ status: WeatherStatus) -> String? {
        switch status {
        case .ok:
            return nil
        case .needsKey:
            return String(localized: "Add a weather key in Settings to see light scores.",
                          comment: "Weather banner: no API key for the chosen provider")
        case .offline(_, let last):
            guard let last else {
                return String(localized: "Weather is offline. Scores appear when it's back.",
                              comment: "Weather banner: offline, nothing cached")
            }
            return String(localized: "Weather is offline. Scores are from the last update at \(updateTime(last)).",
                          comment: "Weather banner: offline; argument is the time of the last successful forecast")
        case .failed(let reason, let last):
            let what = failure(reason)
            guard let last else { return what }
            return String(localized: "\(what) Scores are from the last update at \(updateTime(last)).",
                          comment: "Weather banner: a provider error, then the time of the last successful forecast")
        }
    }

    static func symbol(_ status: WeatherStatus) -> String {
        switch status {
        case .ok: "checkmark.circle"
        case .needsKey: "key"
        case .offline: "wifi.slash"
        case .failed: "exclamationmark.triangle"
        }
    }

    /// The banner opens the weather setup guide (not Settings) when there is no key, or Apple Weather cannot run.
    static func offersSetup(_ status: WeatherStatus) -> Bool {
        switch status {
        case .needsKey: true
        case .failed(.weatherServiceNotEnabled, _): true
        default: false
        }
    }

    static func offersSettings(_ status: WeatherStatus) -> Bool {
        switch status {
        case .needsKey: true
        case .failed(let reason, _):
            switch reason {
            case .keyRejected, .testingKey, .dailyLimitReached, .weatherServiceNotEnabled: true
            default: false
            }
        case .ok, .offline: false
        }
    }

    private static func failure(_ reason: ForecastUnavailableReason) -> String {
        switch reason {
        case .weatherServiceNotEnabled:
            String(localized: "Apple Weather isn't available in this build. Set up OpenWeather to see light scores.",
                   comment: "Weather banner: WeatherKit not provisioned")
        case .keyRejected(let source):
            String(localized: "\(LightText.name(source)) rejected the weather key. Check it in Settings.",
                   comment: "Weather banner: key rejected; argument is the provider")
        case .dailyLimitReached(let source):
            String(localized: "Iter's daily limit for \(LightText.name(source)) is reached.",
                   comment: "Weather banner: the daily call cap; argument is the provider")
        case .testingKey(let source):
            String(localized: "\(LightText.name(source))'s testing key gives shuffled data, so Iter won't score from it.",
                   comment: "Weather banner: testing key; argument is the provider")
        case .providerFailed(let source, _), .offline(let source):
            String(localized: "\(LightText.name(source)) isn't answering.",
                   comment: "Weather banner: a provider failed; argument is the provider")
        case .missingAPIKey:
            String(localized: "Add a weather key in Settings to see light scores.",
                   comment: "Weather banner: no API key for the chosen provider")
        case .serviceFailed, .beyondHorizon, .inThePast, .notLoaded:
            String(localized: "Weather isn't answering.", comment: "Weather banner: generic failure")
        }
    }

    private static func updateTime(_ date: Date) -> String { TimeText.time(date, in: .current) }
}
