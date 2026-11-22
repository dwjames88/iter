import Foundation

/// Confidence: a continuous value, then a level.
///
/// Start from lead time (window middle minus the model run, else the fetch): up to 36 h 2, up to 72 h 1, else 0.
/// Each missing primary input costs 1, each missing secondary input 0.2, a stale forecast 1, sources that disagree 1.
/// Beyond the forecast (persistence) it is always low. Level: 1.5 or more high, 0.5 or more medium, else low.
enum ConfidenceModel {
    struct Result: Equatable {
        /// 0...2 after clamping.
        var value: Double
        var level: Confidence
        /// `value / 2`, 0...1.
        var normalised: Double
        var causes: [ConfidenceCause]
    }

    static let primaryPenalty = 1.0
    static let secondaryPenalty = 0.2
    static let stalePenalty = 1.0
    static let spreadPenalty = 1.0
    /// Total cloud from two sources may differ by this much before confidence drops.
    static let spreadLimit = 0.30
    static let epsilon = 1e-9

    static func level(forValue value: Double) -> Confidence {
        if value >= 1.5 - epsilon { return .high }
        if value >= 0.5 - epsilon { return .medium }
        return .low
    }

    static func evaluate(leadHours: Double, missingPrimary: [SkyInput] = [], missingSecondary: [SkyInput] = [],
                         staleAge: TimeInterval? = nil, sourceSpread: Bool = false, persisted: Bool = false) -> Result {
        var value: Double = leadHours <= 36 ? 2 : (leadHours <= 72 ? 1 : 0)
        var causes: [ConfidenceCause] = []
        if leadHours > 36 { causes.append(.leadTime(hours: leadHours)) }
        for input in missingPrimary {
            value -= primaryPenalty
            causes.append(.missingPrimary(input))
        }
        for input in missingSecondary {
            value -= secondaryPenalty
            causes.append(.missingSecondary(input))
        }
        if let staleAge {
            value -= stalePenalty
            causes.append(.stale(age: staleAge))
        }
        if sourceSpread {
            value -= spreadPenalty
            causes.append(.sourceSpread)
        }
        if persisted {
            value = min(value, 0.49)
            causes.append(.persistence)
        }
        value = min(2, max(0, value))
        return Result(value: value, level: level(forValue: value), normalised: min(1, max(0, value / 2)), causes: causes)
    }

    /// Plausible spread of the score by level (0 / 8 / 15 points), clamped to 0...100.
    static func range(value: Int, confidence: Confidence) -> ClosedRange<Int> {
        let spread: Int
        switch confidence {
        case .high: spread = 0
        case .medium: spread = 8
        case .low: spread = 15
        }
        return max(0, value - spread)...min(100, value + spread)
    }
}
