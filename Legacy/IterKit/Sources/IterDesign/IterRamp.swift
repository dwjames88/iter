import IterCore

/// The Light Index colour ramp, as plain numbers. The fill is a continuous function of the score: linear interpolation
/// in sRGB between the `light/ramp/*` stops (0, 25, 50, 75, 100) of the appearance. The text on it is ink below the
/// appearance's switch score and the inverse colour from it up. Pure, so tests can check every integer score.
public enum IterRamp {
    public static let stopScores = [0, 25, 50, 75, 100]

    public static func clamp(_ score: Int) -> Int { min(max(score, 0), 100) }

    /// The middle score of a band (Poor 20, Fair 49, Good 66, Great 81, Epic 94).
    public static func midpoint(_ band: LightBand) -> Int {
        let r = band.scoreRange
        return (r.lowerBound + r.upperBound) / 2
    }

    public static func stop(_ score: Int, dark: Bool) -> RGB {
        let t = TokenValues.color("light/ramp/\(score)")
        return dark ? t.darkRGB : t.lightRGB
    }

    public static func fill(score: Int, dark: Bool) -> RGB {
        let s = clamp(score)
        let i = min(s / 25, 3)
        let (a, b) = (stop(stopScores[i], dark: dark), stop(stopScores[i + 1], dark: dark))
        let t = Double(s - stopScores[i]) / 25
        func mix(_ x: Int, _ y: Int) -> Int { Int((Double(x) + (Double(y) - Double(x)) * t).rounded()) }
        return RGB(red: mix(a.red, b.red), green: mix(a.green, b.green), blue: mix(a.blue, b.blue))
    }

    public static func switchScore(dark: Bool) -> Int {
        Int(TokenValues.dimension(dark ? "light/rampText/switchScore/dark" : "light/rampText/switchScore/light"))
    }

    public static func text(score: Int, dark: Bool) -> RGB {
        let token = TokenValues.color(clamp(score) >= switchScore(dark: dark) ? "light/rampText/inverse" : "light/rampText/ink")
        return dark ? token.darkRGB : token.lightRGB
    }

    public static var hairlineBelowScore: Double { TokenValues.dimension("event/hairlineBelowScore") }
}
