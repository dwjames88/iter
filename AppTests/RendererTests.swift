import AppKit
import Charts
import SwiftUI
import Testing
@testable import Iter

/// Regression tests for the offscreen renderer (`Snapshot`): fixtures that exercise the things that used to render
/// wrongly (AppKit-backed lists, sidebar glass, vibrancy, toolbars, charts, canvases) with assertions on pixels.
/// With `ITER_SNAPSHOTS=1` the images are also written next to the screen snapshots as `renderer-*.png`.
@MainActor
@Suite(.serialized) struct RendererTests {
    static let size = Snapshot.Size(name: "960x640", width: 960, height: 640)

    private func render<V: View>(_ view: V, _ name: String, _ appearance: Snapshot.Appearance, chrome: Snapshot.Chrome = .titled) async throws -> Pixels {
        let image = try await Snapshot.renderImage(view, appearance: appearance, size: Self.size, settle: .milliseconds(300), chrome: chrome)
        if Snapshot.enabled {
            try FileManager.default.createDirectory(at: Snapshot.outputDirectory, withIntermediateDirectories: true)
            let rep = NSBitmapImageRep(cgImage: image)
            try rep.representation(using: .png, properties: [:])?
                .write(to: Snapshot.outputDirectory.appendingPathComponent("renderer-\(name)-\(appearance.rawValue)-960x640.png"))
        }
        return try #require(Pixels(image))
    }

    // MARK: Fixtures

    private struct SidebarFixture: View {
        @State private var selection: String? = "all"
        var body: some View {
            NavigationSplitView {
                List(selection: $selection) {
                    Section("Trips") {
                        Label("All Trips", systemImage: "map").tag("all")
                        Label("Canyon Country", systemImage: "point.topleft.down.to.point.bottomright.curvepath").tag("canyon")
                    }
                    Section("Find") {
                        Label("Explore", systemImage: "binoculars").tag("explore")
                        Label("Saved", systemImage: "bookmark").tag("saved")
                    }
                }
                .listStyle(.sidebar)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
            } detail: {
                VStack(spacing: 12) {
                    Text("Detail column").font(.largeTitle).bold()
                    Text("Secondary line").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private struct FormFixture: View {
        @State private var name = "Mesa Arch"
        @State private var on = true
        @State private var pick = 1
        var body: some View {
            Form {
                Section("Spot") {
                    TextField("Name", text: $name)
                    Toggle("Golden hour alerts", isOn: $on)
                    Picker("Camera", selection: $pick) { Text("Wide").tag(1); Text("Tele").tag(2) }
                }
                Section("Notes") { Text("Arrive 45 minutes before sunrise.") }
            }
            .formStyle(.grouped)
        }
    }

    private struct ChartFixture: View {
        struct Point: Identifiable { let id: Int; let value: Double }
        let points = (0..<8).map { Point(id: $0, value: Double(($0 * 5) % 9 + 2)) }
        var body: some View {
            Chart(points) { BarMark(x: .value("Day", $0.id), y: .value("Score", $0.value)).foregroundStyle(Color.red) }
                .padding(24)
        }
    }

    private struct ContrastFixture: View {
        var body: some View {
            VStack(spacing: 0) {
                Text("Dark on light").font(.system(size: 40, weight: .bold)).foregroundStyle(.black)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white)
                Text("Light on dark").font(.system(size: 40, weight: .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.black)
            }
        }
    }

    private struct ListCanvasFixture: View {
        var body: some View {
            HStack(spacing: 0) {
                List(0..<12, id: \.self) { Text("Row \($0)") }
                    .frame(width: 300)
                ScrollView {
                    VStack(spacing: 8) {
                        Canvas { ctx, size in
                            ctx.fill(Path(CGRect(x: 20, y: 20, width: size.width - 40, height: 100)), with: .color(.red))
                        }.frame(height: 140)
                        ForEach(0..<6) { Text("Scroll item \($0)").padding() }
                    }
                }
            }
        }
    }

    private struct ToolbarFixture: View {
        var body: some View {
            NavigationStack {
                Text("Body").frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle("Canyon Country")
                    .toolbar { ToolbarItem { Button { } label: { Label("New Trip", systemImage: "plus") } } }
            }
        }
    }

    // MARK: Tests

    @Test func sidebarListRendersInBothAppearances() async throws {
        for appearance in Snapshot.Appearance.allCases {
            let px = try await render(SidebarFixture(), "sidebar", appearance)
            let dark = appearance == .dark
            #expect(px.width == 1920 && px.height == 1280)
            let sidebar = px.stats(x: 10, y: 60, w: 220, h: 170)
            let detail = px.stats(x: 400, y: 200, w: 400, h: 200)
            #expect(sidebar.hasContent, "sidebar \(appearance): has text and symbols, not a uniform fill")
            #expect(detail.hasContent, "detail \(appearance): has the title")
            #expect(sidebar.transparent == 0)
            // Text contrast: in dark the ink is light on a dark ground, in light the ink is dark on a light ground.
            if dark {
                #expect(sidebar.medianLuma < 0.3, "dark sidebar ground is dark")
                #expect(sidebar.maxLuma > 0.6, "dark sidebar text is light")
                #expect(detail.medianLuma < 0.3)
                #expect(detail.maxLuma > 0.7)
            } else {
                #expect(sidebar.medianLuma > 0.8, "light sidebar ground is light")
                #expect(sidebar.minLuma < 0.45, "light sidebar text is dark")
                #expect(detail.medianLuma > 0.8)
                #expect(detail.minLuma < 0.3)
            }
        }
    }

    @Test func sidebarSelectionIsAVisibleNeutralPill() async throws {
        for appearance in Snapshot.Appearance.allCases {
            let px = try await render(SidebarFixture(), "sidebar-selection", appearance)
            // The first item is selected: sample the pill's empty right end against the bare sidebar below the list.
            let pill = px.luma(215 * 2, 87 * 2)
            let ground = px.luma(215 * 2, 400 * 2)
            #expect(abs(pill - ground) > 0.03, "selection pill differs from the sidebar ground (\(pill) vs \(ground))")
            if appearance == .dark { #expect(pill > 0.08, "dark selection pill is not a black bar (\(pill))") }
        }
    }

    @Test func rendersAreDeterministic() async throws {
        let a = try await Snapshot.renderPNG(SidebarFixture(), appearance: .dark, size: Self.size, settle: .milliseconds(300))
        let b = try await Snapshot.renderPNG(SidebarFixture(), appearance: .dark, size: Self.size, settle: .milliseconds(300))
        #expect(a == b, "two renders of the same view are byte-identical")
    }

    @Test func formRendersControlsAndText() async throws {
        for appearance in Snapshot.Appearance.allCases {
            let px = try await render(FormFixture(), "form", appearance)
            let body = px.stats(x: 100, y: 60, w: 760, h: 400)
            #expect(body.hasContent)
            #expect(body.transparent == 0)
            if appearance == .dark { #expect(body.maxLuma > 0.7, "dark form text is light") } else { #expect(body.minLuma < 0.35, "light form text is dark") }
        }
    }

    @Test func chartDrawsItsMarks() async throws {
        for appearance in Snapshot.Appearance.allCases {
            let px = try await render(ChartFixture(), "chart", appearance)
            let plot = px.stats(x: 40, y: 80, w: 880, h: 500)
            #expect(plot.saturated > 2000, "red bars are present (\(plot.saturated) saturated pixels)")
        }
    }

    @Test func textKeepsItsContrastOnExplicitGrounds() async throws {
        for appearance in Snapshot.Appearance.allCases {
            let px = try await render(ContrastFixture(), "contrast", appearance, chrome: .bare)
            let top = px.stats(x: 0, y: 0, w: 960, h: 320)
            let bottom = px.stats(x: 0, y: 320, w: 960, h: 320)
            #expect(top.medianLuma > 0.95 && top.minLuma < 0.2, "black text on white")
            #expect(bottom.medianLuma < 0.05 && bottom.maxLuma > 0.8, "white text on black")
        }
    }

    @Test func listScrollViewAndCanvasRender() async throws {
        for appearance in Snapshot.Appearance.allCases {
            let px = try await render(ListCanvasFixture(), "list-canvas", appearance, chrome: .bare)
            let list = px.stats(x: 0, y: 0, w: 300, h: 300)
            #expect(list.hasContent, "plain List rows draw text")
            if appearance == .dark { #expect(list.maxLuma > 0.6, "dark list text is light") } else { #expect(list.minLuma < 0.4) }
            let canvas = px.stats(x: 320, y: 20, w: 600, h: 140)
            #expect(canvas.saturated > 5000, "Canvas fill is present")
        }
    }

    @Test func toolbarAndTitleAreDrawn() async throws {
        for appearance in Snapshot.Appearance.allCases {
            let px = try await render(ToolbarFixture(), "toolbar", appearance)
            let bar = px.stats(x: 0, y: 0, w: 960, h: 52)
            #expect(bar.hasContent, "title, traffic lights and toolbar button draw in the top band")
            let body = px.stats(x: 300, y: 300, w: 360, h: 80)
            #expect(body.hasContent)
        }
    }
}
