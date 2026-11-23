import Foundation
import IterModel
import IterConditions

/// The named states a Conditions screen is drawn in (docs: honest states). Each is deterministic: fixed place (Mesa Arch,
/// America/Denver), fixed instant (2026-10-12 06:00 local), no network.
public enum ConditionsPreviewState: String, CaseIterable, Sendable {
    /// Nothing yet: no score, the sun and moon compass still works (it is astronomy, not data).
    case loading
    /// The first fast answer (MET Norway): a score with low confidence, everything else still arriving.
    case quick
    /// Every source answered.
    case complete
    /// The forecast is five hours old, older than its time to live.
    case stale
    /// No network: the last good forecast, five hours old, labelled offline.
    case offline
    /// No forecast source covers the place.
    case outOfCoverage
}

@MainActor
public enum ConditionsPreviewData {
    /// A feed holding the state for every day of the outlook.
    public static func feed(_ state: ConditionsPreviewState, selectedDay: LocalDay? = nil,
                            configure: (inout ConditionsFixtures.Options) -> Void = { _ in }) -> FakeConditionsFeed {
        let feed = FakeConditionsFeed()
        let today = ConditionsFixtures.today
        let selected = selectedDay ?? today
        var options = ConditionsFixtures.Options()
        switch state {
        case .loading: break
        case .quick: options.tier = .quick
        case .complete: break
        case .stale:
            options.fetchedAt = ConditionsFixtures.now.addingTimeInterval(-5 * 3600)
            options.staleAge = .seconds(5 * 3600)
        case .offline:
            options.fetchedAt = ConditionsFixtures.now.addingTimeInterval(-5 * 3600)
            options.staleAge = .seconds(5 * 3600)
            options.offline = true
        case .outOfCoverage: options.outOfCoverage = true
        }
        configure(&options)
        for offset in 0..<10 {
            let day = today.adding(days: offset)
            switch state {
            case .loading:
                feed.set(.loading(previous: nil), day: day)
            case .quick where day != selected:
                feed.set(.loading(previous: nil), day: day)
            default:
                feed.set(.ready(ConditionsFixtures.report(day: day, options: options)), day: day)
            }
        }
        if !(0..<10).contains(today.days(until: selected)) {
            feed.set(state == .loading ? .loading(previous: nil) : .ready(ConditionsFixtures.report(day: selected, options: options)), day: selected)
        }
        return feed
    }

    /// A started model in `state`, already populated (no waiting).
    public static func model(_ state: ConditionsPreviewState, selectedDay: LocalDay? = nil,
                             configure: (inout ConditionsFixtures.Options) -> Void = { _ in }) -> ConditionsModel {
        let model = ConditionsModel(place: ConditionsFixtures.place, feed: feed(state, selectedDay: selectedDay, configure: configure),
                                    now: { ConditionsFixtures.now }, selectedDay: selectedDay)
        model.start()
        return model
    }
}
