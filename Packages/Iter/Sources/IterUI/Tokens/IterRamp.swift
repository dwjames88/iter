import Foundation

/// The Light Index colour ramp, as plain numbers. The fill is a continuous function of the score (0 to 100): linear
/// interpolation in sRGB between the `light/ramp/*` stops (0, 25, 50, 75, 100) of the appearance. The text on it is ink
/// below the appearance's switch score and the inverse colour from it up. Pure, so tests can check any score.
public enum IterRamp {
    public static let stopScores = [0, 25, 50, 75, 100]

    public static func clamp(_ score: Int) -> Int { min(max(score, 0), 100) }
    public static func clamp(_ score: Double) -> Double { score.isNaN ? 0 : min(max(score, 0), 100) }

    /// The stop token's colour in the given appearance. `score` must be one of `stopScores`.
    public static func stop(_ score: Int, dark: Bool) -> RGB {
        let t = TokenValues.color("light/ramp/\(score)")
        return dark ? t.darkRGB : t.lightRGB
    }

    /// The ramp fill: scores outside 0...100 clamp, stops return exactly the stop colour, between stops the channels mix
    /// linearly (each rounded to the nearest 8-bit value).
    public static func fill(score: Double, dark: Bool) -> RGB {
        let s = clamp(score)
        let i = min(Int(s / 25), 3)
        let (a, b) = (stop(stopScores[i], dark: dark), stop(stopScores[i + 1], dark: dark))
        let t = (s - Double(stopScores[i])) / 25
        func mix(_ x: Int, _ y: Int) -> Int { Int((Double(x) + (Double(y) - Double(x)) * t).rounded()) }
        return RGB(red: mix(a.red, b.red), green: mix(a.green, b.green), blue: mix(a.blue, b.blue))
    }

    public static func fill(score: Int, dark: Bool) -> RGB { fill(score: Double(score), dark: dark) }

    /// The score from which the chip text is the inverse colour (light 100, dark 0: white on every dark chip).
    public static func switchScore(dark: Bool) -> Int {
        Int(TokenValues.dimension(dark ? "light/rampText/switchScore/dark" : "light/rampText/switchScore/light"))
    }

    /// Text, score and symbol colour on the fill at this score.
    public static func text(score: Double, dark: Bool) -> RGB {
        let token = TokenValues.color(clamp(score) >= Double(switchScore(dark: dark)) ? "light/rampText/inverse" : "light/rampText/ink")
        return dark ? token.darkRGB : token.lightRGB
    }

    public static func text(score: Int, dark: Bool) -> RGB { text(score: Double(score), dark: dark) }

    /// Fills below this score are too close to the ground to read as a shape and get a separator hairline.
    public static var hairlineBelowScore: Double { TokenValues.dimension("event/hairlineBelowScore") }
}
