import Foundation
import Observation
import IterModel
import IterSources
import IterSky
import IterAstro
import IterConditions

/// Conditions for any `Place` (BLUEPRINT §8): the selected day's windows with scores, reasons and confidence, when to go over
/// the coming days, the ten-day outlook, the light timeline, the sun and moon compass with a scrubbable time, hourly weather,
/// the nearest station's report, alerts, smoke, aurora, terrain, the second-source comparison, named gaps and sources.
///
/// Built on the shared `ConditionsStore` (through `ConditionsFeed`), so the same loads serve every screen. A score appears
/// fast and improves: the model keeps the score on screen while a better one loads and never falls back to an empty state in
/// between (`scoreRevision` changes when the shown score is replaced, so the screen can cross-fade). Each published property
/// is assigned only when it changed, so a view that reads one thing is not invalidated by another.
@MainActor @Observable
public final class ConditionsModel {
    // MARK: Identity

    public let place: Place
    /// The day shown. Setting it loads that day (a cached report shows at once) and moves the compass to it.
    public var selectedDay: LocalDay {
        didSet { if selectedDay != oldValue { dayChanged() } }
    }
    /// The time the compass shows. Clamped to the selected day; scrub it and `compass` follows.
    public var scrubTime: Date {
        didSet {
            let clamped = clampToDay(scrubTime)
            if clamped != scrubTime { scrubTime = clamped; return }
            if scrubTime != oldValue { updateCompass() }
        }
    }

    // MARK: Honest state

    public internal(set) var status: ConditionsStatus = .loading
    /// True while the store is loading something for the selected day (a refresh, or a better tier on its way).
    public internal(set) var isUpdating = false

    // MARK: The score

    /// The header chip's score. Never nil between a quick score and the better one that replaces it.
    public internal(set) var headline: HeadlineScore?
    /// What `headline` was before the last replacement, for the cross-fade.
    public internal(set) var previousHeadline: HeadlineScore?
    /// Increments each time the shown score is replaced by a different one (a better tier arrived, a refresh changed it).
    public internal(set) var scoreRevision = 0
    public internal(set) var windows: [WindowDetail] = []

    // MARK: Looking ahead

    public internal(set) var outlook: [OutlookRow] = []
    public internal(set) var whenToGo: WhenToGo?

    // MARK: The day

    public internal(set) var timeline: LightTimeline
    public internal(set) var compassDay: CompassDay
    public internal(set) var compass: CompassReadout
    public internal(set) var hours: [HourRow] = []

    // MARK: Around the place

    public internal(set) var observation: StationObservation?
    public internal(set) var alerts: [AlertRow] = []
    public internal(set) var smoke = SmokeInfo(density: nil, nearSurfaceMaxUgm3: nil, nearSurfaceSource: nil, opticalDepthMax: nil, notes: [])
    public internal(set) var aurora: AuroraInfo?
    public internal(set) var horizon = HorizonInfo(load: .loading, profile: nil, tallestDegrees: nil, shortened: [])
    public internal(set) var comparison: ComparisonInfo?
    public internal(set) var gaps: [GapRow] = []

    // MARK: Provenance

    public internal(set) var sourceLines: [ProvenanceLine] = []
    public internal(set) var attributions: [AttributionText] = []
    /// "Forecast from 06:29, offline" when the forecast is not fresh because there is no network.
    public internal(set) var offlineNote: String?
    public internal(set) var generatedAt: Date?

    // MARK: Now

    public internal(set) var live: LiveConditions?
    public internal(set) var liveLoad: LiveLoad = .idle

    // MARK: Internals

    @ObservationIgnored let feed: any ConditionsFeed
    @ObservationIgnored let ephemeris: any Ephemeris
    @ObservationIgnored let now: @Sendable () -> Date
    @ObservationIgnored let outlookDayCount: Int
    @ObservationIgnored var trackTask: Task<Void, Never>?
    @ObservationIgnored var trackGeneration = 0
    @ObservationIgnored var isTracking = false
    @ObservationIgnored var liveGeneration = 0
    @ObservationIgnored var outlookRequested = false
    @ObservationIgnored var shownDay: LocalDay?
    @ObservationIgnored var report: SkyReport?

    public init(place: Place, feed: any ConditionsFeed, ephemeris: any Ephemeris = Astronomy(), now: @escaping @Sendable () -> Date,
                outlookDays: Int = 10, selectedDay: LocalDay? = nil) {
        self.place = place
        self.feed = feed
        self.ephemeris = ephemeris
        self.now = now
        self.outlookDayCount = max(1, outlookDays)
        let today = LocalDay(now(), in: place.timeZone)
        let day = selectedDay ?? today
        self.selectedDay = day
        let start = Self.initialScrub(place: place, day: day, now: now(), ephemeris: ephemeris)
        scrubTime = start
        timeline = ConditionsDerivation.timeline(report: nil, place: place, day: day, ephemeris: ephemeris)
        compassDay = ConditionsDerivation.compassDay(place: place, day: day, ephemeris: ephemeris)
        compass = ConditionsDerivation.readout(at: start, place: place, ephemeris: ephemeris)
    }

    // MARK: Lifecycle

    /// The screen appeared: load the selected day at on-screen priority, then watch the store.
    public func start() {
        feed.request(place, day: selectedDay, priority: .onScreen)
        track()
    }

    /// The screen went away: stop watching. Loads already running keep filling the cache.
    public func stop() {
        trackGeneration += 1
        isTracking = false
        trackTask?.cancel()
        trackTask = nil
        liveGeneration += 1
    }

    /// Reloads the selected day whatever is cached; the score on screen stays until the new one arrives.
    public func refresh() {
        feed.refresh(place, day: selectedDay, priority: .onScreen)
    }

    // MARK: Days

    /// The days of the outlook: today at the place, then the next nine.
    public var outlookDays: [LocalDay] {
        let today = LocalDay(now(), in: place.timeZone)
        return (0..<outlookDayCount).map { today.adding(days: $0) }
    }

    public func select(day: LocalDay) { selectedDay = day }

    private func dayChanged() {
        feed.request(place, day: selectedDay, priority: .onScreen)
        scrubTime = Self.initialScrub(place: place, day: selectedDay, now: now(), ephemeris: ephemeris)
        compassDay = ConditionsDerivation.compassDay(place: place, day: selectedDay, ephemeris: ephemeris)
        updateCompass()
        // A day we already hold shows at once; a day we do not shows as loading (nothing, never the other day's score).
        apply(readStates())
        if isTracking { track() }
    }

    // MARK: Compass

    /// Moves the scrubbed time to the middle of a window.
    public func scrub(toWindow kind: LightWindowKind) {
        if let w = windows.first(where: { $0.kind == kind }) { scrubTime = w.span.midpoint }
        else if let s = timeline.windows.first(where: { $0.kind == kind }) { scrubTime = s.span.midpoint }
    }

    public func scrubToNow() { scrubTime = now() }

    private func updateCompass() {
        let next = ConditionsDerivation.readout(at: scrubTime, place: place, ephemeris: ephemeris)
        if next != compass { compass = next }
    }

    func clampToDay(_ t: Date) -> Date {
        let zone = place.timeZone
        let start = selectedDay.start(in: zone), end = selectedDay.adding(days: 1).start(in: zone)
        return min(max(t, start), end)
    }

    /// Now, when the selected day is today; else the day's sunset (or solar noon when the sun does not set).
    static func initialScrub(place: Place, day: LocalDay, now: Date, ephemeris: any Ephemeris) -> Date {
        let zone = place.timeZone
        let start = day.start(in: zone), end = day.adding(days: 1).start(in: zone)
        if now >= start && now < end { return now }
        let sun = ephemeris.sunEvents(on: day, at: place.coordinate, in: zone)
        return sun.sunset ?? sun.solarNoon
    }

    // MARK: Now

    /// Current conditions for "Now": the nearest observation, the nowcast and the current forecast hour.
    public func loadLive() async {
        liveGeneration += 1
        let mine = liveGeneration
        liveLoad = .loading
        let result = await feed.live(for: place)
        guard mine == liveGeneration else { return }
        live = result
        liveLoad = .ready
    }

    // MARK: Tracking the store

    private func readStates() -> [LocalDay: ConditionsLoadState] {
        var out: [LocalDay: ConditionsLoadState] = [:]
        for day in Set(outlookDays + [selectedDay]) { out[day] = feed.state(for: place.id, day: day) }
        return out
    }

    /// Reads every tracked slot under observation tracking, applies what it saw at once, and watches for the next change.
    private func track() {
        trackGeneration += 1
        isTracking = true
        trackTask?.cancel()
        observeOnce(trackGeneration)
    }

    private func observeOnce(_ generation: Int) {
        guard isTracking, trackGeneration == generation else { return }
        let (changes, signal) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let states = withObservationTracking({ self.readStates() }, onChange: { signal.yield(()); signal.finish() })
        apply(states)
        trackTask = Task { [weak self] in
            for await _ in changes { break }
            guard let self, !Task.isCancelled else { return }
            self.observeOnce(generation)
        }
    }

    func apply(_ states: [LocalDay: ConditionsLoadState]) {
        let selectedState = states[selectedDay]
        let isLoading = selectedState?.isLoading ?? false
        if isUpdating != isLoading { isUpdating = isLoading }
        if let r = selectedState?.report {
            applyReport(r)
            if !outlookRequested { requestOutlook() }
        } else if shownDay != selectedDay {
            // A different day with nothing yet: loading, with no score and no leftovers from the other day.
            clearContent()
        }
        applyOutlook(states)
    }

    private func requestOutlook() {
        outlookRequested = true
        for day in outlookDays where day != selectedDay { feed.request(place, day: day, priority: .background) }
    }

    private func applyOutlook(_ states: [LocalDay: ConditionsLoadState]) {
        let today = LocalDay(now(), in: place.timeZone)
        let rows = outlookDays.map { ConditionsDerivation.outlookRow(day: $0, today: today, selected: selectedDay, state: states[$0]) }
        if rows != outlook { outlook = rows }
        let best = ConditionsDerivation.whenToGo(rows)
        if best != whenToGo { whenToGo = best }
    }

    private func applyReport(_ r: SkyReport) {
        report = r
        shownDay = r.day
        let at = now()
        set(\.status, ConditionsDerivation.status(r, now: at))
        // The score: keep what is shown until a different one arrives, then bump the revision so the screen can cross-fade.
        let next = ConditionsDerivation.headline(r, intent: place.defaultIntent)
        if let next {
            // Only a change the eye can see counts: a better tier with the same score and window just updates quietly.
            if let old = headline, old.value != next.value || old.kind != next.kind || old.confidence != next.confidence {
                previousHeadline = old
                scoreRevision += 1
            }
            if headline != next { headline = next }
        } else if headline != nil, r.tier == .complete, case .none = r.forecast {
            // The better answer says there is no forecast at all: stop showing a score the data no longer supports.
            previousHeadline = headline
            headline = nil
            scoreRevision += 1
        }
        set(\.windows, ConditionsDerivation.windows(r))
        set(\.timeline, ConditionsDerivation.timeline(report: r, place: place, day: r.day, ephemeris: ephemeris))
        set(\.hours, ConditionsDerivation.hours(r, day: r.day, zone: place.timeZone))
        set(\.observation, ConditionsDerivation.observation(r, now: at))
        set(\.alerts, ConditionsDerivation.alerts(r))
        set(\.smoke, ConditionsDerivation.smoke(r))
        set(\.aurora, ConditionsDerivation.aurora(r))
        set(\.horizon, ConditionsDerivation.horizon(r))
        set(\.comparison, ConditionsDerivation.comparison(r))
        set(\.gaps, ConditionsDerivation.gaps(r))
        set(\.sourceLines, r.provenanceLines)
        set(\.attributions, r.attributions)
        set(\.offlineNote, r.offlineNote)
        set(\.generatedAt, r.generatedAt)
    }

    private func clearContent() {
        report = nil
        shownDay = nil
        set(\.status, .loading)
        if headline != nil { previousHeadline = headline; headline = nil; scoreRevision += 1 }
        set(\.windows, [])
        set(\.timeline, ConditionsDerivation.timeline(report: nil, place: place, day: selectedDay, ephemeris: ephemeris))
        set(\.hours, [])
        set(\.observation, nil)
        set(\.alerts, [])
        set(\.smoke, SmokeInfo(density: nil, nearSurfaceMaxUgm3: nil, nearSurfaceSource: nil, opticalDepthMax: nil, notes: []))
        set(\.aurora, nil)
        set(\.horizon, HorizonInfo(load: .loading, profile: nil, tallestDegrees: nil, shortened: []))
        set(\.comparison, nil)
        set(\.gaps, [])
        set(\.sourceLines, [])
        set(\.attributions, [])
        set(\.offlineNote, nil)
        set(\.generatedAt, nil)
    }

    private func set<V: Equatable>(_ path: ReferenceWritableKeyPath<ConditionsModel, V>, _ value: V) {
        if self[keyPath: path] != value { self[keyPath: path] = value }
    }
}
