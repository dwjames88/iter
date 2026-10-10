import SwiftUI
import MapKit
import IterCore
import IterDesign
import IterFeatures

/// How a pin looks while it is carried: up a little, with a soft shadow below it. Shared by the live maps and the snapshot
/// stand-ins, so what the snapshot shows is what the map draws. Reduce Motion keeps the lift but drops the motion.
/// Solid shadow only: map pins are plates, never material (Design/GLASS-RULES.md).
struct LiftedPin: ViewModifier {
    let isLifted: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// A pointer sees the pin rise 5 pt; a finger covers the pin, so on a touch screen it rises further.
    private var lift: CGFloat {
        #if os(macOS)
        PinDrag.liftPoints
        #else
        IterSpace.md
        #endif
    }

    private var shadowRadius: CGFloat {
        #if os(macOS)
        4
        #else
        IterSpace.sm
        #endif
    }

    private var shadowOffset: CGFloat {
        #if os(macOS)
        3
        #else
        IterSpace.sm
        #endif
    }

    func body(content: Content) -> some View {
        content
            .shadow(color: .black.opacity(isLifted ? 0.3 : 0), radius: isLifted ? shadowRadius : 0, y: isLifted ? shadowOffset : 0)
            .offset(y: isLifted ? -lift : 0)
            .animation(reduceMotion ? nil : .smooth, value: isLifted)
    }
}

/// The exact point of one of your own spots, under its pin: the pointer ends here, so the place is never read off the pin.
struct PinTipDot: View {
    var body: some View {
        Circle()
            .fill(IterColor.mapPin)
            .frame(width: IterSpace.sm, height: IterSpace.sm)
            .overlay(Circle().strokeBorder(IterColor.separator, lineWidth: IterStroke.hairline))
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// What a finished drag reports to a map that wants to know (the Mac pin-drag probe): the coordinate the drop point
/// converts to, how far the pointer travelled, and where the pin's tip was when it was picked up (window space).
struct PinDrop {
    var id: String
    var expected: Coordinate?
    var delta: CGSize
    var tipBefore: CGPoint?
}

extension View {
    /// Lets you move one of your own spots on a map, one behaviour on both platforms. Apply it to the pin's drawing inside its
    /// annotation; draw the annotation at `host.displayCoordinate(for:stored:)` with its tip anchor (`MapPinAnchor`).
    ///
    /// - Mac: drag straight away (3 pt), open and closed hand, a tooltip.
    /// - iPhone and iPad: touch and hold 0.3 s until it lifts (haptic), then drag; a swipe still pans, a tap still selects.
    /// - Both: the pin rises 5 pt with a shadow while held; the point under the pointer keeps its place relative to the tip;
    ///   the drop is the tip, converted in window space; nothing is stored unless the pin moved.
    func ownPinDrag<Host: PinDragHost>(id: String, stored: Coordinate, host: Host, proxy: MapProxy, isEnabled: Bool,
                                       onDrop: ((PinDrop) -> Void)? = nil) -> some View {
        modifier(OwnPinDrag(id: id, stored: stored, host: host, proxy: proxy, isEnabled: isEnabled, onDrop: onDrop))
    }
}

struct OwnPinDrag<Host: PinDragHost>: ViewModifier {
    let id: String
    let stored: Coordinate
    let host: Host
    let proxy: MapProxy
    let isEnabled: Bool
    var onDrop: ((PinDrop) -> Void)?

    /// Where the pointer is relative to the tip; nil until the first drag value after the pickup.
    @State private var grab: CGSize?
    @State private var tipBefore: CGPoint?
    #if os(iOS)
    /// True while a press-and-hold drag gesture is in flight; its reset (end or cancel) puts a stray drag back.
    @GestureState private var holding = false
    #endif

    private var lifted: Bool { host.dragging?.id == id }

    func body(content: Content) -> some View {
        let base = content.modifier(LiftedPin(isLifted: lifted))
        #if os(macOS)
        base
            .pointerStyle(isEnabled ? (lifted ? .grabActive : .grabIdle) : nil)
            .gesture(pointerDrag, isEnabled: isEnabled)
            .help(isEnabled ? String(localized: "Drag to move your spot", comment: "Tooltip") : "")
        #else
        base
            .sensoryFeedback(.impact(weight: .light), trigger: lifted) { _, now in now }
            // Press and hold, then drag: a plain swipe across a pin still pans the map, and a tap still selects it.
            .highPriorityGesture(holdDrag, isEnabled: isEnabled)
            .onChange(of: holding) { _, now in
                // A drag that was interrupted (a call, the system gesture) never reaches `onEnded`: the pin goes back.
                if !now, host.dragging?.id == id { host.endDrag(commit: false) }
            }
        #endif
    }

    // MARK: Shared

    private func begin() -> Bool {
        guard host.beginDrag(id) else { return false }
        grab = nil
        tipBefore = proxy.convert(clCoordinate(stored), to: .global)
        MoveSpotTip.didMove()
        return true
    }

    /// Puts the dragged pin's tip where the pointer is, keeping the grab offset from the first touch.
    private func carry(to location: CGPoint, start: CGPoint) {
        if grab == nil { grab = PinDrag.grab(pointer: start, tip: tipBefore ?? start) }
        let point = PinDrag.tipPoint(pointer: location, grab: grab ?? .zero)
        if let c = proxy.convert(point, from: .global) {
            host.drag(to: Coordinate(latitude: c.latitude, longitude: c.longitude))
        }
    }

    /// The drop. Held without moving: nothing to save (and no empty undo step).
    private func finish(at location: CGPoint, start: CGPoint) {
        let drop = PinDrag.tipPoint(pointer: location, grab: grab ?? .zero)
        let expected = proxy.convert(drop, from: .global).map { Coordinate(latitude: $0.latitude, longitude: $0.longitude) }
        let delta = CGSize(width: location.x - start.x, height: location.y - start.y)
        let moved = host.dragging.map { $0.coordinate != stored } ?? false
        let before = tipBefore
        host.endDrag(commit: moved)
        grab = nil
        tipBefore = nil
        if moved { onDrop?(PinDrop(id: id, expected: expected, delta: delta, tipBefore: before)) }
    }

    private func clCoordinate(_ c: Coordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)
    }

    // MARK: Mac

    #if os(macOS)
    /// The pointer drags the pin straight away. Window space on both sides (the map's own space starts inside its padding).
    private var pointerDrag: some Gesture {
        DragGesture(minimumDistance: PinDrag.pointerMinimumDistance, coordinateSpace: .global)
            .onChanged { value in
                if host.dragging == nil { guard begin() else { return } }
                carry(to: value.location, start: value.startLocation)
            }
            .onEnded { value in
                guard host.dragging != nil else { return }
                finish(at: value.location, start: value.startLocation)
            }
    }
    #endif

    // MARK: iPhone and iPad

    #if os(iOS)
    private var holdDrag: some Gesture {
        LongPressGesture(minimumDuration: PinDrag.holdSeconds)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .updating($holding) { _, state, _ in state = true }
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if host.dragging == nil { guard begin() else { return } }
                if let drag { carry(to: drag.location, start: drag.startLocation) }
            }
            .onEnded { value in
                // The last touch position counts even if no change event carried it.
                guard host.dragging != nil else { return }
                if case .second(true, let drag?) = value {
                    carry(to: drag.location, start: drag.startLocation)
                    finish(at: drag.location, start: drag.startLocation)
                } else {
                    host.endDrag(commit: false)
                    grab = nil
                    tipBefore = nil
                }
            }
    }
    #endif
}

/// Holds a view's `OwnPinDragModel` (made on first use: it needs the app model from the environment). Not state: nothing
/// redraws when it is made.
@MainActor
final class OwnPinDragHolder {
    private var made: OwnPinDragModel?

    func model(for app: AppModel) -> OwnPinDragModel {
        if let made { return made }
        let model = OwnPinDragModel(app: app)
        made = model
        return model
    }
}
