import Foundation
import IterModel
import IterSources

/// MGRS (NGA grid reference standard) computed on device, both ways (`MGRS` in Formats).
public struct MGRSProvider: GridReferenceProvider {
    public let descriptor: SourceDescriptor
    private let clock: any SourceClock

    public init(clock: any SourceClock = SystemSourceClock(), descriptor: SourceDescriptor = SourceCatalogue.mgrs) {
        self.clock = clock
        self.descriptor = descriptor
    }

    /// The reference truncated (not rounded) to `precision` digits per axis, 1...5, without spaces.
    public func mgrs(for coordinate: Coordinate, precision: Int) throws -> Sourced<String> {
        guard (1...5).contains(precision) else { throw SourceError.invalidRequest("precision must be 1...5") }
        let text: String
        do {
            text = try MGRS.string(latitude: coordinate.latitude, longitude: coordinate.longitude, precision: precision)
        } catch {
            throw Self.map(error)
        }
        return Sourced(value: text, provenance: descriptor.provenance(fetchedAt: clock.now, model: "MGRS \(precision * 2)-digit"))
    }

    /// The centre of the referenced cell. (GEOTRANS decodes to the south-west corner; the centre is half a cell away, 0.7 m
    /// for a 1 m reference, and unlike the corner it re-encodes to the same reference without floating-point edge cases.)
    public func coordinate(fromMGRS text: String) throws -> Coordinate {
        do {
            let location = try MGRS.decode(text)
            return Coordinate(latitude: location.centreLatitude, longitude: location.centreLongitude)
        } catch {
            throw Self.map(error)
        }
    }

    private static func map(_ error: any Error) -> SourceError {
        guard let e = error as? MGRSError else { return SourceError.wrap(error) }
        switch e {
        case .invalidReference(let why): return .invalidRequest("MGRS reference: \(why)")
        case .outsideUTMCoverage: return .outsideCoverage
        default: return .invalidRequest("MGRS: \(e)")
        }
    }
}
