import SwiftUI
import IterCore
import IterData
import IterDesign
import IterServices
import IterFeatures

enum SettingsTab: Hashable { case general, weather, intelligence, updates, licence, about }

/// The Settings window: General, Weather, Apple Intelligence, Updates, About; Licence too, when launched with `-IterShowLicensing YES`.
struct SettingsView: View {
    @State private var tab: SettingsTab

    init(initialTab: SettingsTab = AppLaunch.settingsTab ?? .general) {
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        TabView(selection: $tab) {
            GeneralSettingsPane()
                .tabItem { Label(String(localized: "General", comment: "Settings tab"), systemImage: "gearshape") }
                .tag(SettingsTab.general)
            WeatherSettingsPane()
                .tabItem { Label(String(localized: "Weather", comment: "Settings tab"), systemImage: "cloud.sun") }
                .tag(SettingsTab.weather)
            IntelligenceSettingsPane()
                .tabItem { Label(String(localized: "Apple Intelligence", comment: "Settings tab"), systemImage: "sparkles") }
                .tag(SettingsTab.intelligence)
            #if os(macOS)
            UpdatesSettingsPane()
                .tabItem { Label(String(localized: "Updates", comment: "Settings tab"), systemImage: "arrow.down.circle") }
                .tag(SettingsTab.updates)
            #endif
            if AppLaunch.showLicensing {
                LicenceSettingsPane()
                    .tabItem { Label(String(localized: "Licence", comment: "Settings tab"), systemImage: "key") }
                    .tag(SettingsTab.licence)
            }
            AboutSettingsPane()
                .tabItem { Label(String(localized: "About", comment: "Settings tab"), systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .scenePadding()
        .frame(width: IterSize.listMax + IterSpace.xxl)
        .snapshotOpaqueBackground()
    }
}

// MARK: - General

private struct GeneralSettingsPane: View {
    @AppStorage(AppSettings.temperatureUnit) private var temperatureUnit = "system"
    @AppStorage(AppSettings.defaultSetUpBuffer) private var setUpBuffer = 20

    var body: some View {
        Form {
            Section {
                Picker(selection: $temperatureUnit) {
                    Text("System", comment: "Temperature unit follows the system").tag("system")
                    Text("Celsius (°C)", comment: "Temperature unit").tag("celsius")
                    Text("Fahrenheit (°F)", comment: "Temperature unit").tag("fahrenheit")
                } label: { Text("Temperature", comment: "Settings field") }
            }
            Section {
                Stepper(value: $setUpBuffer, in: 0...90, step: 5) {
                    Text("Set-up time before a window: \(setUpBuffer) min", comment: "Settings field with its value, e.g. Set-up time before a window: 20 min")
                }
            } footer: {
                Text("How long before a light window starts that a new stop wants you set up. Each stop can change it.", comment: "Settings footer")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Apple Intelligence

private struct IntelligenceSettingsPane: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL

    var body: some View {
        let availability = model.scout?.availability() ?? .unavailable("")
        Form {
            Section {
                if availability == .available {
                    Label {
                        Text("Apple Intelligence is ready", comment: "Settings Apple Intelligence status")
                    } icon: { Image(systemName: "checkmark.circle") }
                } else {
                    let notice = LightText.askUnavailable(availability)
                    Label(notice.title, systemImage: notice.symbol)
                    if availability == .appleIntelligenceNotEnabled, let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") {
                        Button { openURL(url) } label: { Text("Open System Settings", comment: "Button") }
                    }
                }
            } header: {
                Text("Ask Iter", comment: "Settings section: the Apple Intelligence search in Explore")
            } footer: {
                if availability == .available {
                    Text("Ask Iter, in Explore's search, understands your request with the model on this Mac, then looks up real places in Apple Maps and Iter's curated list.",
                         comment: "Settings: how Ask Iter works")
                } else {
                    Text(LightText.askUnavailable(availability).detail)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

private struct AboutSettingsPane: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        Form {
            Section {
                VStack(spacing: IterSpace.sm) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: IterSize.lightRingLarge)
                        .accessibilityLabel(Text("Iter", comment: "App name"))
                    Text("Iter", comment: "App name").font(IterFont.titleSection)
                    Text(version).foregroundStyle(IterColor.textSecondary)
                    Text("Be in the right place when the light is right.", comment: "Tagline")
                }
                .frame(maxWidth: .infinity)
            }
            Section {
                WeatherDataSources()
            } header: {
                Text("Data Sources and Attribution", comment: "About: heading for provider credits")
            } footer: {
                Text("Sun and moon times are calculated on this Mac. Weather is from the source you choose in Settings ▸ Weather: Apple Weather, OpenWeather or Windy (contains data from the Windy database). Places and drive times are from Apple Maps, alongside Iter's curated spots.",
                     comment: "About: data sources")
            }
        }
        .formStyle(.grouped)
        .task { await model.loadAttribution() }
    }

    private var version: String { VersionText.current }
}
