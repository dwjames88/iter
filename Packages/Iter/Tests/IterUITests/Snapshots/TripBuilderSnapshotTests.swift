import Foundation
import IterModel
import SwiftUI
import Testing

@testable import IterUI

/// The Trip Builder parts, light and dark: `builder-<part>-<state>-<light|dark>.png` in `Design/snapshots/rebuild/`.
@MainActor
@Suite(.serialized) struct TripBuilderSnapshotTests {
    static let zone = TimeZone(identifier: "America/Phoenix")!
    static let locale = Locale(identifier: "en_GB")
    static let day = LocalDay(year: 2026, month: 10, day: 6)

    static func at(_ h: Int, _ m: Int) -> Date { day.at(hour: h, minute: m, in: zone) }

    private func ground<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(IterColor.backgroundWindow)
    }

    // MARK: Sample parts

    static let meta: [TripMetaItem] = [
        .dates(from: day, to: day.adding(days: 3), locale: locale, action: {}),
        .size(days: 4, stops: 6, locale: locale),
        .driving(seconds: 574 * 60, meters: 788_000, locale: locale),
    ]

    static func actions() -> some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Button {} label: { Label("Share", systemImage: "square.and.arrow.up") }
                Button {} label: { Label("More", systemImage: "ellipsis") }
            }
            .buttonStyle(GlassCircleButtonStyle(diameter: 36))
        }
    }

    static let summaries = [
        DaySummary(index: 0, date: day, stopCount: 1, session: .goldenEvening),
        DaySummary(index: 1, date: day.adding(days: 1), stopCount: 2, session: .goldenMorning),
        DaySummary(index: 2, date: day.adding(days: 2), stopCount: 0),
    ]

    static func picker(_ kind: LightWindowKind = .goldenEvening) -> some View {
        LightWindowPicker(options: [
            .init(kind: .goldenMorning, start: at(6, 55), end: at(7, 30), score: 71),
            .init(kind: .goldenEvening, start: at(17, 55), end: at(18, 30), score: 100),
        ], selection: .constant(kind), zone: zone, locale: locale)
    }

    static func stop(_ n: Int, name: String = "Horseshoe Bend", score: Int?, selected: Bool = false,
                     issues: [String] = [], note: String = "") -> some View {
        StopCard(time: "17:07", timeLabel: "Set up", number: n, name: name, locality: "Page, AZ",
                 walkText: TripBuilderText.parkLine(parkAt: at(16, 42), walkMinutes: 25, in: zone, locale: locale),
                 setUpText: TripBuilderText.setUpShort(minutes: 20, locale: locale), issues: issues, isSelected: selected,
                 onOpenSpot: {}, editsSetUp: .constant(false)) {
            picker()
        } score: {
            ScoreChip(kind: .goldenEvening, start: at(17, 55), end: at(18, 30), score: score, zone: zone, locale: locale, size: .small)
        } note: {
            NotePlaceholder(text: .constant(note))
        } setUpEditor: { EmptyView() }
    }

    static func driveRow(_ style: DriveSegmentRow.Style, estimate: Bool = false, shortBy: TimeInterval? = nil, note: String = "") -> some View {
        DriveSegmentRow(style: style, leaveBy: at(14, 35), drive: .init(seconds: 139 * 60, meters: 162_543, isEstimate: estimate),
                        shortBy: shortBy, note: .constant(note), zone: zone, locale: locale)
    }

    static let overnight = DriveSegmentRow.Overnight(place: "Page, AZ", coordinate: Coordinate(latitude: 36.9, longitude: -111.45))

    // MARK: Tests

    @Test func headerCard() async throws {
        let view = ground {
            TripHeaderCard(title: "Canyon Country", meta: Self.meta, onRename: { _ in }) { Self.actions() }
                .padding(BuilderMetrics.panelInset)
        }
        try await Snapshot.assertMatches(view, name: "builder-header-card", size: CGSize(width: 672, height: 170))
    }

    @Test func metaRow() async throws {
        let view = ground {
            VStack(alignment: .leading, spacing: 16) {
                TripMetaRow(items: Self.meta).frame(width: 560, alignment: .leading)
                    .padding(IterSpace.xl).background(IterColor.backgroundContent)
                TripMetaRow(items: Self.meta).frame(width: 330, alignment: .leading)
                    .padding(IterSpace.xl).background(IterColor.backgroundContent)
                TripMetaRow(items: Self.meta).frame(width: 220, alignment: .leading)
                    .padding(IterSpace.xl).background(IterColor.backgroundContent)
            }
            .padding(BuilderMetrics.panelInset)
        }
        try await Snapshot.assertMatches(view, name: "builder-meta-row", size: CGSize(width: 672, height: 300))
    }

    @Test func daySelector() async throws {
        let view = ground {
            VStack(spacing: 0) {
                DaySelector(summaries: Self.summaries, selectedDay: 0, locale: Self.locale) { _ in }
                DaySelector(summaries: Self.summaries, selectedDay: nil, locale: Self.locale) { _ in }
            }
        }
        try await Snapshot.assertMatches(view, name: "builder-day-selector", size: CGSize(width: 672, height: 330))
    }

    @Test func dayCardHeader() async throws {
        let view = ground {
            VStack(spacing: 12) {
                DayCardHeader(dayName: "Day 1", date: TripBuilderText.dayCardDate(Self.day, locale: Self.locale),
                              totals: TripBuilderText.dayTotals(stops: 1, drivingSeconds: 0, locale: Self.locale),
                              sunrise: TripBuilderText.sunTime(.goldenMorning, at: Self.at(6, 25), in: Self.zone, locale: Self.locale),
                              sunset: TripBuilderText.sunTime(.goldenEvening, at: Self.at(18, 1), in: Self.zone, locale: Self.locale))
                DayCardHeader(dayName: "Day 2", date: TripBuilderText.dayCardDate(Self.day.adding(days: 1), locale: Self.locale),
                              totals: TripBuilderText.dayTotals(stops: 2, drivingSeconds: 326 * 60, locale: Self.locale),
                              sunrise: "Sunrise at 07:21", sunset: "Sunset at 18:54")
            }
            .padding(16)
            .background(IterColor.backgroundContent, in: RoundedRectangle(cornerRadius: BuilderMetrics.cardCorner, style: .continuous))
            .padding(16)
        }
        try await Snapshot.assertMatches(view, name: "builder-day-card-header", size: CGSize(width: 672, height: 220))
    }

    @Test func stopCard() async throws {
        let view = ground {
            VStack(spacing: 4) {
                Self.stop(1, score: 100)
                Self.stop(2, score: 75, selected: true)
                Self.stop(3, score: nil)
                Self.stop(4, score: 50, issues: ["No Sunrise window on this day at this place", "Closes before the window ends"])
                Self.stop(5, name: "Monument Valley Navajo Tribal Park Visitor Center and Scenic Drive Overlook", score: 25,
                          note: "Park in the lower lot, the light comes over the left butte")
            }
            .padding(4)
            .background(IterColor.backgroundContent)
            .padding(16)
        }
        try await Snapshot.assertMatches(view, name: "builder-stop-card", size: CGSize(width: 672, height: 800))
    }

    @Test func driveSegments() async throws {
        let view = ground {
            VStack(spacing: 24) {
                Self.driveRow(.inline, note: "Fuel in Kanab").background(IterColor.backgroundContent)
                Self.driveRow(.inline, estimate: true).background(IterColor.backgroundContent)
                Self.driveRow(.inline, shortBy: 25 * 60).background(IterColor.backgroundContent)
                Self.driveRow(.transfer(timing: .constant(.morning), from: "Horseshoe Bend", overnight: nil))
                Self.driveRow(.transfer(timing: .constant(.eveningBefore), from: "Horseshoe Bend", overnight: Self.overnight),
                              note: "Dinner in Kanab on the way")
            }
            .padding(16)
        }
        try await Snapshot.assertMatches(view, name: "builder-drive-segments", size: CGSize(width: 672, height: 470))
    }

    @Test func badges() async throws {
        let view = ground {
            HStack(spacing: IterSpace.lg) {
                NumberBadge(number: 1)
                NumberBadge(number: 12)
                NumberBadge(number: 2, style: .neutral)
                DriveBadge()
                TimeLabelColumn(time: "17:07", label: "Set up")
            }
            .padding(BuilderMetrics.panelInset)
        }
        try await Snapshot.assertMatches(view, name: "builder-badges", size: CGSize(width: 320, height: 80))
    }

    @Test func footer() async throws {
        func foot(_ overnight: String?, hotels: Bool = false) -> some View {
            HStack(spacing: 8) {
                AddStopButton {}
                Spacer(minLength: 8)
                if let overnight { OvernightNote(text: overnight) }
                if hotels { FindHotelsButton(latitude: 36.9, longitude: -111.45) }
            }
            .padding(12 + BuilderMetrics.bodyInset)
            .background(DayCardBackground(position: .only, inset: 0))
        }
        let view = ground {
            VStack(spacing: 16) {
                foot(nil)
                foot("Overnight near Page, AZ")
                foot("Overnight near Page, AZ", hotels: true)
            }
            .padding(BuilderMetrics.panelInset)
        }
        try await Snapshot.assertMatches(view, name: "builder-footer", size: CGSize(width: 672, height: 300))
    }

    @Test func lightWindowPicker() async throws {
        let view = ground {
            HStack(spacing: IterSpace.xl) {
                Self.picker(.goldenEvening)
                Self.picker(.goldenMorning)
            }
            .padding(IterSpace.xl)
            .background(IterColor.backgroundModule)
            .padding(IterSpace.xl)
        }
        try await Snapshot.assertMatches(view, name: "builder-light-window-picker", size: CGSize(width: 400, height: 120))
    }

    @Test func notePlaceholder() async throws {
        let view = ground {
            VStack(alignment: .leading, spacing: IterSpace.lg) {
                NotePlaceholder(text: .constant(""))
                NotePlaceholder(text: .constant("Park in the lower lot"))
                NotePlaceholder(text: .constant(""), prompt: NotePlaceholder.driveNotePrompt, accessibilityName: NotePlaceholder.driveNoteName)
            }
            .frame(width: 260, alignment: .leading)
            .padding(IterSpace.xl)
            .background(IterColor.backgroundModule)
            .padding(IterSpace.xl)
        }
        try await Snapshot.assertMatches(view, name: "builder-note-placeholder", size: CGSize(width: 340, height: 180))
    }

    @Test func module() async throws {
        func dayHeader(_ i: Int, stops: Int, driving: TimeInterval) -> some View {
            DayCardHeader(dayName: TripBuilderText.dayName(index: i, locale: Self.locale),
                          date: TripBuilderText.dayCardDate(Self.day.adding(days: i), locale: Self.locale),
                          totals: TripBuilderText.dayTotals(stops: stops, drivingSeconds: driving, locale: Self.locale),
                          sunrise: TripBuilderText.sunTime(.goldenMorning, at: Self.at(6, 25), in: Self.zone, locale: Self.locale),
                          sunset: TripBuilderText.sunTime(.goldenEvening, at: Self.at(18, 1), in: Self.zone, locale: Self.locale))
        }
        let view = ground {
            VStack(spacing: BuilderMetrics.sectionGap) {
                TripHeaderCard(title: "Canyon Country", meta: Self.meta, onRename: { _ in }) { Self.actions() }
                DaySelector(summaries: Self.summaries, selectedDay: 0, locale: Self.locale) { _ in }
                    .padding(.horizontal, -16)
                DayCard {
                    dayHeader(0, stops: 2, driving: 139 * 60)
                } content: {
                    Self.stop(1, score: 100, selected: true)
                    Self.driveRow(.inline, note: "Fuel in Kanab")
                    Self.stop(2, name: "Antelope Canyon", score: 75)
                    HStack {
                        AddStopButton {}
                        Spacer()
                        OvernightNote(place: "Page, AZ", locale: Self.locale)
                    }
                    .padding(12)
                }
                Self.driveRow(.transfer(timing: .constant(.eveningBefore), from: "Antelope Canyon", overnight: Self.overnight))
                DayCard {
                    dayHeader(1, stops: 1, driving: 0)
                } content: {
                    Self.stop(3, name: "Monument Valley", score: nil)
                    HStack { AddStopButton {}; Spacer() }.padding(12)
                }
            }
            .padding(.horizontal, BuilderMetrics.panelInset)
            .padding(.top, BuilderMetrics.panelInset)
        }
        try await Snapshot.assertMatches(view, name: "builder-module", size: CGSize(width: 639, height: 1200))
    }
}
