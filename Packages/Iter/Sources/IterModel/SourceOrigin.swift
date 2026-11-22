import Foundation

/// Who produced a datum and who handed it to us, so the UI can label it honestly, e.g. "military-origin via NOAA".
/// `tier` is the producer's tier (a military airfield's METAR is `.military` even though NOAA serves it).
/// A source's descriptor carries the best origin it can supply; each datum's `Provenance.origin` carries the actual one
/// (a civil airport's METAR from the same feed is `.government`).
public struct SourceOrigin: Codable, Hashable, Sendable {
    public var tier: SourceTier
    /// The organisation that made the data, e.g. "US Navy" or "NGA and UK DGC".
    public var producer: String
    /// The organisation that distributes it when that is someone else, e.g. "NOAA Aviation Weather Center".
    public var distributor: String?
    /// True when the value is computed on this device from a published model or standard (WMM, MGRS).
    public var computedOnDevice: Bool

    public init(tier: SourceTier, producer: String, distributor: String? = nil, computedOnDevice: Bool = false) {
        self.tier = tier
        self.producer = producer
        self.distributor = distributor
        self.computedOnDevice = computedOnDevice
    }

    /// A short, honest label: "Military-origin via NOAA Aviation Weather Center", "Government (NOAA/NCEP)",
    /// "Military-origin standard, computed on device".
    public var label: String {
        let base: String
        switch tier {
        case .military: base = "Military-origin"
        case .government: base = "Government"
        case .openData: base = "Open data"
        case .userKey: base = "Your key"
        case .device: base = "On device"
        }
        if computedOnDevice { return tier == .device ? base : "\(base) standard, computed on device" }
        if let distributor, !distributor.isEmpty, distributor != producer { return "\(base) (\(producer)) via \(distributor)" }
        return "\(base) (\(producer))"
    }
}
