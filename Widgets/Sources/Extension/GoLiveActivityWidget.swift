import ActivityKit
import IterGoActivity
import IterUI
import SwiftUI
import WidgetKit

/// The trip-mode Live Activity (Lock Screen, banner, StandBy, Dynamic Island). The app starts and updates it while it runs;
/// without push (free team) nothing else can, so every view shows the age of its data and keeps counting from absolute dates.
struct GoLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: GoActivityAttributes.self) { context in
            GoActivityView(tripName: context.attributes.tripName, content: context.state, clock: .live(.now), isStale: context.isStale)
                .widgetURL(GoDeepLink.go)
                .activityBackgroundTint(nil)
        } dynamicIsland: { context in
            let content = context.state
            let stale = context.isStale
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    GoIslandExpandedLeading(content: content, clock: .live(.now), isStale: stale)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    GoIslandExpandedTrailing(content: content, clock: .live(.now), isStale: stale)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    GoIslandExpandedBottom(content: content, clock: .live(.now), isStale: stale)
                }
            } compactLeading: {
                GoIslandCompactLeading(content: content, clock: .live(.now), isStale: stale)
            } compactTrailing: {
                GoIslandCompactTrailing(content: content, clock: .live(.now), isStale: stale)
            } minimal: {
                GoIslandMinimal(content: content, clock: .live(.now), isStale: stale)
            }
            .widgetURL(GoDeepLink.go)
            .keylineTint(keyline(content))
        }
    }

    private func keyline(_ content: GoActivityContent) -> Color {
        if let score = content.liveScore ?? content.forecastScore { return IterColor.ramp(score: score) }
        return IterColor.accent
    }
}
