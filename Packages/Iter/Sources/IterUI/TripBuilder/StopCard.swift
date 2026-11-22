import SwiftUI

/// A stop inside a day card: drag handle, set-up time, number, the place with its light window, the walk-in and set-up
/// line, a note, and the score chip trailing. Plain values and slots, so it draws the same in the list, on iOS and in
/// previews; the owner supplies the window picker, the score chip, the note field and the set-up editor.
/// Figma part: stop card.
public struct StopCard<Picker: View, Score: View, Note: View, Editor: View>: View {
    /// "17:07"; nil when the schedule has no set-up time.
    public var time: String?
    /// "Set up"
    public var timeLabel: String
    public var number: Int
    public var name: String
    public var locality: String
    /// "Park at 16:42 • 25 min walk in"
    public var walkText: String
    /// "20 min setup": the button that opens the set-up editor.
    public var setUpText: String
    /// Conflict lines (warning colour, each with its icon).
    public var issues: [String]
    public var isSelected: Bool
    public var onOpenSpot: () -> Void
    @Binding public var editsSetUp: Bool
    let picker: Picker
    let score: Score
    let note: Note
    let setUpEditor: Editor

    public init(time: String?, timeLabel: String, number: Int, name: String, locality: String, walkText: String,
                setUpText: String, issues: [String] = [], isSelected: Bool = false,
                onOpenSpot: @escaping () -> Void, editsSetUp: Binding<Bool>,
                @ViewBuilder picker: () -> Picker, @ViewBuilder score: () -> Score,
                @ViewBuilder note: () -> Note, @ViewBuilder setUpEditor: () -> Editor) {
        self.time = time
        self.timeLabel = timeLabel
        self.number = number
        self.name = name
        self.locality = locality
        self.walkText = walkText
        self.setUpText = setUpText
        self.issues = issues
        self.isSelected = isSelected
        self.onOpenSpot = onOpenSpot
        self._editsSetUp = editsSetUp
        self.picker = picker()
        self.score = score()
        self.note = note()
        self.setUpEditor = setUpEditor()
    }

    public var body: some View {
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
                    .help(Text("Open spot page", bundle: .module, comment: "Tooltip"))
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
            .help(Text("Change how long before the window you want to be set up", bundle: .module, comment: "Tooltip"))
            .popover(isPresented: $editsSetUp, arrowEdge: .bottom) { setUpEditor }
    }
}
