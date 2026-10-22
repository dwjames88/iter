import SwiftUI
import IterCore
import IterDesign

/// A stop inside a day card: drag handle, set-up time, number, the place with its light window, the walk-in and set-up
/// line, a note, and the score chip trailing. Plain values and slots, so it draws the same in the list, on iOS and in
/// previews; the owner supplies the window picker, the score chip, the note field and the set-up editor.
struct StopCard<Picker: View, Score: View, Note: View, Editor: View>: View {
    /// "17:07"; nil when the schedule has no set-up time.
    var time: String?
    /// "Set up"
    var timeLabel: String
    var number: Int
    var name: String
    var locality: String
    /// "Park at 16:42 • 25 min walk in"
    var walkText: String
    /// "20 min setup": the button that opens the set-up editor.
    var setUpText: String
    /// Conflict lines (warning colour, each with its icon).
    var issues: [String] = []
    var isSelected = false
    var onOpenSpot: () -> Void
    @Binding var editsSetUp: Bool
    @ViewBuilder var picker: Picker
    @ViewBuilder var score: Score
    @ViewBuilder var note: Note
    @ViewBuilder var setUpEditor: Editor

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(BuilderType.bodyStrong)
                .foregroundStyle(IterColor.textSecondary)
                .frame(height: 20)
                .accessibilityHidden(true)
            HStack(alignment: .top, spacing: 16) {
                TimeLabelColumn(time: time, label: timeLabel, minWidth: 40)
                NumberBadge(number: number)
            }
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Button(action: onOpenSpot) {
                        Text(name).font(BuilderType.bodyStrong).foregroundStyle(IterColor.textSecondary).lineLimit(2)
                    }
                    .buttonStyle(.plain)
                    .help(Text("Open spot page", comment: "Tooltip"))
                    if !locality.isEmpty {
                        Text(locality).font(BuilderType.caption).foregroundStyle(IterColor.textSecondary).lineLimit(1)
                    }
                }
                picker
                infoLine
                ForEach(issues, id: \.self) { issue in
                    Label {
                        Text(issue).font(BuilderType.caption).foregroundStyle(IterColor.warning).fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill").font(BuilderType.caption).foregroundStyle(IterColor.warning)
                    }
                }
                note
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            score.fixedSize()
        }
        .padding(12)
        .background(IterColor.backgroundModule, in: shape)
        .overlay { if isSelected { shape.strokeBorder(IterColor.accent, lineWidth: 1.5) } }
        .contentShape(shape)
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: BuilderMetrics.innerCorner, style: .continuous) }

    /// "ⓘ Park at 16:42 • 25 min walk in • 20 min setup"; the set-up part is a button. Wraps under itself when narrow.
    private var infoLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "info.circle").accessibilityHidden(true)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 4) { parts }.fixedSize()
                VStack(alignment: .leading, spacing: 2) {
                    Text(walkText)
                    setUpButton
                }
            }
        }
        .font(BuilderType.body)
        .foregroundStyle(IterColor.textTertiary)
    }

    @ViewBuilder private var parts: some View {
        Text(walkText)
        Text(verbatim: "•").accessibilityHidden(true)
        setUpButton
    }

    private var setUpButton: some View {
        Button { editsSetUp = true } label: { Text(setUpText) }
            .buttonStyle(.plain)
            .help(Text("Change how long before the window you want to be set up", comment: "Tooltip"))
            .popover(isPresented: $editsSetUp, arrowEdge: .bottom) { setUpEditor }
    }
}

#Preview("Stop card, light") { StopCardPreview().preferredColorScheme(.light) }
#Preview("Stop card, dark") { StopCardPreview().preferredColorScheme(.dark) }

struct StopCardPreview: View {
    var scores: [Int?] = [100, 75, 50, nil]
    var selected = false

    var body: some View {
        VStack(spacing: 4) {
            ForEach(Array(scores.enumerated()), id: \.offset) { index, score in
                StopCard(time: "17:07", timeLabel: "Set up", number: index + 1, name: "Horseshoe Bend", locality: "Page, AZ",
                         walkText: "Park at 16:42 • 25 min walk in", setUpText: "20 min setup",
                         issues: index == 3 ? ["No Sunrise window on this day at this place"] : [],
                         isSelected: selected && index == 0, onOpenSpot: {}, editsSetUp: .constant(false)) {
                    LightWindowPicker(options: [.init(kind: .goldenEvening, title: "Sunset · 6:01–6:31 PM", symbol: "sunset.fill")],
                                      selection: .goldenEvening, closedLabel: "Sunset") { _ in }
                } score: {
                    ScoreChip(window: TripBuilderPreviewData.window(score: score), zone: TripBuilderPreviewData.zone, size: .small)
                } note: {
                    NotePlaceholder(note: "") { _ in }
                } setUpEditor: { EmptyView() }
            }
        }
        .padding(4)
        .frame(width: 608)
        .background(IterColor.backgroundContent)
        .padding(16)
        .background(IterColor.backgroundWindow)
    }
}
