import SwiftUI
#if os(macOS)
import AppKit

extension View {
    /// Makes the buttons in this view clickable where the view sits in the window's title bar band.
    ///
    /// The Mac's floating cards start at the top of the window (`FloatingPanelLayout` ignores the top safe area, as Maps'
    /// card does), so their header buttons sit in the band the toolbar occupies. The toolbar's title bar container is a
    /// sibling above the window's content view, and AppKit hands a mouse down in that band to it (to drag the window),
    /// never to the content under it; SwiftUI buttons there looked right and did nothing. This hosts the view in its own
    /// hosting view, added to the window's frame view above the title bar, at the place the view lays out. Only for small
    /// headers: pass what the content needs; the environment does not cross.
    func titlebarClickable() -> some View {
        TitlebarOverlay(content: self)
    }
}

private struct TitlebarOverlay<Content: View>: NSViewRepresentable {
    let content: Content

    func makeNSView(context: Context) -> Anchor<Content> { Anchor(rootView: content) }

    func updateNSView(_ anchor: Anchor<Content>, context: Context) { anchor.host.rootView = content }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView anchor: Anchor<Content>, context: Context) -> CGSize? {
        // Fills the proposed width; the height is the content's own (a header's does not depend on its width).
        CGSize(width: proposal.width ?? anchor.host.fittingSize.width, height: anchor.host.fittingSize.height)
    }
}

/// Takes the header's place in the layout; the real content lives in `host`, above the title bar.
private final class Anchor<Content: View>: NSView {
    let host: NSHostingView<Content>
    private var observers: [any NSObjectProtocol] = []

    init(rootView: Content) {
        host = NSHostingView(rootView: rootView)
        host.safeAreaRegions = []
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let window, let frameView = window.contentView?.superview else {
            host.removeFromSuperview()
            return
        }
        frameView.addSubview(host, positioned: .above, relativeTo: nil)
        for name in [NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.sync() }
            })
        }
        sync()
    }

    override func layout() {
        super.layout()
        sync()
    }

    override func viewDidEndLiveResize() {
        super.viewDidEndLiveResize()
        sync()
    }

    /// Puts the real header over the anchor (window coordinates are the frame view's).
    private func sync() {
        guard window != nil else { return }
        let frame = convert(bounds, to: nil)
        if host.frame != frame { host.frame = frame }
    }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        host.removeFromSuperview()
    }
}
#else
extension View {
    /// iOS has no title bar band: nothing to do.
    func titlebarClickable() -> some View { self }
}
#endif
