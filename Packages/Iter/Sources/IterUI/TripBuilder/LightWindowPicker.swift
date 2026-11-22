import IterModel
import SwiftUI

/// A stop's light window as a system pop-up: the closed control names the window ("Sunset"); the open menu lists every
/// window the sun makes that day with its symbol, time and score, which is what you compare to choose.
/// Figma part: light window picker.
public struct LightWindowPicker: View {
    /// One window the sun makes that day.
    public struct Option: Identifiable, Equatable, Sendable {
        public var kind: LightWindowKind
        public var start: Date
        public var end: Date
        public var score: Int?

        public var id: LightWindowKind { kind }

        public init(kind: LightWindowKind, start: Date, end: Date, score: Int? = nil) {
            self.kind = kind
            self.start = start
            self.end = end
            self.score = score
        }

        /// The menu item, e.g. "Sunset · 6:12–6:48 PM · 64" (no score: "Sunset · 6:12–6:48 PM").
        public func title(in zone: TimeZone, locale: Locale = .current) -> String {
            var parts = [LightText.name(kind), TimeText.timeRange(TimeSpan(start: start, end: end), in: zone, locale: locale)]
            if let score { parts.append(score.formatted(.number.locale(locale))) }
            return parts.joined(separator: " · ")
        }
    }

    public let options: [Option]
    @Binding public var selection: LightWindowKind
    public let zone: TimeZone
    public let locale: Locale

    public init(options: [Option], selection: Binding<LightWindowKind>, zone: TimeZone, locale: Locale = .current) {
        self.options = options
        self._selection = selection
        self.zone = zone
        self.locale = locale
    }

    public var body: some View {
        Menu {
            Picker(selection: $selection) {
                ForEach(options) { option in
                    Label(option.title(in: zone, locale: locale), systemImage: LightText.symbol(option.kind)).tag(option.kind)
                }
            } label: {
                Text("Session", bundle: .module, comment: "Accessibility label of the session menu")
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Text(LightText.name(selection)).font(BuilderType.body)
        }
        .menuStyle(.button)
        .fixedSize()
        .accessibilityLabel(Text("Session", bundle: .module, comment: "Accessibility label of the session menu"))
        .accessibilityValue(Text(LightText.name(selection)))
        .help(Text("Which light to shoot here: each window with its time and score for this day", bundle: .module, comment: "Tooltip"))
    }
}
