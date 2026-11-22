import Foundation
import IterModel
import IterSources

/// The World Magnetic Model 2025 computed on device (`WorldMagneticModel` in Formats).
///
/// Valid 2025.0 to 2030.0; a date outside that range throws `.outsideCoverage` (the model does not extrapolate).
/// `nearMagneticPole` is true when the horizontal intensity is below 6000 nT (NGA's blackout-zone threshold; the compass
/// is unreliable there). No network, no clock: the date is an argument.
public struct WorldMagneticModelProvider: MagneticModelProvider {
    public let descriptor: SourceDescriptor
    private let clock: any SourceClock

    public init(clock: any SourceClock = SystemSourceClock(), descriptor: SourceDescriptor = SourceCatalogue.worldMagneticModel) {
        self.clock = clock
        self.descriptor = descriptor
    }

    /// Horizontal intensity below which the field is treated as near a magnetic pole, nanotesla.
    public static let poleThresholdNT = 6000.0

    /// `elevationM` is metres above the WGS84 ellipsoid (mean sea level differs by up to about 100 m; the effect on
    /// declination is far below a hundredth of a degree).
    public func field(at coordinate: Coordinate, elevationM: Double, on date: Date) throws -> Sourced<IterSources.MagneticField> {
        let year = WorldMagneticModel.decimalYear(for: date)
        guard WorldMagneticModel.validRange.contains(year) else { throw SourceError.outsideCoverage }
        let f: MagneticField
        do {
            f = try WorldMagneticModel.evaluate(latitude: coordinate.latitude, longitude: coordinate.longitude,
                                                altitudeKm: elevationM / 1000, decimalYear: year)
        } catch WorldMagneticModelError.outsideValidity {
            throw SourceError.outsideCoverage
        } catch WorldMagneticModelError.invalidInput {
            throw SourceError.invalidRequest("latitude must be within -90...90 and all inputs finite")
        } catch {
            throw SourceError.wrap(error)
        }
        let value = IterSources.MagneticField(declinationDegrees: f.declination, inclinationDegrees: f.inclination,
                                              totalIntensityNT: f.total, date: date,
                                              nearMagneticPole: f.horizontal < Self.poleThresholdNT)
        let provenance = descriptor.provenance(
            fetchedAt: clock.now, model: "\(WorldMagneticModel.name) (epoch \(WorldMagneticModel.epoch))",
            issuedAt: date, url: descriptor.termsURL)
        return Sourced(value: value, provenance: provenance)
    }
}
