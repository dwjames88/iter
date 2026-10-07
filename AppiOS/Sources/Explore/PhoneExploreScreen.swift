import SwiftUI
import IterCore
import IterDesign
import IterFeatures

/// iPhone Explore tab: full-bleed map with the in-tab bottom sheet (peek / half / full). OWNER: Explore.
struct PhoneExploreScreen: View {
    @Environment(ExploreModel.self) private var explore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var detent = AppLaunch.sheetDetent ?? .half
    /// How far the header has been dragged down from the detent's height (negative = up).
    @State private var dragTranslation: CGFloat = 0

    private static let peekHeight: CGFloat = 150
    private static let topGap: CGFloat = 8

    var body: some View {
        if AppLaunch.previewSearch { ExploreSearchScreen() } else { explorer }
    }

    private var explorer: some View {
        GeometryReader { geo in
            let available = geo.size.height
            let heights = Heights(peek: Self.peekHeight, half: max(available * 0.5, Self.peekHeight + 40), full: max(available - Self.topGap, 300))
            let current = clamp(heights.value(detent) - dragTranslation, heights)
            ZStack(alignment: .bottom) {
                ExploreMapLayer(explore: explore, bottomInset: min(heights.value(detent), heights.half) - (geo.safeAreaInsets.bottom > 0 ? 0 : 0),
                                onPinSelected: { if detent == .peek { move(to: .half) } })
                sheet(height: current, heights: heights)
            }
            .onChange(of: explore.showsPanel) { _, shows in
                if shows, detent == .peek { move(to: .half) }
            }
            .onChange(of: explore.rows.isEmpty) { _, empty in
                if empty, detent == .peek { move(to: .half) }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { explore.requestInitialCamera() }
    }

    private struct Heights {
        let peek, half, full: CGFloat
        func value(_ d: SheetDetent) -> CGFloat { switch d { case .peek: peek; case .half: half; case .full: full } }
        var all: [(SheetDetent, CGFloat)] { [(.peek, peek), (.half, half), (.full, full)] }
    }

    private func clamp(_ h: CGFloat, _ heights: Heights) -> CGFloat { min(max(h, heights.peek - 24), heights.full) }

    private func move(to new: SheetDetent) {
        if reduceMotion { detent = new } else { withAnimation(.spring(duration: 0.38, bounce: 0.18)) { detent = new } }
    }

    private func sheet(height: CGFloat, heights: Heights) -> some View {
        let drag = SheetDrag(changed: { dragTranslation = $0 }, ended: { translation, predicted in
            let projected = heights.value(detent) - predicted
            let target = heights.all.min { abs($0.1 - projected) < abs($1.1 - projected) }?.0 ?? detent
            _ = translation
            if reduceMotion { detent = target; dragTranslation = 0 }
            else { withAnimation(.spring(duration: 0.38, bounce: 0.18)) { detent = target; dragTranslation = 0 } }
        })
        return VStack(spacing: 0) {
            grabber.sheetDrag(drag)
            ExploreBrowser(explore: explore, drag: drag, onOpenPlace: { if detent == .peek { move(to: .half) } })
        }
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .top)
        .background(IterColor.backgroundContent,
                    in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 16, y: -2)
    }

    private var grabber: some View {
        Button { move(to: detent.next) } label: {
            Capsule().fill(IterColor.textTertiary.color.opacity(0.6)).frame(width: 36, height: 5)
                .frame(maxWidth: .infinity).frame(height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Places sheet", comment: "VoiceOver: the draggable sheet's handle"))
        .accessibilityValue(detentName)
        .accessibilityHint(Text("Swipe up or down to change the height", comment: "VoiceOver hint"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: move(to: detent.up)
            case .decrement: move(to: detent.down)
            @unknown default: break
            }
        }
    }

    private var detentName: Text {
        switch detent {
        case .peek: Text("Peek", comment: "Sheet height")
        case .half: Text("Half", comment: "Sheet height")
        case .full: Text("Full", comment: "Sheet height")
        }
    }
}
