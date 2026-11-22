import Foundation
import IterModel
import IterSources

/// The built-in sample weather and sky source: deterministic, offline, and labelled "Sample data" everywhere it shows
/// (every datum's provenance names it, so a source line reads "Sample data", never a real agency). One value serves the
/// forecast, nearby station report, alerts, aurora, smoke analysis and terrain protocols, so a `ConditionsService` built
/// over it produces a complete report for any place without a network.
///
/// The numbers are a smooth function of the coordinate and the time, so different places and days score differently and a
/// place scores the same every time it is asked.
public struct SampleConditions: ForecastProvider, ObservationProvider, StationReportProvider, AlertProvider, AuroraProvider,
                                SmokeAnalysisProvider, TerrainProvider {
    public static let sourceID: SourceID = "iter.sample"

    public static let descriptor = SourceDescriptor(
        id: sourceID, name: "Sample data", operatorName: "Built into Iter; not real weather", tier: .device,
        origin: SourceOrigin(tier: .device, producer: "Iter sample data", computedOnDevice: true),
        kinds: [.forecast, .observation, .alerts, .aurora, .smoke, .elevation, .horizon],
        coverage: .global,
        policy: RequestPolicy(spacing: .zero, maxConcurrent: 16, timeout: .seconds(5), maxRetries: 0, conditional: false),
        cacheTTL: .seconds(3600), licence: LicenceTag(key: licenceKey, mayStore: true),
        ranks: [.forecast: 1, .observation: 1, .alerts: 1, .aurora: 1, .smoke: 1, .elevation: 1, .horizon: 1])

    /// The licence key the credits screen maps to "Built-in sample data".
    public static let licenceKey = "iter.sample"
    public static let attributionText = "Built-in sample data for previews and screenshots. These numbers are generated on this device and are not real weather."

    public var descriptor: SourceDescriptor { Self.descriptor }
    /// The clock the "latest observation" age is measured against.
    public var now: @Sendable () -> Date
    /// Alerts in force everywhere (none by default).
    public var alerts: [WeatherAlert]

    public init(now: @escaping @Sendable () -> Date = { Date() }, alerts: [WeatherAlert] = []) {
        self.now = now
        self.alerts = alerts
    }

    // MARK: The function

    private static func clamp(_ x: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double { min(hi, max(lo, x)) }

    /// One hour of sample conditions. Pure.
    public static func hour(at c: Coordinate, time: Date) -> HourlyConditions {
        let hours = time.timeIntervalSince1970 / 3600
        let day = (time.timeIntervalSince1970 / 86_400).rounded(.down)
        // A slow weather pattern per place and day, then faster drift within the day.
        let pattern = 0.5 + 0.5 * sin(c.latitude * 0.93 + c.longitude * 0.57 + day * 1.71)
        let drift = sin(hours / 6.5 + c.longitude * 0.2)
        let low = clamp(pattern * 0.6 + 0.12 * drift - 0.08)
        let mid = clamp((1 - pattern) * 0.45 + 0.1 * sin(hours / 4.3 + c.latitude) )
        let high = clamp(0.25 + 0.3 * sin(day * 0.9 + c.latitude * 0.4) + 0.1 * drift)
        let total = 1 - (1 - low) * (1 - mid) * (1 - high)
        let chance = clamp(low * 0.7 + mid * 0.2 - 0.18)
        let mm = chance > 0.35 ? (chance - 0.35) * 4 : 0
        let localHour = (hours + c.longitude / 15).truncatingRemainder(dividingBy: 24)
        let temp = 14 - abs(c.latitude) * 0.25 + 8 * sin((localHour - 9) / 24 * 2 * .pi)
        let dew = temp - 4 - 7 * (1 - total)
        return HourlyConditions(
            time: time, cloudTotal: total, cloudLow: low, cloudMid: mid, cloudHigh: high, cloudBaseM: 900 + 1800 * (1 - low),
            precipChance: chance, precipMm: mm, visibilityKm: clamp(24 - 18 * chance - 5 * low, 2, 24), tempC: temp, dewpointC: dew,
            rhPercent: clamp(100 * exp((17.625 * dew) / (243.04 + dew) - (17.625 * temp) / (243.04 + temp)), 5, 100),
            windMs: 2 + 5 * (0.5 + 0.5 * sin(hours / 9 + c.latitude)), gustMs: 5 + 6 * (0.5 + 0.5 * sin(hours / 9 + c.latitude)),
            windDirDeg: ((hours * 7 + c.longitude * 3).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360),
            aod550: 0.08 + 0.03 * pattern, smokeUgm3: 2 + 2 * pattern, pm25: 4 + 3 * pattern)
    }

    private func provenance(distanceKm: Double? = nil, issuedAt: Date? = nil) -> Provenance {
        Self.descriptor.provenance(fetchedAt: now(), model: "Sample", issuedAt: issuedAt, distanceKm: distanceKm)
    }

    // MARK: Forecast

    public func forecast(at coordinate: Coordinate, span: TimeSpan) async throws -> Sourced<HourlySeries> {
        let first = (span.start.timeIntervalSince1970 / 3600).rounded(.down) * 3600
        var rows: [HourlyConditions] = []
        var t = first
        while t <= span.end.timeIntervalSince1970 + 3600 && rows.count < 24 * 11 {
            rows.append(Self.hour(at: coordinate, time: Date(timeIntervalSince1970: t)))
            t += 3600
        }
        let fields = Dictionary(uniqueKeysWithValues: HourlyField.allCases.map { ($0, Self.sourceID) })
        return Sourced(value: HourlySeries(hours: rows, fieldSources: fields), provenance: provenance(issuedAt: first.asDate))
    }

    // MARK: Station reports

    /// The nearest sample "airfield": a point 14 to 26 km from the place, reporting 25 minutes ago.
    private func station(near c: Coordinate) -> StationReport {
        let bearing = (c.latitude * 37 + c.longitude * 19).truncatingRemainder(dividingBy: 360) * .pi / 180
        let km = 14 + 12 * (0.5 + 0.5 * sin(c.latitude * 5 + c.longitude * 3))
        let dLat = km / 111 * cos(bearing)
        let dLon = km / (111 * max(0.2, cos(c.latitude * .pi / 180))) * sin(bearing)
        let at = Coordinate(latitude: c.latitude + dLat, longitude: c.longitude + dLon)
        let observed = now().addingTimeInterval(-25 * 60)
        let h = Self.hour(at: at, time: observed)
        let cover: CloudLayer.Cover = switch h.cloudTotal ?? 0 {
        case ..<0.1: .clr
        case ..<0.35: .few
        case ..<0.6: .sct
        case ..<0.9: .bkn
        default: .ovc
        }
        let layers = cover == .clr ? [] : [CloudLayer(cover: cover, baseM: h.cloudBaseM)]
        return StationReport(
            stationID: "SMPL", stationName: "Sample airfield (not a real station)", coordinate: at, elevationM: 1200, distanceKm: km,
            isMilitary: false, observedAt: observed, rawMETAR: "SMPL SAMPLE DATA", observation: WeatherObservation(time: observed, stationName: "Sample airfield", conditions: h),
            cloudLayers: layers, weather: [], flightCategory: (h.visibilityKm ?? 10) > 8 ? "VFR" : "MVFR")
    }

    public func reports(near coordinate: Coordinate, within km: Double, limit: Int) async throws -> [Sourced<StationReport>] {
        let s = station(near: coordinate)
        guard s.distanceKm <= km, limit > 0 else { return [] }
        return [Sourced(value: s, provenance: provenance(distanceKm: s.distanceKm, issuedAt: s.observedAt))]
    }

    public func latest(near coordinate: Coordinate, within km: Double, maxAge: Duration) async throws -> [Sourced<WeatherObservation>] {
        try await reports(near: coordinate, within: km, limit: 1).map { $0.map(\.observation) }
    }

    // MARK: Alerts, aurora, smoke

    public func alerts(at coordinate: Coordinate) async throws -> Sourced<[WeatherAlert]> {
        Sourced(value: alerts, provenance: provenance())
    }

    public func aurora(at coordinate: Coordinate) async throws -> Sourced<AuroraReading> {
        let t = now()
        let percent = Self.clamp((abs(coordinate.latitude) - 45) * 1.6, 1, 60)
        return Sourced(value: AuroraReading(probabilityPercent: percent, observedAt: t, forecastFor: t.addingTimeInterval(3600), kpNow: 2, kpObservedAt: t),
                       provenance: provenance())
    }

    public func kpForecast() async throws -> Sourced<[KpPeriod]> {
        let start = (now().timeIntervalSince1970 / 10_800).rounded(.down) * 10_800
        let periods = (0..<8).map { KpPeriod(start: Date(timeIntervalSince1970: start + Double($0) * 10_800), kp: 2 + Double($0 % 3) * 0.33, kind: $0 == 0 ? .estimated : .predicted) }
        return Sourced(value: periods, provenance: provenance())
    }

    public func smoke(at coordinate: Coordinate, on date: Date) async throws -> Sourced<SmokeAnalysis> {
        let day = (date.timeIntervalSince1970 / 86_400).rounded(.down) * 86_400
        return Sourced(value: SmokeAnalysis(density: .none, day: Date(timeIntervalSince1970: day), polygonCount: 0), provenance: provenance())
    }

    // MARK: Terrain

    public func elevation(at c: Coordinate) async throws -> Sourced<Double> {
        Sourced(value: 1200 + 600 * sin(c.latitude * 2.1 + c.longitude * 1.3), provenance: provenance())
    }

    public func horizon(at c: Coordinate, azimuthStep: Double) async throws -> Sourced<HorizonProfile> {
        let step = azimuthStep > 0 ? azimuthStep : HorizonProfile.standardStepDegrees
        let count = Int((360 / step).rounded())
        let values = (0..<count).map { i -> Double in
            let az = Double(i) * step * .pi / 180
            return max(0, 2.5 + 2.5 * sin(az * 2 + c.latitude) + 1.5 * sin(az * 5 + c.longitude))
        }
        return Sourced(value: HorizonProfile(azimuthStepDegrees: step, elevationsDegrees: values), provenance: provenance())
    }
}

private extension Double {
    var asDate: Date { Date(timeIntervalSince1970: self) }
}
