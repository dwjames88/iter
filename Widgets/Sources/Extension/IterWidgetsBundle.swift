import SwiftUI
import WidgetKit
import IterUI

struct RebuildEntry: TimelineEntry {
    let date: Date
}

struct RebuildProvider: TimelineProvider {
    func placeholder(in context: Context) -> RebuildEntry { RebuildEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (RebuildEntry) -> Void) {
        completion(RebuildEntry(date: .now))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<RebuildEntry>) -> Void) {
        completion(Timeline(entries: [RebuildEntry(date: .now)], policy: .never))
    }
}

struct RebuildWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: IterUIModule.name, provider: RebuildProvider()) { _ in
            Text("Rebuild")
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Iter")
        .description("Placeholder.")
        .supportedFamilies([.systemSmall])
    }
}

@main
struct IterWidgetBundle: WidgetBundle {
    var body: some Widget {
        RebuildWidget()
    }
}
