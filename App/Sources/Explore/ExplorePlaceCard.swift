import SwiftUI
import IterCore
import IterData
import IterDesign
import IterFeatures

/// The place card over the map for the selected spot (pattern #6): what it is, its light that day, and one
/// primary action (Open), with Save and Add to Trip beside it.
struct ExplorePlaceCard: View {
    let row: ExploreRow
    let day: LocalDay
    var onClose: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.renderMode) private var renderMode

    private var spot: Spot { row.spot }

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.md) {
            HStack(alignment: .top, spacing: IterSpace.sm) {
                VStack(alignment: .leading, spacing: IterSpace.xxs) {
                    Text(spot.name).font(IterFont.headline).foregroundStyle(IterColor.textPrimary)
                    HStack(spacing: IterSpace.xs) {
                        if !spot.locality.isEmpty {
                            Text(spot.locality).lineLimit(1)
                        }
                        ProvenanceTag(origin: spot.origin)
                    }
                    .font(IterFont.subheadline)
                    .foregroundStyle(IterColor.textSecondary)
                }
                Spacer(minLength: IterSpace.sm)
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(IterColor.textTertiary)
                }
                .buttonStyle(.plain)
                .help(String(localized: "Deselect", comment: "Tooltip on the place card's close button"))
                .accessibilityLabel(Text("Close", comment: "VoiceOver"))
            }
            light
            HStack(spacing: IterSpace.sm) {
                Button {
                    ExploreActions.open(spot, day: day, navigation: navigation)
                } label: {
                    Text("Open", comment: "Place card primary action: open the spot page")
                        .frame(minWidth: IterSize.hitTarget)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .help(String(localized: "Open the spot page", comment: "Tooltip"))
                if spot.origin != .user {
                    saveButton
                }
                AddToTripMenu(spot: spot)
                    .menuStyle(.button)
                    .fixedSize()
            }
            .controlSize(.regular)
        }
        .padding(IterSpace.md)
        .frame(maxWidth: IterSize.listIdeal, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: IterRadius.panel, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: IterRadius.panel, style: .continuous)
            .strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Place card for \(spot.name)", comment: "VoiceOver"))
    }

    @ViewBuilder private var light: some View {
        if let window = row.window {
            VStack(alignment: .leading, spacing: IterSpace.xs) {
                HStack(alignment: .center, spacing: IterSpace.md) {
                    LightBadge(window: window, style: .regular)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(TimeText.time(window.span.start, in: spot.timeZone))
                            .font(IterFont.time)
                            .foregroundStyle(IterColor.textPrimary)
                            .monospacedDigit()
                        Text(TimeText.timeRange(window.span, in: spot.timeZone))
                            .font(IterFont.caption)
                            .foregroundStyle(IterColor.textSecondary)
                    }
                }
                if let reason = row.unavailableReason {
                    Text(LightText.noForecastReason(reason))
                        .font(IterFont.caption)
                        .foregroundStyle(IterColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            Text(LightText.noWindowToday).font(IterFont.subheadline).foregroundStyle(IterColor.textSecondary)
        }
    }

    private var saveButton: some View {
        let saved = isSaved
        return Button {
            model.store.setSaved(spot, !saved)
        } label: {
            if saved {
                Label(String(localized: "Saved", comment: "Place card: the spot is saved"), systemImage: "star.fill")
            } else {
                Label(String(localized: "Save", comment: "Place card: save the spot"), systemImage: "star")
            }
        }
        .help(saved ? String(localized: "Remove from Saved", comment: "Tooltip") : String(localized: "Save this spot", comment: "Tooltip"))
    }

    private var isSaved: Bool {
        _ = model.store.revision
        return model.store.isSaved(spotID: spot.id)
    }

    private var background: AnyShapeStyle {
        // An offscreen render has no backdrop for materials.
        renderMode == .snapshot ? AnyShapeStyle(IterColor.backgroundContent) : AnyShapeStyle(.regularMaterial)
    }
}
