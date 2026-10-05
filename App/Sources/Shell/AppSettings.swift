import Foundation
import IterCore

/// UserDefaults keys for Settings, read with @AppStorage anywhere.
enum AppSettings {
    /// "system", "celsius" or "fahrenheit".
    static let temperatureUnit = "IterTemperatureUnit"
    /// Minutes before a window starts that a new stop wants you set up (default 20).
    static let defaultSetUpBuffer = "IterDefaultSetUpBuffer"

    static func temperature(_ celsius: Double, unitSetting: String) -> String {
        let m = Measurement(value: celsius, unit: UnitTemperature.celsius)
        switch unitSetting {
        case "celsius": return m.formatted(.measurement(width: .narrow, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
        case "fahrenheit": return m.converted(to: .fahrenheit).formatted(.measurement(width: .narrow, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
        default: return m.formatted(.measurement(width: .narrow, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0))))
        }
    }
}
