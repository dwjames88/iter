import Foundation
import SwiftUI
import Testing
import IterCore
@testable import IterDesign

private let bands = LightBand.allCases
private func bandKey(_ b: LightBand) -> String { IterColor.bandKey(b) }

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

enum Mode: CaseIterable {
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

@Suite("Registry")
struct RegistryTests {
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
        for t in TokenValues.dimensions { #expect(t.points > 0 && !t.description.isEmpty, "\(t.name)") }
        for t in TokenValues.typography { #expect(!t.description.isEmpty) }
    }

    @Test func everyBandHasRampAndTextTokens() {
        for b in bands {
            #expect(TokenValues.colors.contains { $0.name == IterColor.rampTokenName(b) })
            #expect(TokenValues.colors.contains { $0.name == IterColor.rampTextTokenName(b) })
            _ = IterColor.ramp(b)
            _ = IterColor.rampText(b)
        }
    }

    @Test func everyAPINameResolves() {
        // Touching each static forces the registry lookup (which traps on a missing name).
        let _: [Color] = [
            IterColor.accent,
            IterColor.accentText,
            IterColor.onAccent,
            IterColor.focusRing,
            IterColor.route,
            IterColor.routeInactive,
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
            IterColor.textPrimary,
            IterColor.textSecondary,
            IterColor.textTertiary,
            IterColor.textDisabled,
            IterColor.separator,
            IterColor.backgroundWindow,
            IterColor.backgroundControl,
            IterColor.backgroundContent,
        ]
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
        for n in ["type/score/large", "type/score/medium", "type/score/badge", "type/time", "type/timeSmall"] {
            #expect(TokenValues.typography(n).monospacedDigits, "\(n)")
        }
        #expect(TokenValues.typography("type/title/spot").design == .serif)
        let others = TokenValues.typography.filter { $0.name != "type/title/spot" }
        #expect(others.allSatisfy { $0.design == .standard })
    }
}

@Suite("Contrast")
struct ContrastTests {
    @Test(arguments: Mode.allCases) func rampTextOnFillIsAtLeast4_5(_ mode: Mode) {
        for b in bands {
            let ratio = contrast(mode.hex("light/ramp/\(bandKey(b))"), mode.hex("light/rampText/\(bandKey(b))"))
            #expect(ratio >= 4.5, "\(b) \(mode): \(ratio)")
        }
    }

    @Test func rampIsMonotonicInLuminance() {
        // Light mode: sand to deep amber gets darker. Dark mode: dim sand to bright amber gets lighter.
        for mode in Mode.allCases {
            let lums = bands.map { luminance(mode.hex("light/ramp/\(bandKey($0))")) }
            for (a, b) in zip(lums, lums.dropFirst()) {
                #expect(mode == .light ? a > b : a < b, "\(mode) \(lums)")
            }
        }
    }

    @Test(arguments: Mode.allCases) func adjacentBandsStayDistinctInGreyscale(_ mode: Mode) {
        let hexes = bands.map { mode.hex("light/ramp/\(bandKey($0))") }
        for (a, b) in zip(hexes, hexes.dropFirst()) { #expect(contrast(a, b) >= 1.2, "\(a) \(b)") }
        // Epic against Good, and against Fair, for a deuteranope.
        let (good, epic) = (deuteranope(hexes[2]), deuteranope(hexes[4]))
        #expect((max(good, epic) + 0.05) / (min(good, epic) + 0.05) >= 1.8)
    }

    // `brand/dot` is excluded: it is part of the logo, which WCAG 1.4.11 exempts, and it keeps the chosen file's gold.
    @Test(arguments: Mode.allCases) func graphicsAreAtLeast3To1OnTheWindow(_ mode: Mode) {
        let window = mode.hex("background/window")
        let control = mode.hex("background/control")
        for n in ["accent/primary", "route/active", "route/inactive", "focus/ring", "status/noForecast", "map/moon", "map/sun",
                  "status/warning", "status/danger"] {
            #expect(contrast(mode.hex(n), window) >= 3, "\(n) \(mode) on window: \(contrast(mode.hex(n), window))")
            #expect(contrast(mode.hex(n), control) >= 3, "\(n) \(mode) on control: \(contrast(mode.hex(n), control))")
        }
    }

    @Test(arguments: Mode.allCases) func textColoursAreAtLeast4_5(_ mode: Mode) {
        let window = mode.hex("background/window")
        let control = mode.hex("background/control")
        for n in ["accent/text", "status/warning", "status/danger", "text/primary"] {
            #expect(contrast(mode.hex(n), window) >= 4.5, "\(n) \(mode) on window: \(contrast(mode.hex(n), window))")
            #expect(contrast(mode.hex(n), control) >= 4.5, "\(n) \(mode) on control: \(contrast(mode.hex(n), control))")
        }
        #expect(contrast(mode.hex("accent/onAccent"), mode.hex("accent/primary")) >= 4.5)
    }

    @Test func statusColoursKeepTheirOwnHues() {
        // Never green or coral, and not the amber of the ramp: check hue angles in both modes.
        func hue(_ hex: String) -> Double {
            let c = RGB(hex: hex)!
            let (r, g, b) = (Double(c.red) / 255, Double(c.green) / 255, Double(c.blue) / 255)
            let mx = max(r, g, b), mn = min(r, g, b), d = mx - mn
            guard d > 0 else { return 0 }
            let h = mx == r ? ((g - b) / d).truncatingRemainder(dividingBy: 6) : mx == g ? (b - r) / d + 2 : (r - g) / d + 4
            return (h * 60 + 360).truncatingRemainder(dividingBy: 360)
        }
        for mode in Mode.allCases {
            let warning = hue(mode.hex("status/warning")), danger = hue(mode.hex("status/danger"))
            #expect(warning > 250 && warning < 310, "warning hue \(warning)")          // violet
            #expect(danger > 330 || danger < 10, "danger hue \(danger)")               // crimson, bluer than coral (~14 deg)
            let brand = hue(mode.hex("brand/dot"))
            #expect(abs(brand - danger) > 15 || abs(brand - danger) > 345)
        }
    }
}

@Suite("Round trip")
struct RoundTripTests {
    @Test func exportImportExportIsByteIdentical() throws {
        let first = TokenCodec.exportJSON(.current)
        let imported = try TokenCodec.importJSON(first)
        #expect(imported == .current)
        #expect(TokenCodec.exportJSON(imported) == first)
    }

    @Test func committedTokensJSONIsCurrent() throws {
        let url = Self.repoRoot.appendingPathComponent("Design/tokens.json")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text == TokenCodec.exportJSON(.current), "Design/tokens.json is stale: run scripts/tokens.sh")
    }

    @Test func tokenValuesFileIsWhatTheGeneratorWrites() throws {
        let url = Self.repoRoot.appendingPathComponent("Packages/IterKit/Sources/IterDesign/TokenValues.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text == TokenCodec.swiftSource(.current), "TokenValues.swift differs from generator output")
    }

    @Test func editingTheJSONComesBackAsSwift() throws {
        var text = TokenCodec.exportJSON(.current)
        text = text.replacingOccurrences(of: "\"hex\": \"#0a7c6e\"", with: "\"hex\": \"#123456\"")
        let reg = try TokenCodec.importJSON(text)
        #expect(reg.colors.first { $0.name == "accent/primary" }?.light == "#123456")
        #expect(TokenCodec.swiftSource(reg).contains("light: \"#123456\""))
    }

    @Test func colorsetsAreWrittenWithLightAndDark() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("iter-tokens-\(UUID().uuidString).xcassets")
        defer { try? FileManager.default.removeItem(at: dir) }
        try TokenCodec.writeAssets(.current, to: dir)
        let epic = try OrderedJSON.parse(String(contentsOf: dir.appendingPathComponent("Tokens/light-ramp-epic.colorset/Contents.json"), encoding: .utf8))
        guard case .array(let colors)? = epic["colors"] else { Issue.record("no colors"); return }
        #expect(colors.count == 2)
        #expect(colors[0]["color"]?["components"]?["red"]?.stringValue == "0x6B")
        #expect(colors[1]["appearances"] != nil)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("AccentColor.colorset/Contents.json").path))
        let count = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("Tokens").path).filter { $0.hasSuffix(".colorset") }.count
        #expect(count == TokenValues.colors.count)
    }

    static var repoRoot: URL {
        // .../Packages/IterKit/Tests/IterDesignTests/TokenTests.swift
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}
