import IterGoActivity
import IterModel
import IterUI
import SwiftUI
import WidgetKit
@testable import Iter

/// One named state to render: a sample snapshot at a fixed moment, with the content the app would push to the activity.
struct GoRenderCase: Sendable {
    var name: String
    var snapshot: GoSnapshot
    var isStale: Bool
    var now: Date

    var content: GoActivityContent { GoActivityContent(snapshot: snapshot) }
    var zone: TimeZone { TimeZone(identifier: "America/Denver")! }
    var clock: GoClock { .frozen(now) }

    /// 16:30 in Denver on 24 Oct 2026, so the samples' times read like an evening.
    static let now = ISO8601DateFormatter().date(from: "2026-10-24T22:30:00Z")!

    static func sample(_ s: GoSample) -> GoRenderCase {
        GoRenderCase(name: s.rawValue, snapshot: s.snapshot(now: now), isStale: s == .stale, now: now)
    }

    /// The long-name case: a real stop name far past what the Live Activity can show on one line.
    static var longName: GoRenderCase {
        var snap = GoSample.drivingOnTime.snapshot(now: now)
        snap.next?.name = "Mesa Arch at Sunrise, Canyonlands Island in the Sky District"
        return GoRenderCase(name: "longName", snapshot: snap, isStale: false, now: now)
    }

    static var all: [GoRenderCase] {
        [GoSample.drivingOnTime, .armedEarly, .leaveNow, .drivingLate, .drivingMissed, .atStopShooting, .paused, .finished, .offline,
         .stale, .idle].map(sample) + [longName]
    }
}

// MARK: Sheets

private let sheetPad: CGFloat = 16

private struct Caption: View {
    let text: String
    var body: some View { Text(verbatim: text).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary) }
}

/// The Lock Screen and Dynamic Island presentations of one case at their real sizes.
struct GoActivitySheet: View {
    let c: GoRenderCase
    @Environment(\.colorScheme) private var scheme

    static let size = CGSize(width: 396, height: 570)

    var body: some View {
        let content = c.content
        VStack(alignment: .leading, spacing: 8) {
            Caption(text: "\(c.name): Lock Screen / banner 364 x 160")
            GoActivityView(tripName: c.snapshot.tripName.isEmpty ? "Canyonlands Weekend" : c.snapshot.tripName, content: content,
                           clock: c.clock, isStale: c.isStale, zone: c.zone)
                .frame(width: 364, height: 160)
                .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.93), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            Caption(text: "Compact (leading 52 + trailing 52) and combined strip")
            HStack(spacing: 14) {
                island(width: 52, height: 37) { GoIslandCompactLeading(content: content, clock: c.clock, isStale: c.isStale, zone: c.zone) }
                island(width: 52, height: 37) { GoIslandCompactTrailing(content: content, clock: c.clock, isStale: c.isStale, zone: c.zone) }
                HStack(spacing: 0) {
                    GoIslandCompactLeading(content: content, clock: c.clock, isStale: c.isStale, zone: c.zone).frame(width: 58, alignment: .trailing)
                    Spacer(minLength: 0).frame(width: 96)
                    GoIslandCompactTrailing(content: content, clock: c.clock, isStale: c.isStale, zone: c.zone).frame(width: 58, alignment: .leading)
                }
                .frame(width: 216, height: 37)
                .background(.black, in: Capsule())
            }
            Caption(text: "Minimal 37 x 37")
            HStack(spacing: 14) {
                island(width: 37, height: 37, circle: true) { GoIslandMinimal(content: content, clock: c.clock, isStale: c.isStale) }
            }
            Caption(text: "Expanded 371 x 160")
            GoIslandExpandedPreview(tripName: c.snapshot.tripName, content: content, clock: c.clock, isStale: c.isStale, zone: c.zone)
                .frame(width: 371, height: 160, alignment: .top)
                .background(.black, in: RoundedRectangle(cornerRadius: 44, style: .continuous))
            Spacer(minLength: 0)
        }
        .padding(sheetPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(scheme == .dark ? Color(white: 0.06) : Color(white: 0.8))
    }

    private func island<V: View>(width: CGFloat, height: CGFloat, circle: Bool = false, @ViewBuilder _ v: () -> V) -> some View {
        v().frame(width: width, height: height)
            .background(.black, in: RoundedRectangle(cornerRadius: circle ? height / 2 : 18, style: .continuous))
    }
}

/// The widget families of one case at their real sizes, plus the accessories as a grey-only (tinted Lock Screen) look.
struct GoWidgetSheet: View {
    let c: GoRenderCase
    @Environment(\.colorScheme) private var scheme

    static let size = CGSize(width: 580, height: 450)

    private func widget(_ family: GoWidgetFamily) -> some View {
        GoWidgetView(snapshot: c.snapshot, clock: c.clock, family: family, isStale: c.isStale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Caption(text: "\(c.name): small 170 x 170, medium 364 x 170")
            HStack(alignment: .top, spacing: 14) {
                widget(.small).padding(16).frame(width: 170, height: 170).background(IterColor.backgroundContent, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                widget(.medium).padding(16).frame(width: 364, height: 170).background(IterColor.backgroundContent, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            Caption(text: "Lock Screen: rectangular 172 x 76, circular 76 x 76, inline 234 x 26")
            HStack(alignment: .center, spacing: 14) { accessories(grey: false) }
            Caption(text: "The same, tinted (grey only: nothing relies on colour)")
            HStack(alignment: .center, spacing: 14) { accessories(grey: true) }
            Spacer(minLength: 0)
        }
        .padding(sheetPad)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(scheme == .dark ? Color(white: 0.06) : Color(white: 0.8))
    }

    @ViewBuilder private func accessories(grey: Bool) -> some View {
        let plate = scheme == .dark ? Color(white: 1, opacity: 0.16) : Color(white: 0, opacity: 0.12)
        Group {
            widget(.accessoryRectangular).padding(.horizontal, 10).padding(.vertical, 6)
                .frame(width: 172, height: 76).background(plate, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            widget(.accessoryCircular).frame(width: 76, height: 76).background(plate, in: Circle())
            widget(.accessoryInline).frame(width: 234, height: 26, alignment: .leading)
        }
        .foregroundStyle(scheme == .dark ? Color.white : Color.black)
        .saturation(grey ? 0 : 1)
    }
}
