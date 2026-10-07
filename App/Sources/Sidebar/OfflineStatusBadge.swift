import SwiftUI
import IterDesign
import IterFeatures

/// The words for a trip's offline state, shared by the badge's text, tooltip and VoiceOver label.
enum OfflineStatusText {
    /// nil when the trip has nothing offline to report.
    static func label(_ status: OfflinePackStatus) -> String? {
        switch status {
        case .none:
            nil
        case .downloading(let done, let total):
            String(localized: "Downloading for offline use, \(done) of \(total)", comment: "Offline status of a pinned trip while it downloads")
        case .ready:
            String(localized: "Ready offline", comment: "Offline status of a pinned trip")
        case .stale(_, let reason):
            switch reason {
            case .tripChanged: String(localized: "Trip changed since download", comment: "Offline status: the pinned trip was edited after it downloaded")
            case .forecastOld: String(localized: "Forecast is more than 12 hours old", comment: "Offline status: the downloaded forecast is old")
            case .incomplete: String(localized: "Some items didn't download", comment: "Offline status: part of the download failed")
            }
        case .failed:
            String(localized: "Couldn't download for offline use", comment: "Offline status: the download failed")
        }
    }

    static var baseMapNote: String {
        String(localized: "Pinned trips keep forecasts, drive times, routes and spot images on this Mac. The base map isn't stored: MapKit has no way to download map tiles for offline use.",
               comment: "Tooltip on a pinned trip's offline status")
    }
}

/// A pinned trip's download state as a small glyph (sidebar) or glyph plus words (trip header). Draws nothing when the
/// trip is not pinned or has no offline state.
struct OfflineStatusBadge: View {
    enum Style { case row, header }

    @Environment(AppModel.self) private var model
    let tripID: UUID
    var style: Style = .row

    var body: some View {
        let status = model.offline.status(for: tripID)
        if let text = OfflineStatusText.label(status) {
            Group {
                switch style {
                case .row:
                    glyph(status)
                case .header:
                    HStack(spacing: IterSpace.xs) {
                        glyph(status)
                        Text(text).font(IterFont.subheadline)
                    }
                    .foregroundStyle(IterColor.textSecondary)
                }
            }
            .help(style == .header ? OfflineStatusText.baseMapNote : text)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(text))
        }
    }

    @ViewBuilder private func glyph(_ status: OfflinePackStatus) -> some View {
        switch status {
        case .none:
            EmptyView()
        case .downloading(let done, let total):
            if total > 0 {
                ProgressView(value: Double(min(done, total)), total: Double(total))
                    .progressViewStyle(.circular).controlSize(.mini)
            } else {
                ProgressView().controlSize(.mini)
            }
        case .ready:
            Image(systemName: "checkmark.circle").foregroundStyle(IterColor.textSecondary)
        case .stale:
            Image(systemName: "exclamationmark.arrow.circlepath").foregroundStyle(IterColor.warning)
        case .failed:
            Image(systemName: "exclamationmark.triangle").foregroundStyle(IterColor.warning)
        }
    }
}
