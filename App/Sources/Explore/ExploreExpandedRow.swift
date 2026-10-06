import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// What an expanded Explore row shows beneath its summary: Save and Add to Trip, the day's scored windows, the
/// hourly cloud, rain and visibility, sunrise and sunset, and the forecast source. All of it is the spot page's own
/// sections drawn in `.compact` density, so the list and the page never disagree.
struct ExploreExpandedRow: View {
    let row: ExploreRow
    let day: LocalDay

    var body: some View {
        ExploreExpandedContent(row: row, day: day)
            .id("\(row.id)-\(day.description)")
    }
}

/// The list row that follows an expanded summary row: the expanded content on its own neutral rounded surface.
/// It is a separate, non-selectable row, so the list's accent selection highlight covers the summary line only
/// and never floods the content. `backgroundProminence` is reset so text keeps its normal (not white-on-accent) styles.
struct ExploreExpansionRow: View {
    let row: ExploreRow
    let day: LocalDay

    var body: some View {
        ExploreExpandedRow(row: row, day: day)
            .padding(IterSpace.md)
            .background(IterColor.backgroundWindow, in: RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: IterRadius.card, style: .continuous)
                .strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline))
            .environment(\.backgroundProminence, .standard)
            .padding(.bottom, IterSpace.xs)
    }
}

private struct ExploreExpandedContent: View {
    let row: ExploreRow
    let day: LocalDay
    @Environment(AppModel.self) private var model
    @State private var page: SpotModel?

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.md) {
            actions
            if let page {
                DayWindowsSection(page: page)
                HourlyWeatherSection(page: page)
                SunTimesLine(page: page)
                if let forecast = page.forecast {
                    ForecastSourceLine(info: ForecastSourceInfo(forecast))
                } else if let reason = page.unavailableReason {
                    Text(LightText.noForecastReason(reason))
                        .font(IterFont.caption)
                        .foregroundStyle(IterColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .environment(\.spotDensity, .compact)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .task {
            let made = SpotModel(app: model, spot: row.spot, initialDay: day)
            page = made
            await made.start()
        }
    }

    private var spot: Spot { row.spot }

    private var actions: some View {
        HStack(spacing: IterSpace.sm) {
            if spot.origin != .user { saveButton }
            AddToTripMenu(spot: spot)
                .menuStyle(.button)
                .buttonStyle(.bordered)
                .fixedSize()
                .help(String(localized: "Add this spot to a trip", comment: "Tooltip"))
            Spacer(minLength: 0)
        }
        .controlSize(.small)
    }

    private var saveButton: some View {
        let saved = isSaved
        return Button {
            model.store.setSaved(spot, !saved)
        } label: {
            if saved {
                Label(String(localized: "Saved", comment: "Expanded row: the spot is saved"), systemImage: "bookmark.fill")
            } else {
                Label(String(localized: "Save", comment: "Expanded row: save the spot"), systemImage: "bookmark")
            }
        }
        .buttonStyle(.bordered)
        .help(saved ? String(localized: "Remove from Saved", comment: "Tooltip") : String(localized: "Save this spot", comment: "Tooltip"))
        .accessibilityLabel(saved
            ? Text("Remove \(spot.name) from Saved", comment: "VoiceOver")
            : Text("Save \(spot.name)", comment: "VoiceOver"))
    }

    private var isSaved: Bool {
        _ = model.store.revision
        return model.store.isSaved(spotID: spot.id)
    }
}
