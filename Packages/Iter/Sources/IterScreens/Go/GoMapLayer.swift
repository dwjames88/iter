import SwiftUI
import MapKit
import IterModel
import IterGoActivity
import IterUI

/// The map under the sheet: your position, the stops still to do as solid numbered plates, the route in the route colour.
/// Apple Maps geometry in the standard style; "Dark for Night Shooting" mutes it.
///
/// **Camera.** It frames you and the stop you are heading to, plus the rest of today's stops while they fit at a legible zoom
/// (`GoMapCamera`), inside the part of the screen the sheet and the Dynamic Island leave uncovered. Whole-trip framing is gone:
/// it piled the numbered pins on top of each other. The camera follows while you do nothing; the moment you pan or zoom it
/// stops, and a recentre button brings it back.
///
/// **Pins** that would overlap at the current zoom merge into one badge ("6–8", `GoMapPins`), so no two plates ever stack.
public struct GoMapLayer: View {
    let snapshot: GoSnapshot
    let routePath: [Coordinate]
    /// How much of the bottom the sheet covers right now (its detent's height). Zero on the Mac, where the sheet is a column.
    let bottomInset: Double

    @AppStorage(GoNightView.key) private var night = false
    @State private var position: MapCameraPosition = .automatic
    @State private var size: CGSize = .zero
    @State private var topInset: Double = 0
    @State private var following = true
    @State private var mapPointsPerPoint: Double = 0

    public init(snapshot: GoSnapshot, routePath: [Coordinate], bottomInset: Double = 0) {
        self.snapshot = snapshot
        self.routePath = routePath
        self.bottomInset = bottomInset
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                map
                    .ignoresSafeArea()
                    .onGeometryChange(for: CGSize.self, of: { $0.size }) { size = $0 }
                if !following { recentreButton }
            }
            .onChange(of: proxy.safeAreaInsets.top, initial: true) { _, top in topInset = top }
        }
        // The camera follows while `following`; one key says when it has to move (a nudge of you under ~200 m does not).
        .task(id: FitKey(snapshot: snapshot, size: size, top: topInset, bottom: bottomInset)) {
            if following { fit(animated: hasFitted) }
        }
    }

    @State private var hasFitted = false

    private var map: some View {
        let stops = Self.stops(snapshot)
        let nextID = (snapshot.next ?? stops.first)?.id
        let groups = GoMapPins.groups(stops: stops, nextID: nextID, mapPointsPerPoint: mapPointsPerPoint)
        return Map(position: $position) {
            // Your position comes from the app's own location (the engine's fix), so it shows with a fixed or scripted location
            // too; MapKit's dot is only the fallback before the first fix.
            if let here = snapshot.here {
                Annotation("You", coordinate: Self.clCoordinate(here), anchor: .center) { GoMapUserDot() }
                    .annotationTitles(.hidden)
            } else {
                UserAnnotation()
            }
            overlays
            if routePath.count > 1 {
                MapPolyline(coordinates: routePath.map(Self.clCoordinate))
                    .stroke(IterColor.route, lineWidth: IterStroke.route)
            }
            ForEach(groups) { group in
                Annotation(group.accessibilityLabel, coordinate: Self.clCoordinate(group.coordinate), anchor: .center) {
                    if group.isCluster {
                        GoMapClusterBadge(group: group)
                    } else {
                        GoMapPlate(number: group.stops[0].number, isNext: group.containsNext)
                    }
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(emphasis: night ? .muted : .automatic))
        .onMapCameraChange(frequency: .onEnd) { context in
            if size.width > 0 { mapPointsPerPoint = context.rect.size.width / size.width }
        }
        // Moving or zooming the map by hand ends the following until the recentre button is pressed.
        .onChange(of: position.positionedByUser) { _, byUser in
            if byUser { following = false }
        }
    }

    /// Where a weather overlay (the cloud imagery layer) goes: under the route and the pins, over the base map. Empty for now.
    @MapContentBuilder private var overlays: some MapContent {
    }

    private var recentreButton: some View {
        Button {
            following = true
            fit(animated: true)
        } label: {
            Image(systemName: "location.fill")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel("Recentre")
        .padding(.trailing, 12)
        .padding(.bottom, bottomInset + 12)
    }

    // MARK: Camera

    private var viewport: GoMapViewport {
        GoMapViewport(size: size, top: topInset, leading: 0, bottom: bottomInset, trailing: 0)
    }

    private func fit(animated: Bool) {
        guard size.width > 0 else { return }
        let focus = snapshot.next ?? snapshot.current
        let today = Self.stops(snapshot).filter { $0.dayIndex == focus?.dayIndex }.map(\.coordinate)
        guard let framing = GoMapCamera.frame(user: snapshot.here, next: focus?.coordinate, today: today, viewport: viewport) else { return }
        mapPointsPerPoint = framing.mapPointsPerPoint
        hasFitted = true
        if animated {
            withAnimation(.smooth(duration: 0.6)) { position = .rect(framing.rect) }
        } else {
            position = .rect(framing.rect)
        }
    }

    /// What moves the camera. You are rounded to about 200 m so a moving dot does not re-aim it on every fix.
    struct FitKey: Equatable {
        var here: [Int]
        var stops: [UUID]
        var size: CGSize
        var top: Double
        var bottom: Double

        init(snapshot: GoSnapshot, size: CGSize, top: Double, bottom: Double) {
            here = snapshot.here.map { [Int(($0.latitude * 500).rounded()), Int(($0.longitude * 500).rounded())] } ?? []
            stops = [snapshot.next?.id, snapshot.current?.id].compactMap { $0 } + GoMapLayer.stops(snapshot).map(\.id)
            self.size = size
            self.top = top
            self.bottom = bottom
        }
    }

    // MARK: Pure helpers

    /// The stops to pin: the remaining schedule, else the next stop, else the one you are at.
    static func stops(_ snapshot: GoSnapshot) -> [GoStopInfo] {
        if let schedule = snapshot.schedule, !schedule.isEmpty { return schedule.map(\.stop) }
        if let next = snapshot.next { return [next] }
        return snapshot.current.map { [$0] } ?? []
    }

    static func clCoordinate(_ c: Coordinate) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)
    }
}

/// Where you are: the system's blue location dot, solid with a white ring (map markers are never material).
struct GoMapUserDot: View {
    var body: some View {
        Circle()
            .fill(Color.blue)
            .frame(width: 14, height: 14)
            .overlay { Circle().strokeBorder(.white, lineWidth: 3) }
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
            .accessibilityLabel("Your location")
    }
}

/// Stops too close to tell apart at this zoom, as one solid badge. Coral when the stop you are heading to is inside it.
struct GoMapClusterBadge: View {
    let group: GoMapPinGroup

    var body: some View {
        Text(group.label)
            .font(IterFont.captionStrong)
            .monospacedDigit()
            .foregroundStyle(IterColor.onAccent)
            .padding(.horizontal, IterSpace.sm)
            .frame(minWidth: IterSize.mapPin, minHeight: IterSize.mapPin)
            .background(group.containsNext ? IterColor.mapPin : IterColor.mapPinInactive, in: Capsule())
            .overlay { Capsule().strokeBorder(IterColor.backgroundContent, lineWidth: IterStroke.regular) }
            .accessibilityLabel(group.accessibilityLabel)
    }
}

/// A stop's pin: a solid numbered plate (map pins are never material). The stop you are heading to is larger and coral.
struct GoMapPlate: View {
    let number: Int
    let isNext: Bool

    var body: some View {
        Text(number, format: .number)
            .font(IterFont.headline)
            .monospacedDigit()
            .foregroundStyle(IterColor.onAccent)
            .frame(width: isNext ? IterSize.mapPinSelected : IterSize.mapPin, height: isNext ? IterSize.mapPinSelected : IterSize.mapPin)
            .background(isNext ? IterColor.mapPin : IterColor.mapPinInactive, in: Circle())
            .overlay { Circle().strokeBorder(IterColor.backgroundContent, lineWidth: IterStroke.regular) }
            .accessibilityLabel("Stop \(number)")
    }
}
