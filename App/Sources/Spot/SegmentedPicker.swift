import SwiftUI
import IterDesign
#if os(macOS)
import AppKit
#endif

/// The system segmented control stretched to the full width of its container, with equal segments. SwiftUI's own
/// segmented `Picker` keeps its intrinsic width on the Mac, so there the same `NSSegmentedControl` is hosted with
/// `fillEqually`; on iOS the `Picker` already fills the width.
struct FullWidthSegmentedPicker<Value: Hashable>: View {
    let label: String
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    var help: String?

    var body: some View {
        #if os(macOS)
        MacSegmented(label: label, options: options, selection: $selection, help: help)
            .frame(maxWidth: .infinity)
            .accessibilityLabel(label)
        #else
        Picker(selection: $selection) {
            ForEach(options.indices, id: \.self) { i in Text(options[i].title).tag(options[i].value) }
        } label: { Text(label) }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        #endif
    }
}

#if os(macOS)
private struct MacSegmented<Value: Hashable>: NSViewRepresentable {
    let label: String
    let options: [(value: Value, title: String)]
    @Binding var selection: Value
    var help: String?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: options.map(\.title), trackingMode: .selectOne,
                                         target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        control.segmentDistribution = .fillEqually
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setAccessibilityLabel(label)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = Box(set: { index in
            guard options.indices.contains(index) else { return }
            selection = options[index].value
        })
        control.toolTip = help
        if let index = options.firstIndex(where: { $0.value == selection }), control.selectedSegment != index {
            control.selectedSegment = index
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSSegmentedControl, context: Context) -> CGSize? {
        let intrinsic = nsView.intrinsicContentSize
        return CGSize(width: proposal.width ?? intrinsic.width, height: intrinsic.height)
    }

    struct Box { var set: (Int) -> Void }

    @MainActor final class Coordinator: NSObject {
        var parent = Box(set: { _ in })
        @objc func changed(_ sender: NSSegmentedControl) { parent.set(sender.selectedSegment) }
    }
}
#endif
