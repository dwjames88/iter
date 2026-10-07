import SwiftUI
import IterCore
import IterServices
import IterFeatures

/// The one path a key takes into the Keychain from Settings (the Save button and the debug launch switch both use it).
@MainActor
enum IOSKeySaving {
    static func save(_ key: String, for source: ForecastSource, in setup: WeatherSetup) throws {
        try setup.setKey(key, for: source)
    }

    #if DEBUG
    /// `-IterSaveOpenWeatherKeyFromArgument YES`: saves the `-ITER_OPENWEATHER_KEY` value into the Keychain through the same
    /// path as the Save button, so a relaunch without the argument shows the saved state. Never prints the key.
    static func applyLaunchSwitch(_ setup: WeatherSetup) {
        guard UserDefaults.standard.bool(forKey: "IterSaveOpenWeatherKeyFromArgument"),
              let key = UserDefaults.standard.string(forKey: "ITER_OPENWEATHER_KEY") else { return }
        do {
            try save(key, for: .openWeather, in: setup)
            AppLaunch.log.info("Saved the OpenWeather key from the launch argument to the Keychain")
        } catch {
            AppLaunch.log.error("Saving the launch-argument key failed")
        }
    }
    #endif
}
