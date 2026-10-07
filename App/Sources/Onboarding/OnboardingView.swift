import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import IterCore
import IterDesign
import IterServices
import IterFeatures

/// The first-run guide: welcome, location, weather key, Ask, done. One sheet, one step at a time, driven by
/// `AppModel.onboarding`. Shared by the Mac and iOS apps; the host presents it as a sheet and calls
/// `onboarding.dismissed()` from the sheet's `onDismiss`.
struct OnboardingView: View {
    /// The sheet's width on the Mac; the height follows the content.
    static let sheetWidth: CGFloat = 560

    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var keyCheck: OpenWeatherKeyCheck
    @State private var saveFailed = false
    /// Bumped when the app becomes active again, so the Apple Intelligence row re-reads availability.
    @State private var activations = 0

    init(keyCheck: OpenWeatherKeyCheck = OpenWeatherKeyCheck()) {
        _keyCheck = State(initialValue: keyCheck)
    }

    private var onboarding: OnboardingModel { model.onboarding }

    var body: some View {
        VStack(spacing: 0) {
            OnboardingStepDots(index: onboarding.position.index, count: onboarding.position.count)
                .padding(.top, IterSpace.xl)
            content
                .padding(.horizontal, IterSpace.xxl)
                .padding(.vertical, IterSpace.xl)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            buttonBar
                .padding(.horizontal, IterSpace.sheet)
                .padding(.vertical, IterSpace.lg)
        }
        .frame(width: Self.sheetWidth)
        .onReceive(NotificationCenter.default.publisher(for: Self.becameActive)) { _ in activations += 1 }
    }

    #if os(macOS)
    private static let becameActive = NSApplication.didBecomeActiveNotification
    #else
    private static let becameActive = UIApplication.didBecomeActiveNotification
    #endif

    @ViewBuilder private var content: some View {
        switch onboarding.step {
        case .welcome: welcome
        case .location: location
        case .weather: weather
        case .intelligence: intelligence
        case .done: done
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: IterSpace.lg) {
            Image("Logo")
                .resizable()
                .scaledToFit()
                .frame(height: IterSize.lightRingLarge)
                .accessibilityHidden(true)
            title(String(localized: "Welcome to Iter", comment: "Onboarding: welcome title"))
            Text("Iter scores sunrise, sunset, golden hour and blue hour for the places you want to photograph.",
                 comment: "Onboarding welcome: what Iter does")
            Text("Find spots, see when the light is best, and plan trips around it.",
                 comment: "Onboarding welcome: how to use Iter")
                .foregroundStyle(IterColor.textSecondary)
        }
        .multilineTextAlignment(.center)
        .font(IterFont.body)
        .frame(maxWidth: .infinity)
    }

    private var location: some View {
        VStack(spacing: IterSpace.lg) {
            symbol("location.circle")
            title(String(localized: "Your location", comment: "Onboarding location: title"))
            Text("Iter uses your location to show spots near you and to start the map where you are. You can search and plan anywhere without it.",
                 comment: "Onboarding location: why Iter asks")
                .font(IterFont.body)
                .multilineTextAlignment(.center)
            switch model.location.authorization {
            case .authorized:
                OnboardingStatusRow(symbol: "checkmark.circle.fill", tint: IterColor.accentText,
                                    text: String(localized: "Location is on.", comment: "Onboarding location: allowed"))
            case .denied, .restricted:
                OnboardingStatusRow(symbol: "location.slash", tint: IterColor.textSecondary, text: Self.locationOff)
            case .notDetermined:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private static var locationOff: String {
        #if os(macOS)
        String(localized: "Location is off. You can turn it on in System Settings ▸ Privacy & Security ▸ Location Services.",
               comment: "Onboarding location: denied (Mac)")
        #else
        String(localized: "Location is off. You can turn it on in Settings ▸ Privacy & Security ▸ Location Services.",
               comment: "Onboarding location: denied (iPhone and iPad)")
        #endif
    }

    private var weather: some View {
        VStack(alignment: .leading, spacing: IterSpace.md) {
            title(String(localized: "Set up weather", comment: "Onboarding weather: title"))
                .frame(maxWidth: .infinity, alignment: .center)
            Text("Light scores need a forecast. Iter uses OpenWeather, which is free for 1,000 calls a day. You bring your own key, and it stays in your Keychain.",
                 comment: "Onboarding weather: intro")
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                numbered(1, String(localized: "Create a free account at OpenWeather.", comment: "Onboarding weather step 1"))
                numbered(2, String(localized: "Subscribe to One Call by Call (One Call API 3.0). The first 1,000 calls each day are free.", comment: "Onboarding weather step 2"))
                numbered(3, String(localized: "On the Billing plan tab, set the daily limit to 1,000 calls so you are never charged.", comment: "Onboarding weather step 3"))
                numbered(4, String(localized: "Open the API keys page and copy your key.", comment: "Onboarding weather step 4"))
            }
            HStack(spacing: IterSpace.md) {
                Button(String(localized: "Open OpenWeather", comment: "Onboarding weather: opens the sign-up page")) {
                    openURL(Self.signUpURL)
                }
                Link(String(localized: "API keys page", comment: "Onboarding weather: link to the keys page"), destination: Self.keysURL)
            }
            if keyCheck.hasSavedKey(in: model.weather) { savedKeyNote }
            TextField(text: Binding(get: { keyCheck.draft }, set: { saveFailed = false; keyCheck.update(draft: $0) })) {
                Text("Paste your API key", comment: "Onboarding weather: key field prompt")
            }
            .font(.system(.body, design: .monospaced))
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .accessibilityLabel(Text("OpenWeather API key", comment: "Onboarding weather: key field accessibility label"))
            keyStatus
            Text("New keys can take up to two hours to start working.", comment: "Onboarding weather: activation delay")
                .font(IterFont.footnote)
                .foregroundStyle(IterColor.textSecondary)
        }
        .font(IterFont.body)
    }

    private static let signUpURL = URL(string: "https://home.openweathermap.org/users/sign_up")!
    private static let keysURL = URL(string: "https://home.openweathermap.org/api_keys")!

    private var savedKeyNote: some View {
        VStack(alignment: .leading, spacing: IterSpace.xxs) {
            Text("A key is already saved in your Keychain.", comment: "Onboarding weather: a key exists")
                .font(IterFont.bodyEmphasis)
            Text(Self.savedStatus(model.weather.status(for: .openWeather)))
                .font(IterFont.footnote)
                .foregroundStyle(IterColor.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }

    private static func savedStatus(_ status: WeatherProviderStatus) -> String {
        switch status {
        case .working: String(localized: "Working", comment: "Onboarding: weather source answers")
        case .keyRejected: String(localized: "OpenWeather rejected this key.", comment: "Onboarding: key rejected by OpenWeather")
        case .failed(let detail): String(localized: "OpenWeather said: \(detail)", comment: "Onboarding: OpenWeather's own error text")
        default: String(localized: "Not checked yet", comment: "Onboarding: the saved key has not been tried yet")
        }
    }

    @ViewBuilder private var keyStatus: some View {
        Group {
            if saveFailed {
                OnboardingStatusRow(symbol: "exclamationmark.triangle.fill", tint: IterColor.warning,
                                    text: String(localized: "Couldn't save the key in your Keychain.", comment: "Onboarding weather: Keychain write failed"))
            } else {
                switch keyCheck.state {
                case .idle:
                    Text(verbatim: " ").accessibilityHidden(true)
                case .invalidFormat:
                    OnboardingStatusRow(symbol: "exclamationmark.circle", tint: IterColor.warning,
                                        text: String(localized: "That doesn't look like an OpenWeather key. Keys are 32 letters and numbers.", comment: "Onboarding weather: key has the wrong shape"))
                case .checking:
                    OnboardingStatusRow(symbol: nil, tint: IterColor.textSecondary,
                                        text: String(localized: "Checking…", comment: "Onboarding weather: testing the key"))
                case .working:
                    OnboardingStatusRow(symbol: "checkmark.circle.fill", tint: IterColor.accentText,
                                        text: String(localized: "Working", comment: "Onboarding: weather source answers"))
                case .failed(let error):
                    OnboardingStatusRow(symbol: "xmark.circle.fill", tint: IterColor.danger, text: Self.message(for: error))
                }
            }
        }
        .font(IterFont.callout)
    }

    private static func message(for error: WeatherError) -> String {
        switch error {
        case .keyRejected:
            String(localized: "OpenWeather rejected this key.", comment: "Onboarding: key rejected by OpenWeather")
        case .offline:
            String(localized: "Can't reach OpenWeather. Check your internet connection.", comment: "Onboarding weather: no network")
        case .overDailyLimit:
            String(localized: "OpenWeather says this key is over its daily limit.", comment: "Onboarding weather: HTTP 429")
        case .failed(let detail), .provider(_, let detail):
            String(localized: "OpenWeather said: \(detail)", comment: "Onboarding: OpenWeather's own error text")
        case .notEnabled, .missingKey, .testingKey:
            String(localized: "OpenWeather said: this key can't be used.", comment: "Onboarding weather: unexpected error")
        }
    }

    private var intelligence: some View {
        VStack(spacing: IterSpace.lg) {
            symbol("sparkles")
            title(String(localized: "Ask Iter", comment: "Onboarding Ask: title"))
            Text("Ask finds places from a plain question, such as “quiet lakes for sunrise near Bishop”, and explains a score in words. It uses Apple Intelligence, which runs on this Mac.",
                 comment: "Onboarding Ask: what it does (Mac)")
                .font(IterFont.body)
                .multilineTextAlignment(.center)
            Text(Self.requirement)
                .font(IterFont.callout)
                .foregroundStyle(IterColor.textSecondary)
                .multilineTextAlignment(.center)
            availabilityRow
        }
        .frame(maxWidth: .infinity)
    }

    private static var requirement: String {
        #if os(macOS)
        String(localized: "Needs a Mac with Apple silicon and Apple Intelligence turned on in System Settings ▸ Apple Intelligence & Siri. Everything else in Iter works without it.",
               comment: "Onboarding Ask: requirement (Mac)")
        #else
        String(localized: "Needs a device that supports Apple Intelligence, turned on in Settings ▸ Apple Intelligence & Siri. Everything else in Iter works without it.",
               comment: "Onboarding Ask: requirement (iPhone and iPad)")
        #endif
    }

    @ViewBuilder private var availabilityRow: some View {
        let _ = activations
        let state = Self.askState(model.scout?.availability())
        HStack(spacing: IterSpace.md) {
            OnboardingStatusRow(symbol: state.available ? "checkmark.circle.fill" : "info.circle",
                                tint: state.available ? IterColor.accentText : IterColor.textSecondary.color, text: state.text)
            if state.offersSettings {
                Button(Self.openSettingsTitle) { openSystemSettings() }
            }
        }
        .font(IterFont.callout)
    }

    private static var openSettingsTitle: String {
        #if os(macOS)
        String(localized: "Open System Settings", comment: "Onboarding Ask: opens System Settings (Mac)")
        #else
        String(localized: "Open Settings", comment: "Onboarding Ask: opens the Settings app (iPhone and iPad)")
        #endif
    }

    private func openSystemSettings() {
        #if os(macOS)
        openURL(URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension")!)
        #else
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
        #endif
    }

    /// How the Ask requirement reads for each availability; `nil` is a build without a scout.
    struct AskState: Equatable {
        var available: Bool
        var offersSettings: Bool
        var text: String
    }

    static func askState(_ availability: ScoutAvailability?) -> AskState {
        switch availability {
        case .available:
            #if os(macOS)
            AskState(available: true, offersSettings: false, text: String(localized: "Available on this Mac", comment: "Onboarding Ask: works (Mac)"))
            #else
            AskState(available: true, offersSettings: false, text: String(localized: "Available on this device", comment: "Onboarding Ask: works (iPhone and iPad)"))
            #endif
        case .appleIntelligenceNotEnabled:
            AskState(available: false, offersSettings: true, text: String(localized: "Apple Intelligence is turned off", comment: "Onboarding Ask: user has it off"))
        case .deviceNotEligible:
            #if os(macOS)
            AskState(available: false, offersSettings: false, text: String(localized: "Not supported on this Mac", comment: "Onboarding Ask: hardware too old (Mac)"))
            #else
            AskState(available: false, offersSettings: false, text: String(localized: "Not supported on this device", comment: "Onboarding Ask: hardware too old (iPhone and iPad)"))
            #endif
        case .modelNotReady:
            AskState(available: false, offersSettings: false, text: String(localized: "Apple Intelligence is still getting ready", comment: "Onboarding Ask: model downloading"))
        case .unavailable:
            AskState(available: false, offersSettings: false, text: String(localized: "Not available right now", comment: "Onboarding Ask: unavailable for another reason"))
        case nil:
            AskState(available: false, offersSettings: false, text: String(localized: "Not available in this build", comment: "Onboarding Ask: no scout in this build"))
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: IterSpace.lg) {
            title(String(localized: "You're set", comment: "Onboarding done: title"))
                .frame(maxWidth: .infinity, alignment: .center)
            VStack(spacing: 0) {
                summaryRow(String(localized: "Location", comment: "Onboarding summary: row label"), locationSummary)
                Divider()
                summaryRow(String(localized: "Weather", comment: "Onboarding summary: row label"), weatherSummary)
                Divider()
                summaryRow(String(localized: "Ask", comment: "Onboarding summary: row label for the Ask feature"), Self.askState(model.scout?.availability()).text)
            }
            .padding(.horizontal, IterSpace.md)
            .background(IterColor.backgroundModule, in: RoundedRectangle(cornerRadius: IterRadius.card))
            Text("New here? Start in Explore: pick a place to see its light, then add it to a trip.",
                 comment: "Onboarding done: where to begin")
            Link(String(localized: "Take the Guided Tour", comment: "Onboarding done: link to the README tour"),
                 destination: URL(string: "https://github.com/dwjames88/iter#a-short-tour")!)
            #if os(macOS)
            Text("Open this guide again from Help ▸ Welcome to Iter.", comment: "Onboarding done: how to reopen the guide (Mac)")
                .font(IterFont.footnote)
                .foregroundStyle(IterColor.textSecondary)
            #endif
        }
        .font(IterFont.body)
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(IterColor.textSecondary)
            Spacer(minLength: IterSpace.md)
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, IterSpace.sm)
        .accessibilityElement(children: .combine)
    }

    private var locationSummary: String {
        model.location.authorization == .authorized
            ? String(localized: "On", comment: "Onboarding summary: location allowed")
            : String(localized: "Off", comment: "Onboarding summary: location not allowed")
    }

    private var weatherSummary: String {
        let hasKey = model.weather.hasKey(for: .openWeather) && model.weather.settings.primary == .openWeather
        guard hasKey else {
            return String(localized: "Not set up yet: use the banner or Settings ▸ Weather", comment: "Onboarding summary: no weather key")
        }
        switch model.weather.status(for: .openWeather) {
        case .working: return String(localized: "Working", comment: "Onboarding: weather source answers")
        case .keyRejected, .failed:
            return String(localized: "Key saved, not working yet", comment: "Onboarding summary: a key exists but OpenWeather has not accepted it")
        default: return String(localized: "Key saved", comment: "Onboarding summary: a key exists")
        }
    }

    // MARK: Bar

    private var buttonBar: some View {
        HStack(spacing: IterSpace.md) {
            if !onboarding.isFirst && !onboarding.isLast {
                Button(String(localized: "Back", comment: "Onboarding: previous step")) { onboarding.back() }
            }
            secondary
            Spacer(minLength: 0)
            primary
        }
        .background {
            // Esc skips the guide from any step.
            Button(String(localized: "Skip", comment: "Onboarding: close the guide")) { onboarding.skip() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var secondary: some View {
        switch onboarding.step {
        case .welcome:
            Button(String(localized: "Skip", comment: "Onboarding: close the guide")) { onboarding.skip() }
        case .location:
            if model.location.authorization == .notDetermined {
                Button(String(localized: "Not Now", comment: "Onboarding location: decline for now")) { onboarding.next() }
            }
        case .weather:
            Button(String(localized: "Do This Later", comment: "Onboarding weather: skip the setup")) { onboarding.next() }
        case .intelligence, .done:
            EmptyView()
        }
    }

    @ViewBuilder private var primary: some View {
        switch onboarding.step {
        case .welcome, .intelligence:
            primaryButton(String(localized: "Continue", comment: "Onboarding: next step")) { onboarding.next() }
        case .location:
            if model.location.authorization == .notDetermined {
                primaryButton(String(localized: "Allow Location…", comment: "Onboarding location: asks the system for permission")) { model.location.start() }
            } else {
                primaryButton(String(localized: "Continue", comment: "Onboarding: next step")) { onboarding.next() }
            }
        case .weather:
            let saved = keyCheck.hasSavedKey(in: model.weather)
            let title = keyCheck.isRejected
                ? String(localized: "Save Key Anyway", comment: "Onboarding weather: save a key OpenWeather has not accepted yet")
                : String(localized: "Continue", comment: "Onboarding: next step")
            primaryButton(title) { continueFromWeather() }
                .disabled(keyCheck.state == .checking || !(keyCheck.canSave || saved))
        case .done:
            primaryButton(String(localized: "Start Using Iter", comment: "Onboarding done: closes the guide")) { onboarding.finish() }
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
    }

    private func continueFromWeather() {
        if keyCheck.canSave {
            do { try keyCheck.save(into: model.weather) } catch { saveFailed = true; return }
        }
        onboarding.next()
    }

    // MARK: Pieces

    private func title(_ text: String) -> some View {
        Text(text)
            .font(IterFont.titleSection)
            .accessibilityAddTraits(.isHeader)
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: IterSize.lightRingMedium))
            .foregroundStyle(IterColor.accentText)
            .accessibilityHidden(true)
    }

    private func numbered(_ n: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: IterSpace.sm) {
            Text(verbatim: "\(n).")
                .monospacedDigit()
                .foregroundStyle(IterColor.textSecondary)
                .frame(minWidth: IterSize.iconMedium, alignment: .trailing)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Five dots, the current one filled. Reads as "Step 2 of 5".
struct OnboardingStepDots: View {
    let index: Int
    let count: Int

    var body: some View {
        HStack(spacing: IterSpace.sm) {
            ForEach(1...count, id: \.self) { n in
                Circle()
                    .fill(n == index ? IterColor.accent : IterColor.separator)
                    .frame(width: IterSpace.sm, height: IterSpace.sm)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Step \(index) of \(count)", comment: "Onboarding: progress; the placeholders are the current step and the number of steps"))
    }
}

/// A status line: symbol (or a spinner), then text. One VoiceOver element.
struct OnboardingStatusRow: View {
    /// nil shows a spinner.
    let symbol: String?
    let tint: AnyShapeStyle
    let text: String

    init<S: ShapeStyle>(symbol: String?, tint: S, text: String) {
        self.symbol = symbol
        self.tint = AnyShapeStyle(tint)
        self.text = text
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: IterSpace.sm) {
            if let symbol {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            } else {
                ProgressView().controlSize(.small)
                    .accessibilityHidden(true)
            }
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(text))
    }
}
