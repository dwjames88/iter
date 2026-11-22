import Foundation
import SwiftUI
import Testing
@testable import IterUI

// MARK: WCAG helpers (implemented here on purpose, independent of the library's own luminance)

private func luminance(_ hex: String) -> Double {
    let rgb = RGB(hex: hex)!
    func lin(_ v: Int) -> Double {
        let c = Double(v) / 255
        return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * lin(rgb.red) + 0.7152 * lin(rgb.green) + 0.0722 * lin(rgb.blue)
}

private func contrast(_ a: String, _ b: String) -> Double {
    let (x, y) = (luminance(a), luminance(b))
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)
}

private func token(_ name: String) -> ColorToken { TokenValues.color(name) }

enum Mode: CaseIterable, Sendable {
    case light, dark
    func hex(_ t: ColorToken) -> String { self == .light ? t.light : t.dark }
    func hex(_ name: String) -> String { hex(token(name)) }
}

/// Machado et al. (2009) deuteranopia matrix at full severity, applied in linear RGB.
private func deuteranope(_ hex: String) -> Double {
    let rgb = RGB(hex: hex)!
    func lin(_ v: Int) -> Double { let c = Double(v) / 255; return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    let (r, g, b) = (lin(rgb.red), lin(rgb.green), lin(rgb.blue))
    let r2 = 0.367322 * r + 0.860646 * g - 0.227968 * b
    let g2 = 0.280085 * r + 0.672501 * g + 0.047413 * b
    let b2 = -0.011820 * r + 0.042940 * g + 0.968881 * b
    func clamp(_ v: Double) -> Double { min(max(v, 0), 1) }
    return 0.2126 * clamp(r2) + 0.7152 * clamp(g2) + 0.0722 * clamp(b2)
}

@Suite("Token registry")
struct TokenRegistryTests {
    @Test func namesAreUniqueAndNeverAGroupAndALeaf() {
        let all = TokenValues.colors.map(\.name) + TokenValues.dimensions.map(\.name) + TokenValues.typography.map(\.name)
        #expect(Set(all).count == all.count)
        let names = Set(all)
        for n in all {
            var parts = n.split(separator: "/").map(String.init)
            parts.removeLast()
            for i in 1...max(parts.count, 1) where !parts.isEmpty {
                #expect(!names.contains(parts.prefix(i).joined(separator: "/")), "\(n) sits under a leaf token")
            }
        }
    }

    @Test func hexValuesAreValidAndDescriptionsPresent() {
        for t in TokenValues.colors {
            #expect(RGB(hex: t.light) != nil, "\(t.name) light \(t.light)")
            #expect(RGB(hex: t.dark) != nil, "\(t.name) dark \(t.dark)")
            #expect(t.light == t.light.uppercased() && t.dark == t.dark.uppercased())
            #expect(!t.description.isEmpty)
            if let alias = t.systemAlias { #expect(IterColor.supportedSystemAliases.contains(alias), "\(t.name) alias \(alias)") }
        }
        for t in TokenValues.dimensions { #expect(t.points >= 0 && !t.description.isEmpty, "\(t.name)") }
        for t in TokenValues.typography { #expect(!t.description.isEmpty) }
    }

    @Test func rampStopsAndTextTokensExist() {
        for stop in IterRamp.stopScores { _ = TokenValues.color("light/ramp/\(stop)") }
        _ = TokenValues.color("light/rampText/ink"); _ = TokenValues.color("light/rampText/inverse")
        for score in [-5, 0, 50, 100, 140] { _ = IterColor.ramp(score: score); _ = IterColor.rampText(score: score) }
        for score in [-5.5, 0, 12.5, 100, 140.5] { _ = IterColor.ramp(score: score); _ = IterColor.rampText(score: score) }
    }

    @Test func everyAPINameResolves() {
        // Touching each static forces the registry lookup (which traps on a missing name).
        let _: [Color] = [
            IterColor.accent,
            IterColor.accentText,
            IterColor.accentHover,
            IterColor.accentPressed,
            IterColor.accentDisabled,
            IterColor.accentEmphasis,
            IterColor.onAccent,
            IterColor.selection,
            IterColor.focusRing,
            IterColor.route,
            IterColor.routeInactive,
            IterColor.mapPin,
            IterColor.mapPinInactive,
            IterColor.brandDot,
            IterColor.sun,
            IterColor.moon,
            IterColor.warning,
            IterColor.danger,
            IterColor.noForecast,
            IterColor.skyNight,
            IterColor.skyBlue,
            IterColor.skyGolden,
            IterColor.skyDay,
            IterColor.cloudLow,
            IterColor.cloudMid,
            IterColor.cloudHigh,
            IterColor.separator,
            IterColor.backgroundWindow,
            IterColor.backgroundControl,
            IterColor.backgroundContent,
            IterColor.backgroundSystemWindow,
        ]
        // Text tokens are IterInk (a ShapeStyle); `.color` is the plain colour.
        let inks: [IterInk] = [IterColor.textPrimary, IterColor.textSecondary, IterColor.textTertiary, IterColor.textDisabled]
        let _: [Color] = inks.map(\.color)
        let _: [CGFloat] = [
            IterSpace.xxs,
            IterSpace.xs,
            IterSpace.sm,
            IterSpace.md,
            IterSpace.lg,
            IterSpace.xl,
            IterSpace.xxl,
            IterRadius.badge,
            IterRadius.control,
            IterRadius.card,
            IterRadius.panel,
        ]
        let _: [CGFloat] = [
            IterSize.badgeHeight,
            IterSize.badgeHeightCompact,
            IterSize.badgeHeightLarge,
            IterSize.badgeMinWidth,
            IterSize.mapPin,
            IterSize.mapPinSelected,
            IterSize.controlHeight,
            IterSize.controlHeightLarge,
            IterSize.hitTarget,
            IterSize.iconSmall,
            IterSize.iconMedium,
            IterSize.iconLarge,
            IterSize.confidenceMark,
            IterSize.lightRingSmall,
            IterSize.lightRingMedium,
            IterSize.lightRingLarge,
            IterSize.timelineHeight,
            IterSize.timelineAxisHeight,
            IterSize.arcHeight,
            IterSize.arcMarker,
            IterSize.hourlyTintHeight,
            IterSize.windowMinWidth,
            IterSize.sidebarMin,
            IterSize.sidebarIdeal,
            IterSize.sidebarMax,
            IterSize.listMin,
            IterSize.listIdeal,
            IterSize.listMax,
            IterSize.inspectorMin,
            IterSize.inspectorIdeal,
            IterSize.inspectorMax,
            IterSize.mainWindowMinWidth,
            IterSize.windowMinHeight,
        ]
        let _: [CGFloat] = [
            IterStroke.hairline,
            IterStroke.thin,
            IterStroke.regular,
            IterStroke.thick,
            IterStroke.route,
            IterStroke.routeInactive,
            IterStroke.routeCasing,
            IterStroke.dashLength,
            IterStroke.dashGap,
            IterStroke.focusRingWidth,
            IterStroke.focusRingOffset,
        ]
        let _: [Font] = [
            IterFont.titleSpot,
            IterFont.titleSection,
            IterFont.headline,
            IterFont.body,
            IterFont.bodyEmphasis,
            IterFont.callout,
            IterFont.subheadline,
            IterFont.footnote,
            IterFont.caption,
            IterFont.captionStrong,
            IterFont.scoreLarge,
            IterFont.scoreMedium,
            IterFont.scoreBadge,
            IterFont.time,
            IterFont.timeSmall,
        ]
        #expect(IterSpace.md == 12 && IterSpace.lg == 16)
    }

    @Test func spacingIsOnTheFourPointGrid() {
        for t in TokenValues.dimensions where t.name.hasPrefix("space/") && t.name != "space/xxs" {
            #expect(t.points.truncatingRemainder(dividingBy: 4) == 0, "\(t.name)")
        }
    }

    @Test func numbersAreMonospacedAndTitleIsSerif() {
        for n in ["type/score/large", "type/score/medium", "type/score/badge", "type/time", "type/timeSmall", "type/event/score", "type/event/time"] {
            #expect(TokenValues.typography(n).monospacedDigits, "\(n)")
        }
        #expect(TokenValues.typography("type/title/spot").design == .serif)
        let others = TokenValues.typography.filter { $0.name != "type/title/spot" }
        #expect(others.allSatisfy { $0.design == .standard })
    }
}

@Suite("Token contrast")
struct TokenContrastTests {
    private func fillHex(_ score: Int, _ mode: Mode) -> String { IterRamp.fill(score: score, dark: mode == .dark).hex }

    @Test func lowScoresGetAHairlineAndHighOnesDoNot() {
        #expect(IterColor.rampNeedsHairline(score: 0) && IterColor.rampNeedsHairline(score: 20))
        #expect(!IterColor.rampNeedsHairline(score: 60) && !IterColor.rampNeedsHairline(score: 100))
        // The unstroked fills are clearly a shape on the window: 1.15:1 or more in light mode.
        let first = Int(IterRamp.hairlineBelowScore)
        #expect(contrast(fillHex(first, .light), Mode.light.hex("background/window")) >= 1.10)
    }

    @Test(arguments: Mode.allCases) func graphicsAreAtLeast3To1OnTheWindow(_ mode: Mode) {
        let window = mode.hex("background/window")
        let control = mode.hex("background/control")
        for n in ["accent/primary", "route/active", "route/inactive", "focus/ring", "status/noForecast", "map/moon", "map/sun",
                  "status/warning", "status/danger", "map/pin", "map/pinInactive", "accent/emphasis", "brand/dot", "light/blueHour"] {
            #expect(contrast(mode.hex(n), window) >= 3, "\(n) \(mode) on window: \(contrast(mode.hex(n), window))")
            #expect(contrast(mode.hex(n), control) >= 3, "\(n) \(mode) on control: \(contrast(mode.hex(n), control))")
        }
    }

    @Test(arguments: Mode.allCases) func textColoursAreAtLeast4_5(_ mode: Mode) {
        let window = mode.hex("background/window")
        let control = mode.hex("background/control")
        for n in ["accent/text", "status/warning", "status/danger", "text/primary", "text/secondary"] {
            #expect(contrast(mode.hex(n), window) >= 4.5, "\(n) \(mode) on window: \(contrast(mode.hex(n), window))")
            #expect(contrast(mode.hex(n), control) >= 4.5, "\(n) \(mode) on control: \(contrast(mode.hex(n), control))")
        }
        let module = mode.hex("background/module")
        for n in ["text/primary", "text/secondary"] {
            #expect(contrast(mode.hex(n), module) >= 4.5, "\(n) \(mode) on module: \(contrast(mode.hex(n), module))")
        }
        #expect(contrast(mode.hex("light/blueHour"), module) >= 3, "blueHour \(mode) on module")
        let selection = mode.hex("selection/fill")
        for n in ["text/primary", "text/secondary", "accent/text"] {
            #expect(contrast(mode.hex(n), selection) >= 4.5, "\(n) \(mode) on selection: \(contrast(mode.hex(n), selection))")
        }
        let onAccent = mode.hex("accent/onAccent")
        #expect(contrast(onAccent, mode.hex("accent/emphasis")) >= 4.5, "onAccent on emphasis \(mode)")
        #expect(contrast(onAccent, mode.hex("accent/primary")) >= 3, "onAccent on primary \(mode)")   // icons and large text
        #expect(contrast(mode.hex("text/secondary"), mode.hex("background/systemWindow")) >= 4.5, "secondary on system window \(mode)")
    }

    /// OKLCH hue in degrees, from the OKLab matrices (Ottosson), independent of the library.
    private func oklchHue(_ hex: String) -> Double {
        let c = RGB(hex: hex)!
        func lin(_ v: Int) -> Double { let x = Double(v) / 255; return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        let (r, g, b) = (lin(c.red), lin(c.green), lin(c.blue))
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        let h = atan2(bb, a) * 180 / .pi
        return h < 0 ? h + 360 : h
    }

    private func hueDistance(_ x: String, _ y: String) -> Double {
        let d = abs(oklchHue(x) - oklchHue(y)).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    @Test(arguments: Mode.allCases) func statusColoursKeepTheirOwnHues(_ mode: Mode) {
        let accent = mode.hex("accent/primary"), danger = mode.hex("status/danger"), warning = mode.hex("status/warning")
        #expect(hueDistance(danger, accent) >= 35, "danger vs accent \(mode): \(hueDistance(danger, accent))")
        #expect(hueDistance(warning, accent) >= 60, "warning vs accent \(mode): \(hueDistance(warning, accent))")
        #expect(hueDistance(danger, warning) >= 35, "danger vs warning \(mode): \(hueDistance(danger, warning))")
        let w = oklchHue(warning)
        #expect(w >= 280 && w <= 320, "warning is violet: \(w)")
    }
}

@Suite("Token round trip")
struct TokenRoundTripTests {
    @Test func exportImportExportIsByteIdentical() throws {
        let first = TokenCodec.exportJSON(.current)
        let imported = try TokenCodec.importJSON(first)
        #expect(imported == .current)
        #expect(TokenCodec.exportJSON(imported) == first)
    }

    /// tokens.json is the source and is kept in the canonical layout (`scripts/tokens.sh format`).
    @Test func committedTokensJSONIsCanonicalAndMatchesTheRegistry() throws {
        let url = Self.repoRoot.appendingPathComponent("Design/tokens.json")
        let text = try String(contentsOf: url, encoding: .utf8)
        let imported = try TokenCodec.importJSON(text)
        #expect(imported == .current)
        #expect(text == TokenCodec.exportJSON(imported), "Design/tokens.json is not canonical: run scripts/tokens.sh format")
    }

    /// `swift test` fails here when Design/tokens.json and the generated TokenValues.swift drift apart.
    @Test func tokenValuesFileIsWhatTheGeneratorWrites() throws {
        let json = try String(contentsOf: Self.repoRoot.appendingPathComponent("Design/tokens.json"), encoding: .utf8)
        let swift = try String(contentsOf: Self.repoRoot.appendingPathComponent("Packages/Iter/Sources/IterUI/Tokens/TokenValues.swift"), encoding: .utf8)
        #expect(swift == TokenCodec.swiftSource(try TokenCodec.importJSON(json)),
                "TokenValues.swift differs from what tokens.json generates: run scripts/tokens.sh")
    }

    @Test func generatedFileHasTheGeneratedHeaderAndOneTokenPerLine() throws {
        let swift = TokenCodec.swiftSource(.current)
        #expect(swift.hasPrefix("// GENERATED from Design/tokens.json by iter-tokens"))
        #expect(swift.contains("Do not edit by hand"))
        let tokenLines = swift.split(separator: "\n").filter { $0.contains("ColorToken(\"") || $0.contains("DimensionToken(\"") || $0.contains("TypographyToken(\"") }
        #expect(tokenLines.count == TokenValues.colors.count + TokenValues.dimensions.count + TokenValues.typography.count)
    }

    @Test func editingTheJSONComesBackAsSwift() throws {
        var text = TokenCodec.exportJSON(.current)
        text = text.replacingOccurrences(of: "\"hex\": \"#d9431a\"", with: "\"hex\": \"#123456\"")
        let reg = try TokenCodec.importJSON(text)
        #expect(reg.colors.first { $0.name == "accent/primary" }?.light == "#123456")
        #expect(TokenCodec.swiftSource(reg).contains("light: \"#123456\""))
    }

    @Test func colorsetsAreWrittenWithLightAndDark() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iter-tokens-\(UUID().uuidString).xcassets")
        defer { try? FileManager.default.removeItem(at: dir) }
        try TokenCodec.writeAssets(.current, to: dir)
        let epic = try OrderedJSON.parse(String(contentsOf: dir.appendingPathComponent("Tokens/light-ramp-100.colorset/Contents.json"), encoding: .utf8))
        guard case .array(let colors)? = epic["colors"] else { Issue.record("no colors"); return }
        #expect(colors.count == 2)
        #expect(colors[0]["color"]?["components"]?["red"]?.stringValue == "0xC9")
        #expect(colors[1]["appearances"] != nil)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("AccentColor.colorset/Contents.json").path))
        let count = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("Tokens").path).filter { $0.hasSuffix(".colorset") }.count
        #expect(count == TokenValues.colors.count)
    }

    static var repoRoot: URL {
        // <root>/Packages/Iter/Tests/IterUITests/Tokens/TokenRegistryTests.swift
        (0..<6).reduce(URL(fileURLWithPath: #filePath)) { url, _ in url.deletingLastPathComponent() }
    }
}
