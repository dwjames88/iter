import Foundation
import IterModel
import IterSources

/// NOAA SWPC aurora: the OVATION nowcast probability at the nearest 1 degree cell, with the latest estimated Kp.
///
/// Cost: `ovation_aurora_latest.json` is about 0.9 MB and global. This provider always fetches it when asked; callers
/// decide whether a mid-latitude place is worth the download (aurora is rarely visible below about 40 degrees of
/// geomagnetic latitude) and cache the answer per UTC half hour (the feed updates about every 5 minutes with a
/// 30 to 90 minute forecast lead). The Kp request is small; if it fails, `kpNow` is nil and the aurora value still returns.
public struct SWPCAuroraProvider: AuroraProvider {
    public static let ovationURL = URL(string: "https://services.swpc.noaa.gov/json/ovation_aurora_latest.json")!
    public static let kpNowURL = URL(string: "https://services.swpc.noaa.gov/json/planetary_k_index_1m.json")!
    public static let kpForecastURL = URL(string: "https://services.swpc.noaa.gov/products/noaa-planetary-k-index-forecast.json")!
    public static let humanURL = URL(string: "https://www.swpc.noaa.gov/products/aurora-30-minute-forecast")

    public let descriptor: SourceDescriptor
    private let http: any HTTPClient
    private let clock: any SourceClock

    public init(http: any HTTPClient, clock: any SourceClock = SystemSourceClock(),
                descriptor: SourceDescriptor = SourceCatalogue.swpc) {
        self.http = http
        self.clock = clock
        self.descriptor = descriptor
    }

    public func aurora(at coordinate: Coordinate) async throws -> Sourced<AuroraReading> {
        guard coordinate.latitude.isFinite, coordinate.longitude.isFinite, abs(coordinate.latitude) <= 90 else {
            throw SourceError.invalidRequest("latitude must be within -90...90")
        }
        guard descriptor.coverage.contains(coordinate) else { throw SourceError.outsideCoverage }
        let body = try await fetch(Self.ovationURL)
        let grid = try SWPCMapping.ovation(from: body)
        guard let percent = grid.probability(at: coordinate) else {
            throw SourceError.decoding("OVATION grid has no cell for \(coordinate.cacheKey)")
        }
        var kp: SWPCMapping.KpNow?
        do { kp = try SWPCMapping.kpNow(from: try await fetch(Self.kpNowURL)) } catch let e as SourceError {
            if case .cancelled = e { throw e }
        }
        let reading = AuroraReading(probabilityPercent: percent, observedAt: grid.observedAt, forecastFor: grid.forecastFor,
                                    kpNow: kp?.kp, kpObservedAt: kp?.observedAt)
        let provenance = descriptor.provenance(
            fetchedAt: clock.now, model: "OVATION aurora nowcast, 1 degree grid", issuedAt: grid.observedAt,
            validFor: TimeSpan(start: grid.observedAt, end: grid.forecastFor), url: Self.humanURL)
        return Sourced(value: reading, provenance: provenance)
    }

    public func kpForecast() async throws -> Sourced<[KpPeriod]> {
        let periods = try SWPCMapping.kpForecast(from: try await fetch(Self.kpForecastURL))
        let provenance = descriptor.provenance(
            fetchedAt: clock.now, model: "NOAA planetary K-index forecast",
            issuedAt: periods.last(where: { $0.kind != .predicted })?.start,
            validFor: TimeSpan(start: periods[0].start, end: periods[periods.count - 1].start.addingTimeInterval(3 * 3600)),
            url: URL(string: "https://www.swpc.noaa.gov/products/planetary-k-index"))
        return Sourced(value: periods, provenance: provenance)
    }

    private func fetch(_ url: URL) async throws -> Data {
        do { return try await http.send(.get(url, from: descriptor)).body } catch { throw SourceError.wrap(error) }
    }
}
