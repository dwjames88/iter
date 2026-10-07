import Foundation
import IterCore
import IterFeatures

/// Phrasing used only on the spot page. Light, time and band words still come from `LightText` and `TimeText`.
extension LightText {
    // MARK: Sections

    static let nothingLeftToday = String(localized: "No light windows are left today.", comment: "Outlook: every window of today is over")
    static let timelineTitle = String(localized: "Light through the day", comment: "Spot page section title")
    static let skyTitle = String(localized: "Sun and moon", comment: "Spot page section title")
    static let hourlyTitle = String(localized: "Hour by hour", comment: "Spot page section title")
    static let factsTitle = String(localized: "Good to know", comment: "Spot page section title")
    static let lookAroundTitle = String(localized: "Look Around", comment: "Spot page section title")

    // MARK: Lead

    static func outlookTitle(days: Int, intent: LightIntent) -> String {
        String(localized: "\(days)-day outlook for \(name(intent))", comment: "Outlook strip title with the number of days and the chosen intent, e.g. 8-day outlook for Sunset")
    }

    static let outlookKey = String(localized: "Fainter days are less certain.",
                                   comment: "Outlook strip key explaining fading")

    static let bestMarker = String(localized: "Best", comment: "Marker on the best day of the outlook")

    static func bestIn(days: Int, intent: LightIntent) -> String {
        String(localized: "Best \(name(intent).lowercased()) in the next \(days) days", comment: "Caption above the best window, e.g. Best sunset in the next 10 days")
    }

    static let checkingForecast = String(localized: "Checking the forecast…", comment: "Shown while the forecast loads")
    static let showThisDay = String(localized: "Show this day", comment: "Button that selects the best day")

    /// "Today", "Tomorrow" or "Wed 7 Oct".
    static func relativeDay(_ day: LocalDay, today: LocalDay) -> String {
        switch today.days(until: day) {
        case 0: String(localized: "Today", comment: "Relative day")
        case 1: String(localized: "Tomorrow", comment: "Relative day")
        case -1: String(localized: "Yesterday", comment: "Relative day")
        default: TimeText.day(day)
        }
    }

    // MARK: Sun times

    static let polarNight = String(localized: "The sun doesn't rise here on this day. The light is the blue hour either side of noon.",
                                    comment: "Polar night: no sunrise")
    static let polarDay = String(localized: "The sun doesn't set here on this day. No blue hour, but a long golden window while the sun is low.",
                                 comment: "Midnight sun: no sunset")

    static func nextSunrise(_ time: String) -> String {
        String(localized: "Next sunrise \(time)", comment: "Sun time when there is no score")
    }

    static func nextSunset(_ time: String) -> String {
        String(localized: "Next sunset \(time)", comment: "Sun time when there is no score")
    }

    /// "6:48 AM", or "Wed 6:48 AM" when not today.
    static func sunTime(_ date: Date, in zone: TimeZone, today: LocalDay) -> String {
        let time = TimeText.time(date, in: zone)
        let day = LocalDay(date, in: zone)
        if day == today { return time }
        return "\(TimeText.weekday(day)) \(time)"
    }

    // MARK: Windows and reasons

    static let noWindowsPolar = String(localized: "No golden hour, blue hour or night window today.",
                                       comment: "Windows list when the sun produces no windows")

    static let reasonsTitle = String(localized: "Why this score", comment: "Heading above the factors behind a score")
    static let helps = String(localized: "Helps", comment: "Factor effect")
    static let hurts = String(localized: "Hurts", comment: "Factor effect")
    static let neutral = String(localized: "Little effect", comment: "Factor effect")

    static func points(_ p: Int) -> String {
        if p == 0 { return "0" }
        return p > 0 ? "+\(p)" : "−\(abs(p))"
    }

    static func leadNote(hours: Double) -> String {
        let h = Int(hours.rounded())
        if h < 1 { return String(localized: "Forecast is for right now.", comment: "Forecast lead note") }
        if h < 48 { return String(localized: "Forecast is about \(h) hours ahead of this window.", comment: "Forecast lead note") }
        let days = Int((hours / 24).rounded())
        return String(localized: "Forecast is about \(days) days ahead of this window.", comment: "Forecast lead note")
    }

    static func confidenceExplained(_ c: Confidence) -> String {
        switch c {
        case .high: String(localized: "The forecast is close, so the score is firm.", comment: "Confidence in words")
        case .medium: String(localized: "A few days out: expect the score to move a little.", comment: "Confidence in words")
        case .low: String(localized: "Far out or missing inputs: treat the score as a guide.", comment: "Confidence in words")
        }
    }

    // MARK: Explain

    static let explain = String(localized: "Explain", comment: "Button: write a plain-language explanation of a score")
    static let explainAgain = String(localized: "Explain again", comment: "Button")
    static let explaining = String(localized: "Writing an explanation…", comment: "Progress while Apple Intelligence writes")
    static let cancel = String(localized: "Cancel", comment: "Button")
    static let writtenByAppleIntelligence = String(localized: "Written by Apple Intelligence from the factors listed above.",
                                                   comment: "Attribution under a generated explanation")

    static func explanationFailure(_ failure: ExplanationFailure) -> String {
        switch failure {
        case .unavailable: String(localized: "Apple Intelligence isn't available right now.", comment: "Explanation failure")
        case .noForecast: String(localized: "There is no score to explain for this window.", comment: "Explanation failure")
        case .ungrounded: String(localized: "The explanation didn't match the numbers, so it was discarded. Try again.", comment: "Explanation failure")
        case .failed: String(localized: "Couldn't write an explanation. Try again.", comment: "Explanation failure")
        }
    }

    // MARK: Timeline

    static let zoomLabel = String(localized: "Zoom", comment: "Timeline zoom picker label")
    static let zoomFullDay = String(localized: "Full day", comment: "Timeline zoom option")
    static let zoomSunrise = String(localized: "Sunrise ±2 h", comment: "Timeline zoom option")
    static let zoomSunset = String(localized: "Sunset ±2 h", comment: "Timeline zoom option")

    static let cloudLowLegend = String(localized: "Low cloud", comment: "Chart legend")
    static let cloudMidLegend = String(localized: "Mid cloud", comment: "Chart legend")
    static let cloudHighLegend = String(localized: "High cloud", comment: "Chart legend")
    static let cloudTotalLegend = String(localized: "Cloud cover", comment: "Chart legend")
    static let windyTitle = String(localized: "Windy", comment: "Spot page section title")
    static let windyExplanation = String(localized: "Windy's map shows cloud by height, rain and wind around this spot. It opens on windy.com: Windy doesn't allow its map inside other weather apps.",
                                         comment: "Spot page Windy section")
    static let openInWindy = String(localized: "Open in Windy", comment: "Button that opens windy.com at the spot")
    static let rainLegend = String(localized: "Chance of rain", comment: "Chart legend")
    static let rainAmountLegend = String(localized: "Rain amount (full height is 2 mm/h)", comment: "Chart legend when the provider gives amounts, not chances")

    static let noWeatherLayers = String(localized: "Cloud and rain are not drawn: there is no forecast. Sun and window times above are exact.",
                                        comment: "Timeline note when there is no forecast")

    /// "6 PM · 79% cloud · 10% rain"
    static func readout(hour: String, cloud: Double?, rain: Double?, rainMm: Double? = nil) -> String {
        var parts = [hour]
        if let cloud { parts.append(String(localized: "\(percent(cloud)) cloud", comment: "Scrub readout")) }
        if let rain { parts.append(String(localized: "\(percent(rain)) rain", comment: "Scrub readout")) }
        else if let rainMm { parts.append(String(localized: "\(millimetresPerHour(rainMm)) rain", comment: "Scrub readout when only an amount is known")) }
        return parts.joined(separator: " · ")
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    static func hourLabel(_ date: Date, in zone: TimeZone) -> String {
        var style = Date.FormatStyle().hour(.defaultDigits(amPM: .abbreviated))
        style.timeZone = zone
        return date.formatted(style)
    }

    static func windowChartLabel(_ window: LightWindow) -> String {
        if let score = window.score { return "\(shortName(window.kind)) \(score)" }
        return shortName(window.kind)
    }

    // MARK: Sun and moon rose

    static func degrees(_ bearing: Double) -> String {
        let value = Int(bearing.rounded())
        return String(localized: "\(value)° \(compassPoint(for: bearing))", comment: "A compass bearing, e.g. 100° E")
    }

    static let orientationLabel = String(localized: "Orientation", comment: "Sun and moon rose: label of the North up or View up control")
    static let northUp = String(localized: "North up", comment: "Sun and moon rose: north is at the top")
    static let viewUp = String(localized: "View up", comment: "Sun and moon rose: the classic view's direction is at the top")
    static let orientationHelp = String(localized: "Turn the rose so north, or the classic view, is at the top", comment: "Help for the rose orientation control")
    static let classicView = String(localized: "Classic view", comment: "Sun and moon rose: label on the wedge showing the direction the classic composition faces")
    static func viewShort(_ bearing: Double) -> String {
        String(localized: "View \(degrees(bearing))", comment: "Sun and moon rose: short label on the classic view wedge when the full label does not fit")
    }
    static let roseKey = String(localized: "Edge: horizon · Centre: overhead", comment: "Sun and moon rose: key under the rose")
    static let sunWord = String(localized: "Sun", comment: "Sun and moon rose readout: the sun")
    static let moonWord = String(localized: "Moon", comment: "Sun and moon rose readout: the moon")
    static let timeOfDay = String(localized: "Time of day", comment: "VoiceOver label of the time scrubber")
    static let nowMark = String(localized: "Now", comment: "Time scrubber: mark for the current time")
    static let belowHorizon = String(localized: "below the horizon", comment: "Sun or moon is below the horizon")

    static func altitudeUp(_ altitude: Double) -> String {
        String(localized: "\(Int(altitude.rounded()))° up", comment: "Height of the sun or moon above the horizon, e.g. 12° up")
    }

    static func eventName(_ kind: SkyRose.EventKind) -> String {
        switch kind {
        case .sunrise: String(localized: "Sunrise", comment: "Sun event")
        case .solarNoon: String(localized: "Solar noon", comment: "Sun event: highest point")
        case .sunset: String(localized: "Sunset", comment: "Sun event")
        case .moonrise: String(localized: "Moonrise", comment: "Moon event")
        case .moonset: String(localized: "Moonset", comment: "Moon event")
        }
    }

    /// Symbol for a rose event mark.
    static func roseSymbol(_ kind: SkyRose.EventKind) -> String {
        switch kind {
        case .sunrise: "sunrise.fill"
        case .solarNoon: "sun.max.fill"
        case .sunset: "sunset.fill"
        case .moonrise: "moonrise.fill"
        case .moonset: "moonset.fill"
        }
    }

    /// The one strong fact: "Sun sets at 263° W, inside your view".
    static func roseFact(_ fact: SkyRose.Fact, in zone: TimeZone) -> String {
        switch fact {
        case .inside(let event):
            return event.kind == .sunrise
                ? String(localized: "Sun rises at \(degrees(event.position.azimuth)), inside your view", comment: "Rose fact: the sunrise is inside the classic view")
                : String(localized: "Sun sets at \(degrees(event.position.azimuth)), inside your view", comment: "Rose fact: the sunset is inside the classic view")
        case .outside(let event, let by):
            let whole = Int(by.rounded())
            return event.kind == .sunrise
                ? String(localized: "Sun rises at \(degrees(event.position.azimuth)), outside your view by \(whole)°", comment: "Rose fact: the sunrise misses the classic view by some degrees")
                : String(localized: "Sun sets at \(degrees(event.position.azimuth)), outside your view by \(whole)°", comment: "Rose fact: the sunset misses the classic view by some degrees")
        case .noView(let event):
            let time = TimeText.time(event.date, in: zone)
            return event.kind == .sunrise
                ? String(localized: "Sun rises at \(degrees(event.position.azimuth)) at \(time)", comment: "Rose fact when the view direction is unknown")
                : String(localized: "Sun sets at \(degrees(event.position.azimuth)) at \(time)", comment: "Rose fact when the view direction is unknown")
        case .noSunrise:
            return String(localized: "The sun doesn't rise on this day", comment: "Rose fact: polar night")
        case .noSunset:
            return String(localized: "The sun doesn't set on this day", comment: "Rose fact: midnight sun")
        }
    }

    /// "241° WSW · 12° up" or "241° WSW · below the horizon": the readout line without its "Sun" or "Moon" word.
    static func skyDetail(_ position: SkyPosition) -> String {
        if position.altitude >= 0 {
            return String(localized: "\(degrees(position.azimuth)) · \(altitudeUp(position.altitude))", comment: "Rose readout: bearing and height of the sun or moon")
        }
        return String(localized: "\(degrees(position.azimuth)) · \(belowHorizon)", comment: "Rose readout: bearing of the sun or moon below the horizon")
    }

    static func moonDetail(_ position: SkyPosition, phase: MoonPhase) -> String {
        String(localized: "\(skyDetail(position)) · \(moonName(phase.name)), \(percent(phase.illumination)) lit", comment: "Rose readout for the moon: bearing, height, phase and how much is lit")
    }

    /// The scrubber's spoken value: "18:41, golden hour. Sun 263° W, 1° up. Moon 120° ESE, 35° up, waxing gibbous, 78% lit."
    static func scrubberValue(time: String, window: LightWindowKind?, sun: SkyPosition, moon: SkyPosition, phase: MoonPhase) -> String {
        func spoken(_ p: SkyPosition) -> String {
            p.altitude >= 0 ? "\(degrees(p.azimuth)), \(altitudeUp(p.altitude))" : "\(degrees(p.azimuth)), \(belowHorizon)"
        }
        let head = window.map { "\(time), \(name($0).lowercased())" } ?? time
        let sunPart = String(localized: "Sun \(spoken(sun))", comment: "VoiceOver: the sun's position")
        let moonPart = String(localized: "Moon \(spoken(moon)), \(moonName(phase.name).lowercased()), \(percent(phase.illumination)) lit", comment: "VoiceOver: the moon's position and phase")
        return [head, sunPart, moonPart].joined(separator: ". ") + "."
    }

    static func roseSummary(day: String) -> String {
        String(localized: "Sun and moon for \(day)", comment: "VoiceOver: sun and moon rose label")
    }

    static func facingNote(_ bearing: Double) -> String {
        String(localized: "Classic view faces \(degrees(bearing))", comment: "Sun and moon rose: direction the classic composition faces")
    }

    static func moonName(_ name: MoonPhase.Name) -> String {
        switch name {
        case .new: String(localized: "New moon", comment: "Moon phase")
        case .waxingCrescent: String(localized: "Waxing crescent", comment: "Moon phase")
        case .firstQuarter: String(localized: "First quarter", comment: "Moon phase")
        case .waxingGibbous: String(localized: "Waxing gibbous", comment: "Moon phase")
        case .full: String(localized: "Full moon", comment: "Moon phase")
        case .waningGibbous: String(localized: "Waning gibbous", comment: "Moon phase")
        case .lastQuarter: String(localized: "Last quarter", comment: "Moon phase")
        case .waningCrescent: String(localized: "Waning crescent", comment: "Moon phase")
        }
    }

    static func moonSymbol(_ name: MoonPhase.Name) -> String {
        switch name {
        case .new: "moonphase.new.moon"
        case .waxingCrescent: "moonphase.waxing.crescent"
        case .firstQuarter: "moonphase.first.quarter"
        case .waxingGibbous: "moonphase.waxing.gibbous"
        case .full: "moonphase.full.moon"
        case .waningGibbous: "moonphase.waning.gibbous"
        case .lastQuarter: "moonphase.last.quarter"
        case .waningCrescent: "moonphase.waning.crescent"
        }
    }

    // MARK: Hourly

    static let rowTemp = String(localized: "Temp", comment: "Hourly row label")
    static let rowCloud = String(localized: "Cloud", comment: "Hourly row label")
    static let rowRain = String(localized: "Rain", comment: "Hourly row label")
    static let rowWind = String(localized: "Wind", comment: "Hourly row label")

    /// Wind in the user's system: mph or km/h, number only (the unit is in `windUnit`).
    static func windNumber(kph: Double) -> String {
        let value = Locale.current.measurementSystem == .us ? kph * 0.621371 : kph
        return Int(value.rounded()).formatted()
    }

    static var windUnit: String {
        Locale.current.measurementSystem == .us
            ? String(localized: "mph", comment: "Wind speed unit")
            : String(localized: "km/h", comment: "Wind speed unit")
    }

    // MARK: Facts

    static func walkIn(_ minutes: Int?) -> String {
        guard let minutes else { return String(localized: "Walk-in unknown", comment: "Spot fact when the walk from parking is not known") }
        return String(localized: "\(minutes) min walk-in", comment: "Spot fact: walk from parking")
    }

    static func elevation(_ meters: Double) -> String {
        if Locale.current.measurementSystem == .us {
            let feet = Measurement(value: meters, unit: UnitLength.meters).converted(to: .feet)
            return String(localized: "\(Int(feet.value.rounded()).formatted()) ft elevation", comment: "Spot fact: elevation in feet")
        }
        return String(localized: "\(Int(meters.rounded()).formatted()) m elevation", comment: "Spot fact: elevation in metres")
    }

    static func facing(_ bearing: Double?) -> String {
        guard let bearing else { return String(localized: "Facing unknown", comment: "Spot fact when the classic view direction is unknown") }
        return String(localized: "Faces \(degrees(bearing))", comment: "Spot fact: direction the classic composition faces")
    }

    static func bestAt(_ lights: [BestLight]) -> String? {
        guard !lights.isEmpty else { return nil }
        return String(localized: "Best at \(lights.map { name($0).lowercased() }.formatted(.list(type: .and, width: .narrow)))",
                      comment: "Spot fact: what the spot is known for")
    }

    static let notesTitle = String(localized: "Notes", comment: "Spot notes heading")

    // MARK: Actions

    static let save = String(localized: "Save", comment: "Button")
    static let saved = String(localized: "Saved", comment: "Button state")
    static let openInMaps = String(localized: "Open in Maps", comment: "Button")
    static let share = String(localized: "Share", comment: "Button")
    static let edit = String(localized: "Edit", comment: "Button")
    static let delete = String(localized: "Delete", comment: "Button")

    static let deleteSpot = String(localized: "Delete Spot", comment: "Button")

    static func deleteTitle(_ name: String) -> String {
        String(localized: "Delete “\(name)”?", comment: "Delete spot confirmation title")
    }

    static func deleteMessage(stops: Int) -> String {
        String(localized: "It is also removed from \(stops) trip stops. You can undo this with Edit > Undo.", comment: "Delete spot confirmation message")
    }

    // MARK: Outlook days

    static let windowPassed = String(localized: "Passed", comment: "Outlook row for today when the day's headline window is over")
}
