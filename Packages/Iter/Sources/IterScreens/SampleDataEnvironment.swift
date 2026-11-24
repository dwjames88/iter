import SwiftUI

private struct IsSampleDataKey: EnvironmentKey { static let defaultValue = false }

public extension EnvironmentValues {
    /// True when the app runs on the built-in sample services (`DataMode.sample`). Views that would call something "live" or
    /// "with traffic" say "sample" instead: the shells set it once at the root.
    var isSampleData: Bool {
        get { self[IsSampleDataKey.self] }
        set { self[IsSampleDataKey.self] = newValue }
    }
}

/// The words for what the sample services stand in for, so one place decides.
public enum SampleDataText {
    /// "Live" in the real app; "Sample" in sample mode.
    public static func liveWord(sample: Bool, locale: Locale = .current) -> String {
        sample ? String(localized: "Sample", locale: locale, comment: "Sample data mode: replaces the word Live")
               : String(localized: "Live", locale: locale, comment: "A reading that is current")
    }
}
