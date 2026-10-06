import Foundation
import Observation
import IterCore
import IterLight
import IterData
import IterServices

// MARK: - Explainer seam

/// The plain-language explainer, as the spot page needs it. `LightExplainer` conforms; tests use a fake.
public protocol LightExplaining: Sendable {
    func isAvailable() -> Bool
    func explain(spotName: String, window: LightWindow, intentName: String) async throws -> String
}

extension LightExplainer: LightExplaining {}

/// The "Explain" button's life: idle, writing, written, or failed (with a reason the page phrases).
public enum ExplanationState: Equatable, Sendable {
    case idle
    case loading
    case done(String)
    case failed(ExplanationFailure)
}

public enum ExplanationFailure: Equatable, Sendable {
    case unavailable
    case noForecast
    case ungrounded
    case failed
}

// MARK: - Value types

/// The best window for an intent over the coming days.
public struct BestWindow: Equatable, Sendable {
    public var day: LocalDay
    public var window: LightWindow
}

/// How much of the day the timeline, arc markers and hourly strip show.
public enum TimelineFocus: String, CaseIterable, Hashable, Sendable, Identifiable {
    case fullDay
    case aroundSunrise
    case aroundSunset

    public var id: String { rawValue }
}

/// Sun and moon positions across one local day, for the arc and the sky band.
public struct SkyPaths: Sendable {
    public var sun: [(date: Date, position: SkyPosition)]
    public var moon: [(date: Date, position: SkyPosition)]
}

/// What is true at one instant of the day (the scrubber's readout).
public struct InstantReadout: Equatable, Sendable {
    public var date: Date
    /// Total cloud 0–1, nil without a forecast.
    public var cloud: Double?
    public var rain: Double?
    public var temperatureC: Double?
    public var symbolName: String?
    public var sun: SkyPosition
    public var moon: SkyPosition
}

/// Upcoming sun times, for when there is no score to show.
public struct SunTimes: Equatable, Sendable {
    public var kind: SunEvents.DayKind
    public var sunrise: Date?
    public var sunset: Date?
}

// MARK: - Model

/// State of one spot page: the chosen day, intent and window, the scrub time, the outlook and the explanation.
/// Derived light is recomputed (and cached) whenever the shared forecast state changes.
@MainActor
@Observable
public final class SpotModel {
    public let app: AppModel
    public private(set) var spot: Spot
    public private(set) var day: LocalDay
    public private(set) var intent: LightIntent
    public private(set) var selectedWindow: LightWindowKind?
    /// The time under the pointer on the timeline; nil when nothing is being scrubbed.
    public var scrub: Date?
    public private(set) var focus: TimelineFocus = .fullDay
    public private(set) var expanded: Set<LightWindowKind> = []
    public private(set) var explanation: ExplanationState = .idle

    /// Days in the outlook strip.
    public static let outlookDays = 10

    @ObservationIgnored private let explainer: any LightExplaining
    @ObservationIgnored private var explainTask: Task<Void, Never>?
    @ObservationIgnored private var explainGeneration = 0
    @ObservationIgnored private var dayChosenByUser: Bool
    @ObservationIgnored private var intentChosenByUser = false

    public init(app: AppModel, spot: Spot, initialDay: LocalDay? = nil, explainer: any LightExplaining = LightExplainer()) {
        self.app = app
        self.spot = spot
        self.explainer = explainer
        self.intent = app.intent(for: spot)
        self.day = initialDay ?? app.today(in: spot.timeZone)
        self.dayChosenByUser = initialDay != nil
        applyDefaults()
    }

    // MARK: Forecast

    public var forecastState: ForecastState { app.forecasts.state(for: spot.coordinate) }
    public var forecast: Forecast? { forecastState.forecast }
    public var isLoadingForecast: Bool { forecastState == .loading || isRetrying }
    public var isSample: Bool { forecast?.source == .sample }

    /// Why there is no forecast, or nil when there is one (or it is still loading).
    public var unavailableReason: ForecastUnavailableReason? {
        if case .unavailable(let reason) = forecastState { return reason }
        return nil
    }

    /// Requests the forecast, waits for it, and moves to the best day if the user has not chosen one.
    public func start() async {
        app.forecasts.request(spot.coordinate)
        _ = await app.forecasts.load(spot.coordinate)
        applyDefaults()
    }

    /// True while a retry is in flight (the failed state stays until it finishes).
    public private(set) var isRetrying = false

    public func retry() {
        guard !isRetrying else { return }
        isRetrying = true
        app.forecasts.request(spot.coordinate, force: true)
        Task { [weak self] in
            guard let self else { return }
            _ = await app.forecasts.load(spot.coordinate)
            isRetrying = false
            applyDefaults()
        }
    }

    /// The spot was edited: keep the page, refresh what depends on the spot.
    public func update(spot new: Spot) {
        guard new != spot else { return }
        let zoneChanged = new.timeZoneIdentifier != spot.timeZoneIdentifier
        spot = new
        if zoneChanged { day = app.today(in: new.timeZone) }
        resetExplanation()
        applyDefaults()
    }

    // MARK: Derived light (cached per forecast revision)

    private struct CacheKey: Hashable {
        var revision: Int
        var today: LocalDay
        var spot: Spot
        var sample: Bool
    }

    @ObservationIgnored private var cacheKey: CacheKey?
    @ObservationIgnored private var dayCache: [LocalDay: DayLight] = [:]
    @ObservationIgnored private var bestCache: [LightIntent: BestWindow?] = [:]
    @ObservationIgnored private var pathCache: [LocalDay: SkyPaths] = [:]

    private func validateCache() {
        let key = CacheKey(revision: app.forecasts.revision, today: today, spot: spot, sample: app.sampleDataEnabled)
        if key != cacheKey {
            cacheKey = key
            dayCache = [:]
            bestCache = [:]
            pathCache = [:]
        }
    }

    public var today: LocalDay { app.today(in: spot.timeZone) }
    public var timeZone: TimeZone { spot.timeZone }

    public func dayLight(on day: LocalDay) -> DayLight {
        validateCache()
        if let cached = dayCache[day] { return cached }
        let state = forecastState
        let value = app.engine.dayLight(for: spot, on: day, forecast: state.forecast, unavailable: state.unavailableReason, now: app.now())
        dayCache[day] = value
        return value
    }

    /// The selected day.
    public var dayLight: DayLight { dayLight(on: day) }

    /// Days in the outlook: what the forecast covers (8 with OpenWeather), at most `outlookDays`; never empty days.
    public var outlookDayCount: Int {
        app.engine.outlookDayCount(for: spot, from: today, forecast: forecast, max: Self.outlookDays)
    }

    /// The coming days at the spot, as many as the forecast covers.
    public var outlook: [DayLight] {
        (0..<outlookDayCount).map { dayLight(on: today.adding(days: $0)) }
    }

    /// Today's windows still ahead and all of tomorrow's, for the card and page.
    public var upcomingWindows: [(day: LocalDay, window: LightWindow)] {
        app.upcomingWindows(for: spot)
    }

    /// The outlook, plus the selected day when it falls outside it (a trip day further out).
    public var stripDays: [DayLight] {
        let base = outlook
        return base.contains { $0.day == day } ? base : base + [dayLight]
    }

    /// The window that answers the page's intent on a day.
    public func headline(on day: LocalDay) -> LightWindow? { dayLight(on: day).headline(for: intent) }

    /// The best scored window for the intent over the days the forecast covers; nil when nothing is scored.
    public var best: BestWindow? {
        validateCache()
        if let cached = bestCache[intent] { return cached }
        let state = forecastState
        let result = app.engine.bestUpcoming(for: spot, intent: intent, from: today, days: outlookDayCount,
                                             forecast: state.forecast, unavailable: state.unavailableReason, now: app.now())
            .map { BestWindow(day: $0.day, window: $0.window) }
        bestCache[intent] = .some(result)
        return result
    }

    public var selectedLightWindow: LightWindow? {
        guard let selectedWindow else { return nil }
        return dayLight.window(selectedWindow)
    }

    /// Sun and moon positions for the selected day.
    public var paths: SkyPaths {
        validateCache()
        if let cached = pathCache[day] { return cached }
        let value = SkyPaths(
            sun: app.ephemeris.path(of: .sun, on: day, at: spot.coordinate, in: timeZone, everyMinutes: 10),
            moon: app.ephemeris.path(of: .moon, on: day, at: spot.coordinate, in: timeZone, everyMinutes: 10))
        pathCache[day] = value
        return value
    }

    /// Sunrise and sunset next to come (today's if still ahead, else tomorrow's), with whether the sun rises at all.
    public var nextSunTimes: SunTimes {
        let now = app.now()
        let first = dayLight(on: today).sun
        let second = dayLight(on: today.adding(days: 1)).sun
        let rise = [first.sunrise, second.sunrise].compactMap { $0 }.first { $0 > now }
        let set = [first.sunset, second.sunset].compactMap { $0 }.first { $0 > now }
        return SunTimes(kind: first.kind, sunrise: rise, sunset: set)
    }

    // MARK: Hourly weather

    public var dayInterval: (start: Date, end: Date) {
        (day.start(in: timeZone), day.adding(days: 1).start(in: timeZone))
    }

    /// Hourly conditions inside the selected day, in order. Empty without a forecast.
    public var hours: [HourlyConditions] {
        guard let forecast else { return [] }
        let (start, end) = dayInterval
        return forecast.hours.filter { $0.date >= start && $0.date < end }
    }

    /// True when the forecast carries cloud by altitude for this day.
    public var hasCloudLayers: Bool {
        let h = hours
        return !h.isEmpty && h.allSatisfy { $0.cloudLow != nil && $0.cloudMid != nil && $0.cloudHigh != nil }
    }

    // MARK: Timeline domain and scrubbing

    public var availableFoci: [TimelineFocus] {
        let sun = dayLight.sun
        var out: [TimelineFocus] = [.fullDay]
        if sun.sunrise != nil { out.append(.aroundSunrise) }
        if sun.sunset != nil { out.append(.aroundSunset) }
        return out
    }

    public static let zoomMargin: TimeInterval = 2 * 3600

    /// The visible time range of the timeline, arc markers and hourly strip.
    public var domain: ClosedRange<Date> {
        let (start, end) = dayInterval
        let sun = dayLight.sun
        switch focus {
        case .fullDay:
            return start...end
        case .aroundSunrise:
            guard let t = sun.sunrise else { return start...end }
            return max(start, t.addingTimeInterval(-Self.zoomMargin))...min(end, t.addingTimeInterval(Self.zoomMargin))
        case .aroundSunset:
            guard let t = sun.sunset else { return start...end }
            return max(start, t.addingTimeInterval(-Self.zoomMargin))...min(end, t.addingTimeInterval(Self.zoomMargin))
        }
    }

    /// The instant the arc, the readout and the timeline marker show: the scrub, else the selected window's middle,
    /// else the day's headline window, else solar noon.
    public var markerTime: Date {
        if let scrub { return clamp(scrub) }
        if let window = selectedLightWindow { return window.span.midpoint }
        if let window = headline(on: day) { return window.span.midpoint }
        return dayLight.sun.solarNoon
    }

    private func clamp(_ date: Date) -> Date {
        let (start, end) = dayInterval
        return min(max(date, start), end)
    }

    /// Everything known at one instant of the selected day.
    public func readout(at date: Date) -> InstantReadout {
        let h = forecast?.hour(at: date)
        return InstantReadout(date: date, cloud: h?.cloudCover, rain: h?.precipitationChance, temperatureC: h?.temperatureC,
                              symbolName: h?.symbolName,
                              sun: app.ephemeris.sunPosition(at: date, coordinate: spot.coordinate),
                              moon: app.ephemeris.moonPosition(at: date, coordinate: spot.coordinate))
    }

    /// The window whose span contains `date`, if any.
    public func window(at date: Date) -> LightWindow? {
        dayLight.windows.first { $0.span.contains(date) }
    }

    // MARK: Selection

    public func selectDay(_ new: LocalDay) {
        dayChosenByUser = true
        setDay(new)
    }

    public func goToToday() { selectDay(today) }

    private func setDay(_ new: LocalDay) {
        guard new != day else { return }
        day = new
        scrub = nil
        expanded = []
        focus = .fullDay
        selectedWindow = defaultWindow(on: new)
        resetExplanation()
    }

    public func selectIntent(_ new: LightIntent) {
        intentChosenByUser = true
        guard new != intent else { return }
        intent = new
        selectedWindow = defaultWindow(on: day)
        if !dayChosenByUser, let best { setDay(best.day); selectedWindow = best.window.kind }
        resetExplanation()
    }

    /// Selects a window (shared by rows, timeline, arc and hourly strip), or clears with nil.
    public func selectWindow(_ kind: LightWindowKind?) {
        guard kind != selectedWindow else { return }
        selectedWindow = kind
        scrub = nil
        resetExplanation()
    }

    /// Selects the best window's day and window.
    public func showBest() {
        guard let best else { return }
        selectDay(best.day)
        selectWindow(best.window.kind)
    }

    public func toggleExpanded(_ kind: LightWindowKind) {
        if expanded.contains(kind) {
            expanded.remove(kind)
        } else {
            expanded.insert(kind)
            selectWindow(kind)
        }
    }

    public func setExpanded(_ kind: LightWindowKind, _ isExpanded: Bool) {
        if isExpanded != expanded.contains(kind) { toggleExpanded(kind) }
    }

    public func setFocus(_ new: TimelineFocus) {
        guard availableFoci.contains(new) else { return }
        focus = new
    }

    private func defaultWindow(on day: LocalDay) -> LightWindowKind? {
        if let best, best.day == day { return best.window.kind }
        let light = dayLight(on: day)
        return light.headline(for: intent)?.kind ?? light.windows.first?.kind
    }

    /// Before the user chooses, the page opens on the best day for the intent (when it has a forecast).
    private func applyDefaults() {
        if !intentChosenByUser { intent = app.intent(for: spot) }
        if !dayChosenByUser, let best, best.day != day {
            setDay(best.day)
            selectedWindow = best.window.kind
        } else if let kind = selectedWindow, dayLight.window(kind) != nil {
            return
        } else {
            selectedWindow = defaultWindow(on: day)
        }
    }

    // MARK: Explanation

    public var explainerAvailable: Bool { explainer.isAvailable() }

    /// Can the selected window be explained at all (scored, and Apple Intelligence is available)?
    public var canExplain: Bool {
        explainerAvailable && selectedLightWindow?.assessment.lightScore != nil
    }

    /// Writes a plain-language explanation of the selected window. `intentName` is the displayed name of the intent.
    public func explain(intentName: String) {
        guard let window = selectedLightWindow else { return }
        guard window.assessment.lightScore != nil else { explanation = .failed(.noForecast); return }
        explainTask?.cancel()
        explainGeneration += 1
        let generation = explainGeneration
        explanation = .loading
        let name = spot.name
        let explainer = self.explainer
        explainTask = Task { [weak self] in
            let result: ExplanationState
            do {
                result = .done(try await explainer.explain(spotName: name, window: window, intentName: intentName))
            } catch is CancellationError {
                return
            } catch let error as LightExplainerError {
                switch error {
                case .unavailable: result = .failed(.unavailable)
                case .noForecast: result = .failed(.noForecast)
                case .ungroundedNumbers: result = .failed(.ungrounded)
                case .failed: result = .failed(.failed)
                }
            } catch {
                result = .failed(.failed)
            }
            guard !Task.isCancelled, let self, self.explainGeneration == generation else { return }
            self.explanation = result
        }
    }

    public func cancelExplanation() {
        resetExplanation()
    }

    private func resetExplanation() {
        explainTask?.cancel()
        explainTask = nil
        explainGeneration += 1
        explanation = .idle
    }
}
