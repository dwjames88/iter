import Foundation
import IterModel
import IterSources

/// The honest slot for night-sky brightness: no commercial-safe source exists, so every call throws `.noSource`
/// (which maps to `NoDataReason.notProvidedBySource`).
public struct NoSkyBrightnessProvider: SkyBrightnessProvider {
    public let descriptor: SourceDescriptor

    public init(descriptor: SourceDescriptor = SourceCatalogue.noSkyBrightness) { self.descriptor = descriptor }

    public func skyBrightness(at coordinate: Coordinate) async throws -> Sourced<SkyBrightness> {
        throw SourceError.noSource
    }
}

/// The honest slot for seeing and transparency: no commercial-safe source exists, so every call throws `.noSource`.
public struct NoSeeingProvider: SeeingProvider {
    public let descriptor: SourceDescriptor

    public init(descriptor: SourceDescriptor = SourceCatalogue.noSeeing) { self.descriptor = descriptor }

    public func seeing(at coordinate: Coordinate, span: TimeSpan) async throws -> Sourced<[SeeingEstimate]> {
        throw SourceError.noSource
    }
}
