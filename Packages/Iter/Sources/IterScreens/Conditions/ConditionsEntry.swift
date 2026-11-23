import SwiftUI
import IterFeatures
import IterModel
import IterUI

/// The stack of modules (no scrolling of its own), so the place page can put its header above it in one scroll view.
struct ConditionsStack: View {
    let model: ConditionsModel

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.xl) {
            ConditionsStateLine(model: model)
            WhenToGoModule(model: model)
            OutlookModule(model: model)
            WindowsModule(model: model)
            SkyModule(model: model)
            HourlyModule(model: model)
            NowModule(model: model)
            GoodToKnowModule(model: model)
            SourcesFoot(model: model)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Every Conditions section for one place, stacked (when to go, outlook, windows, timeline, compass, hourly, now, alerts,
/// smoke, aurora, horizon, comparison, gaps, source lines). Scrolls itself. Starts the model when it appears; the host calls
/// `model.stop()` when the place goes away.
public struct ConditionsSections: View {
    let model: ConditionsModel
    public init(model: ConditionsModel) { self.model = model }
    public var body: some View {
        ScrollView {
            ConditionsStack(model: model)
                .padding(IterSpace.lg)
        }
        .onAppear { model.start() }
    }
}

/// A compact summary (headline window with its score chip, when to go) for cards and lists.
public struct ConditionsSummary: View {
    let model: ConditionsModel
    public init(model: ConditionsModel) { self.model = model }

    public var body: some View {
        let zone = model.place.timeZone
        HStack(alignment: .center, spacing: IterGrid.laneGap) {
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                if let h = model.headline {
                    HStack(spacing: IterSpace.xs) {
                        WindowSymbol(kind: h.kind, font: .system(size: 14))
                        Text(verbatim: ConditionsFormat.headlineTitle(kind: h.kind, timeline: model.timeline, windows: model.windows, zone: zone))
                            .font(IterFont.headline).foregroundStyle(IterColor.textPrimary)
                    }
                } else {
                    SkeletonBar(width: 140, height: 14)
                }
                if let best = model.whenToGo {
                    Text(verbatim: ConditionsFormat.bestLine(best)).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
                }
                if let line = ConditionsFormat.stateLine(model.status, placeName: model.place.name, generatedAt: model.generatedAt,
                                                         offlineNote: model.offlineNote, zone: zone) {
                    Text(verbatim: line.text).font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            HeadlineChip(model: model, size: .large)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { model.start() }
    }
}
