import Foundation
import IterModel
import IterSources

/// NOAA NESDIS Hazard Mapping System smoke polygons for a UTC day, read from the daily KML.
///
/// A day whose file is not on the server yet (HTTP 404) is `.notPublished`. A point outside North America throws
/// `.outsideCoverage` before any request. The KML is a few KB to about 1 MB; callers cache it per UTC day.
public struct HMSSmokeProvider: SmokeAnalysisProvider {
    public let descriptor: SourceDescriptor
    private let http: any HTTPClient
    private let clock: any SourceClock

    public init(http: any HTTPClient, clock: any SourceClock = SystemSourceClock(),
                descriptor: SourceDescriptor = SourceCatalogue.hmsSmoke) {
        self.http = http
        self.clock = clock
        self.descriptor = descriptor
    }

    public func smoke(at coordinate: Coordinate, on date: Date) async throws -> Sourced<SmokeAnalysis> {
        guard coordinate.latitude.isFinite, coordinate.longitude.isFinite else {
            throw SourceError.invalidRequest("coordinate is not finite")
        }
        guard descriptor.coverage.contains(coordinate) else { throw SourceError.outsideCoverage }
        let day = HMSMapping.utcDay(of: date)
        let url = HMSMapping.fileURL(forDay: day)
        let body: Data
        do { body = try await http.send(.get(url, from: descriptor)).body } catch {
            let e = SourceError.wrap(error)
            if case .http(let status, _) = e, status == 404 {
                throw SourceError.notPublished("HMS smoke analysis for \(url.lastPathComponent)")
            }
            throw e
        }
        let placemarks = try HMSMapping.placemarks(from: body)
        let analysis = HMSMapping.analysis(of: placemarks, at: coordinate, day: day)
        let provenance = descriptor.provenance(
            fetchedAt: clock.now, model: "HMS analyst smoke polygons", issuedAt: day,
            validFor: TimeSpan(start: day, end: day.addingTimeInterval(86_400)), url: url)
        return Sourced(value: analysis, provenance: provenance)
    }
}
