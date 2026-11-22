import Foundation
import Observation
import IterCore
import IterServices

/// Where the user is, for Explore's "Near you" section. Never blocks: shows the last known fix at once, then refreshes.
@MainActor
@Observable
public final class UserLocationModel {
    public private(set) var authorization: LocationAuthorization
    public private(set) var coordinate: Coordinate?
    public private(set) var isLocating = false
    /// True when the location comes from `-IterLocation`, not the device.
    public var isSimulated: Bool

    public var radiusMiles: Int {
        didSet { defaults.set(radiusMiles, forKey: Self.radiusKey) }
    }

    public static let radiusChoices = [100, 200, 300, 500]
    public static let defaultRadiusMiles = 300
    public static let radiusKey = "IterNearbyRadiusMiles"
    public static let lastFixKey = "IterLastLocationFix"
    public static let launchArgumentKey = "IterLocation"
    /// System Settings > Privacy & Security > Location Services.
    public static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!

    @ObservationIgnored private let provider: any UserLocationProviding
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let clock: () -> Date

    public init(provider: any UserLocationProviding = InertLocationProvider(),
                isSimulated: Bool = false,
                defaults: UserDefaults = .standard,
                clock: @escaping () -> Date = { Date() }) {
        self.provider = provider
        self.isSimulated = isSimulated
        self.defaults = defaults
        self.clock = clock
        let stored = defaults.integer(forKey: Self.radiusKey)
        self.radiusMiles = stored > 0 ? stored : Self.defaultRadiusMiles
        self.authorization = provider.authorization
        // A simulated fix is known up front, so the first screen is built with it (no late regroup, no late refit).
        if isSimulated, let fixed = provider as? FixedLocationProvider { self.coordinate = fixed.coordinate }
        provider.onAuthorizationChange = { [weak self] status in self?.authorizationChanged(to: status) }
    }

    /// Parses "36.6,-121.9"; nil when malformed or out of range.
    public static func parseLaunchLocation(_ text: String?) -> Coordinate? {
        guard let text else { return nil }
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let lat = Double(parts[0]), let lon = Double(parts[1]),
              lat.isFinite, lon.isFinite, (-90...90).contains(lat), (-180...180).contains(lon) else { return nil }
        return Coordinate(latitude: lat, longitude: lon)
    }

    /// `-IterLocation lat,lon` gives a simulated fixed location (this is the stub); a render copy without one never touches
    /// CoreLocation (no dialog); otherwise CoreLocation.
    public static func live() -> UserLocationModel {
        let (provider, simulated) = provider(launchLocation: UserDefaults.standard.string(forKey: launchArgumentKey),
                                             isRenderCopy: RenderCopy.isCurrent)
        return UserLocationModel(provider: provider, isSimulated: simulated)
    }

    static func provider(launchLocation: String?, isRenderCopy: Bool) -> (any UserLocationProviding, simulated: Bool) {
        if let fixed = parseLaunchLocation(launchLocation) { return (FixedLocationProvider(fixed), true) }
        if isRenderCopy { return (InertLocationProvider(), false) }
        return (CoreLocationProvider(), false)
    }

    /// Which strip Explore shows above the list.
    public enum BannerState: Sendable, Equatable { case none, openSettings, finding, unavailable }

    public static func bannerState(authorization: LocationAuthorization, isLocating: Bool, hasFix: Bool) -> BannerState {
        switch authorization {
        case .notDetermined: .none   // the system dialog is on screen
        case .denied, .restricted: .openSettings
        case .authorized: hasFix ? .none : (isLocating ? .finding : .unavailable)
        }
    }

    public var bannerState: BannerState {
        Self.bannerState(authorization: authorization, isLocating: isLocating, hasFix: coordinate != nil)
    }

    @ObservationIgnored private var requestedAtLaunch = false

    /// Called once the main window is up: asks for location (the system dialog the first time), then fetches a fix if allowed.
    /// Authorization is requested at most once per process, however often this is called.
    public func requestAtLaunch() {
        guard !requestedAtLaunch else { return }
        requestedAtLaunch = true
        start()
    }

    /// Call when Explore first appears. Idempotent.
    public func start() {
        authorization = provider.authorization
        if authorization == .notDetermined { provider.requestAuthorization() }
        refreshIfAuthorized()
    }

    /// Fetches a fresh fix now (e.g. a refresh button).
    public func refresh() { refreshIfAuthorized() }

    /// MapKit's own user-location indicator (and its button) belong on a map: real, permitted location only.
    public var showsSystemIndicator: Bool { authorization == .authorized && !isSimulated }

    /// Where the app draws its own dot: only for a simulated, permitted location (MapKit would show the real one).
    public var simulatedIndicatorCoordinate: Coordinate? { authorization == .authorized && isSimulated ? coordinate : nil }

    public func distanceMiles(to other: Coordinate) -> Double? {
        coordinate.map { $0.distance(to: other) / 1609.344 }
    }

    // MARK: Private

    private func authorizationChanged(to status: LocationAuthorization) {
        authorization = status
        refreshIfAuthorized()
    }

    private func refreshIfAuthorized() {
        guard authorization == .authorized else {
            if authorization == .denied || authorization == .restricted { coordinate = nil }
            return
        }
        if coordinate == nil, let cached = cachedFix() { coordinate = cached }
        guard !isLocating else { return }
        isLocating = true
        Task { [weak self] in
            guard let self else { return }
            let fix = await provider.requestFix()
            isLocating = false
            guard authorization == .authorized, let fix else { return }
            coordinate = fix
            storeFix(fix)
        }
    }

    private func cachedFix() -> Coordinate? {
        guard let dict = defaults.dictionary(forKey: Self.lastFixKey),
              let lat = dict["lat"] as? Double, let lon = dict["lon"] as? Double else { return nil }
        return Coordinate(latitude: lat, longitude: lon)
    }

    private func storeFix(_ fix: Coordinate) {
        guard !isSimulated else { return }
        defaults.set(["lat": fix.latitude, "lon": fix.longitude, "timestamp": clock().timeIntervalSince1970], forKey: Self.lastFixKey)
    }
}
