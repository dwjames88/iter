import SwiftUI

/// The three resting heights of the phone's Explore sheet.
enum SheetDetent: String, CaseIterable, Sendable {
    case peek, half, full

    var next: SheetDetent {
        switch self { case .peek: .half; case .half: .full; case .full: .peek }
    }
    var up: SheetDetent { self == .peek ? .half : .full }
    var down: SheetDetent { self == .full ? .half : .peek }
}

/// A drag on the sheet's header: the vertical translation so far (down is positive), and at the end the translation and
/// where it was predicted to end.
struct SheetDrag {
    var changed: @MainActor (CGFloat) -> Void
    var ended: @MainActor (_ translation: CGFloat, _ predicted: CGFloat) -> Void
}

extension View {
    /// Makes the view drag the sheet, when there is a sheet.
    @ViewBuilder func sheetDrag(_ drag: SheetDrag?) -> some View {
        if let drag {
            gesture(DragGesture(minimumDistance: 6, coordinateSpace: .global)
                .onChanged { drag.changed($0.translation.height) }
                .onEnded { drag.ended($0.translation.height, $0.predictedEndTranslation.height) })
        } else {
            self
        }
    }
}
