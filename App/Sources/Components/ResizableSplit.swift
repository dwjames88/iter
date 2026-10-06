import SwiftUI
import IterDesign

/// A leading pane and a trailing pane with a draggable divider (replaces `HSplitView`, whose reported minimum
/// width was inflated and which left the trailing pane short of the container).
///
/// The leading width is clamped to `[IterSize.listColumnMin, min(IterSize.listMax, total - detailMin - divider)]`,
/// so the trailing pane never drops below `IterSize.detailMin`, and it is remembered per screen.
struct ResizableSplit<Leading: View, Trailing: View>: View {
    @AppStorage private var storedWidth: Double
    private let leading: Leading
    private let trailing: Trailing
    private let idealWidth: CGFloat
    @State private var dragStart: CGFloat?

    init(storageKey: String, idealWidth: CGFloat,
         @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        _storedWidth = AppStorage(wrappedValue: 0, "ResizableSplit.\(storageKey)")
        self.idealWidth = idealWidth
        self.leading = leading()
        self.trailing = trailing()
    }

    /// The minimum the whole split needs: leading minimum, divider and trailing minimum.
    static var minimumWidth: CGFloat { IterSize.listColumnMin + IterSize.detailMin + 1 }

    var body: some View {
        GeometryReader { proxy in
            let width = clamped(storedWidth > 0 ? CGFloat(storedWidth) : idealWidth, total: proxy.size.width)
            HStack(spacing: 0) {
                leading.frame(width: width).frame(maxHeight: .infinity)
                divider(width: width, total: proxy.size.width)
                trailing.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: Self.minimumWidth, maxWidth: .infinity, maxHeight: .infinity)
    }

    private func clamped(_ value: CGFloat, total: CGFloat) -> CGFloat {
        let upper = max(IterSize.listColumnMin, min(IterSize.listMax, total - IterSize.detailMin - 1))
        return min(max(value, IterSize.listColumnMin), upper)
    }

    /// One point of separator colour inside a wider invisible hit area.
    private func divider(width: CGFloat, total: CGFloat) -> some View {
        Rectangle()
            .fill(IterColor.separator)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .overlay {
                Color.clear
                    .frame(width: IterSize.hitTarget / 2)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { drag in
                                let start = dragStart ?? width
                                dragStart = start
                                storedWidth = Double(clamped(start + drag.translation.width, total: total))
                            }
                            .onEnded { _ in dragStart = nil }
                    )
            }
            .accessibilityHidden(true)
    }
}
