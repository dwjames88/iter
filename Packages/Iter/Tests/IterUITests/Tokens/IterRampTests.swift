import SwiftUI
import Testing
#if canImport(AppKit)
import AppKit
#endif
@testable import IterUI

// The expected stops are written out here on purpose (not read from the registry), so a change to tokens.json that
// moves a ramp stop fails these tests until the design decision is recorded here too.
private let lightStops = ["#FFFFFF", "#FFEED9", "#FFCFA1", "#E98A5A", "#C9502A"]
private let darkStops = ["#1E1410", "#4A2E22", "#8A4A32", "#C4663F", "#E68A62"]
private let stopScores = [0, 25, 50, 75, 100]

private func rgb(_ hex: String) -> RGB { RGB(hex: hex)! }

/// WCAG 2.x relative luminance, written independently of the library's own.
private func luminance(_ c: RGB) -> Double {
    func lin(_ v: Int) -> Double {
        let x = Double(v) / 255
        return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * lin(c.red) + 0.7152 * lin(c.green) + 0.0722 * lin(c.blue)
}

private func contrast(_ a: RGB, _ b: RGB) -> Double {
    let (x, y) = (luminance(a), luminance(b))
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)
}

@Suite("Iter ramp")
struct IterRampTests {
    @Test func everyStopIsExactInLightAndDark() {
        for (i, score) in stopScores.enumerated() {
            #expect(IterRamp.fill(score: score, dark: false) == rgb(lightStops[i]), "light \(score)")
            #expect(IterRamp.fill(score: score, dark: true) == rgb(darkStops[i]), "dark \(score)")
            #expect(IterRamp.fill(score: Double(score), dark: false) == rgb(lightStops[i]))
            #expect(IterRamp.fill(score: Double(score), dark: true) == rgb(darkStops[i]))
        }
    }

    @Test func endpointsAreNoLightAndTheDeepestOrange() {
        #expect(IterRamp.fill(score: 0, dark: false).hex == "#FFFFFF")
        #expect(IterRamp.fill(score: 100, dark: false).hex == "#C9502A")
        #expect(IterRamp.fill(score: 0, dark: true).hex == "#1E1410")
        #expect(IterRamp.fill(score: 100, dark: true).hex == "#E68A62")
        // The 100 stop is the ramp's own orange, not the accent.
        #expect(IterRamp.fill(score: 100, dark: false) != TokenValues.color("accent/primary").lightRGB)
    }

    @Test(arguments: [false, true]) func scoresOutsideTheRangeClamp(_ dark: Bool) {
        for s in [-1.0, -50.5, -1e9, -Double.infinity] { #expect(IterRamp.fill(score: s, dark: dark) == IterRamp.fill(score: 0, dark: dark)) }
        for s in [100.001, 140.0, 1e9, Double.infinity] { #expect(IterRamp.fill(score: s, dark: dark) == IterRamp.fill(score: 100, dark: dark)) }
        #expect(IterRamp.fill(score: Double.nan, dark: dark) == IterRamp.fill(score: 0, dark: dark))
        #expect(IterRamp.fill(score: -3, dark: dark) == IterRamp.fill(score: 0, dark: dark))
        #expect(IterRamp.fill(score: 130, dark: dark) == IterRamp.fill(score: 100, dark: dark))
        #expect(IterRamp.text(score: -3, dark: dark) == IterRamp.text(score: 0, dark: dark))
        #expect(IterRamp.text(score: 130, dark: dark) == IterRamp.text(score: 100, dark: dark))
    }

    /// Midpoints between neighbouring stops are the per-channel mean, rounded half up. Values worked out by hand from the
    /// stop table above.
    @Test func midpointInterpolation() {
        // light 12.5: FFFFFF / FFEED9 -> FF, (255+238)/2 = 246.5 -> 247 (F7), (255+217)/2 = 236 (EC)
        #expect(IterRamp.fill(score: 12.5, dark: false).hex == "#FFF7EC")
        // light 37.5: FFEED9 / FFCFA1 -> FF, (238+207)/2 = 222.5 -> 223 (DF), (217+161)/2 = 189 (BD)
        #expect(IterRamp.fill(score: 37.5, dark: false).hex == "#FFDFBD")
        // light 62.5: FFCFA1 / E98A5A -> (255+233)/2 = 244 (F4), (207+138)/2 = 172.5 -> 173 (AD), (161+90)/2 = 125.5 -> 126 (7E)
        #expect(IterRamp.fill(score: 62.5, dark: false).hex == "#F4AD7E")
        // light 87.5: E98A5A / C9502A -> (233+201)/2 = 217 (D9), (138+80)/2 = 109 (6D), (90+42)/2 = 66 (42)
        #expect(IterRamp.fill(score: 87.5, dark: false).hex == "#D96D42")
        // dark 12.5: 1E1410 / 4A2E22 -> (30+74)/2 = 52 (34), (20+46)/2 = 33 (21), (16+34)/2 = 25 (19)
        #expect(IterRamp.fill(score: 12.5, dark: true).hex == "#342119")
        // dark 37.5: 4A2E22 / 8A4A32 -> (74+138)/2 = 106 (6A), (46+74)/2 = 60 (3C), (34+50)/2 = 42 (2A)
        #expect(IterRamp.fill(score: 37.5, dark: true).hex == "#6A3C2A")
        // dark 62.5: 8A4A32 / C4663F -> (138+196)/2 = 167 (A7), (74+102)/2 = 88 (58), (50+63)/2 = 56.5 -> 57 (39)
        #expect(IterRamp.fill(score: 62.5, dark: true).hex == "#A75839")
        // dark 87.5: C4663F / E68A62 -> (196+230)/2 = 213 (D5), (102+138)/2 = 120 (78), (63+98)/2 = 80.5 -> 81 (51)
        #expect(IterRamp.fill(score: 87.5, dark: true).hex == "#D57851")
    }

    @Test(arguments: [false, true]) func interpolationIsLinearBetweenStops(_ dark: Bool) {
        let stops = (dark ? darkStops : lightStops).map(rgb)
        for s in 0...100 {
            let i = min(s / 25, 3)
            let t = Double(s - stopScores[i]) / 25
            let got = IterRamp.fill(score: s, dark: dark)
            for (g, lo, hi) in [(got.red, stops[i].red, stops[i + 1].red), (got.green, stops[i].green, stops[i + 1].green), (got.blue, stops[i].blue, stops[i + 1].blue)] {
                #expect(abs(Double(g) - (Double(lo) + (Double(hi) - Double(lo)) * t)) <= 0.5 + 1e-9, "score \(s)")
            }
        }
    }

    @Test func intAndDoubleOverloadsAgree() {
        for s in 0...100 {
            for dark in [false, true] {
                #expect(IterRamp.fill(score: s, dark: dark) == IterRamp.fill(score: Double(s), dark: dark))
                #expect(IterRamp.text(score: s, dark: dark) == IterRamp.text(score: Double(s), dark: dark))
            }
        }
    }

    /// Luminance moves one way along the ramp: down in light (white to deep orange), up in dark. Checked every 0.25.
    @Test(arguments: [false, true]) func luminanceIsMonotonic(_ dark: Bool) {
        let lums = stride(from: 0.0, through: 100.0, by: 0.25).map { luminance(IterRamp.fill(score: $0, dark: dark)) }
        for (a, b) in zip(lums, lums.dropFirst()) {
            if dark { #expect(a <= b) } else { #expect(a >= b) }
        }
        #expect(dark ? lums.first! < lums.last! : lums.first! > lums.last!)
    }

    @Test func noLightIsPaperWhiteInLightAndTheDarkSurfaceInDark() {
        #expect(luminance(IterRamp.fill(score: 0, dark: false)) == 1)
        #expect(luminance(IterRamp.fill(score: 0, dark: true)) < 0.02)
    }

    /// Light: ink up to the switch score (100), white at 100. White already beats ink from 99, but only at 100 does it
    /// reach 4.5:1 (4.50 vs 4.14:1), so the design switches there.
    @Test func lightTextRule() {
        let ink = rgb("#1E0F0A"), white = rgb("#FFFFFF")
        #expect(IterRamp.switchScore(dark: false) == 100)
        for s in 0...100 {
            let fill = IterRamp.fill(score: s, dark: false)
            #expect(IterRamp.text(score: s, dark: false) == (s >= 100 ? white : ink), "score \(s)")
            #expect((contrast(fill, white) > contrast(fill, ink)) == (s >= 99), "score \(s)")
        }
        let top = IterRamp.fill(score: 100, dark: false)
        #expect(contrast(top, white) >= 4.5 && contrast(top, ink) < 4.5)
        // Ink holds 4.5:1 through score 96 and falls under it from 97.
        for s in 0...96 { #expect(contrast(IterRamp.fill(score: s, dark: false), ink) >= 4.5, "score \(s)") }
        #expect(contrast(IterRamp.fill(score: 97, dark: false), ink) < 4.5)
    }

    /// Dark: white on every chip, as designed (switch score 0). The brightest fills miss 4.5:1 by design.
    @Test func darkTextIsAlwaysWhite() {
        #expect(IterRamp.switchScore(dark: true) == 0)
        for s in 0...100 { #expect(IterRamp.text(score: s, dark: true).hex == "#FFFFFF", "score \(s)") }
        let white = rgb("#FFFFFF")
        func ratio(_ s: Int) -> Double { contrast(IterRamp.fill(score: s, dark: true), white) }
        #expect(ratio(0) >= 18 && ratio(25) >= 12.3 && ratio(50) >= 6.7)
        #expect(ratio(75) >= 3.9 && ratio(75) < 4.5)
        #expect(ratio(100) >= 2.5 && ratio(100) < 3)
    }

    #if canImport(AppKit)
    @Test func swiftUIColoursResolveForBothAppearances() throws {
        func resolved(_ c: Color, dark: Bool) throws -> RGB {
            let appearance = try #require(NSAppearance(named: dark ? .darkAqua : .aqua))
            var out = RGB(red: -1, green: -1, blue: -1)
            appearance.performAsCurrentDrawingAppearance {
                let ns = NSColor(c).usingColorSpace(.sRGB)!
                func b(_ v: CGFloat) -> Int { Int((v * 255).rounded()) }
                out = RGB(red: b(ns.redComponent), green: b(ns.greenComponent), blue: b(ns.blueComponent))
            }
            return out
        }
        for s in [0, 25, 40, 75, 100] {
            for dark in [false, true] {
                #expect(try resolved(IterColor.ramp(score: s), dark: dark) == IterRamp.fill(score: s, dark: dark), "int \(s) dark \(dark)")
                #expect(try resolved(IterColor.ramp(score: Double(s) + 0.5), dark: dark) == IterRamp.fill(score: Double(s) + 0.5, dark: dark), "double \(s) dark \(dark)")
                #expect(try resolved(IterColor.rampText(score: s), dark: dark) == IterRamp.text(score: s, dark: dark))
            }
        }
        #expect(try resolved(IterColor.ramp(score: -20), dark: false) == rgb("#FFFFFF"))
        #expect(try resolved(IterColor.ramp(score: 300), dark: true) == rgb("#E68A62"))
    }
    #endif
}
