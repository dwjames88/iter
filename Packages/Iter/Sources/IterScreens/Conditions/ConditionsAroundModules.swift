import SwiftUI
import IterFeatures
import IterModel
import IterSky
import IterConditions
import IterSources
import IterUI

// Modules 5 to 8: hour by hour, now, good to know, sources.

struct HourlyModule: View {
    let model: ConditionsModel

    var body: some View {
        ModuleCard(title: "Hour by Hour", symbol: "cloud.sun") {
            if model.hours.isEmpty {
                if model.status == .loading || model.isUpdating {
                    VStack(spacing: IterSpace.xs) { ForEach(0..<5, id: \.self) { _ in SkeletonBar() } }
                } else {
                    Text("No hourly forecast for this day.").font(IterFont.body).foregroundStyle(IterColor.textSecondary)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    table(full: true)
                    table(full: false)
                }
            }
            if let c = model.comparison {
                Label {
                    Text(verbatim: ConditionsFormat.comparisonLine(c)).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: c.disagrees ? "arrow.triangle.branch" : "checkmark.circle")
                }
                .font(IterFont.secondary).foregroundStyle(c.disagrees ? IterColor.warning : IterColor.textSecondary.color)
            }
        }
    }

    private func table(full: Bool) -> some View {
        let zone = model.place.timeZone
        let scrubHour = model.hours.last { $0.time <= model.scrubTime }?.time
        return VStack(spacing: 0) {
            row(["Time", "Cloud"] + (full ? ["Low", "Mid", "High"] : []) + ["Rain"] + (full ? ["Vis"] : []) + ["Temp", "Wind"], full: full, header: true)
            ForEach(model.hours) { h in
                let cells = [ConditionsFormat.hourLabel(h.time, zone: zone), ConditionsFormat.percent(h.cloudTotal)]
                    + (full ? [ConditionsFormat.percent(h.cloudLow), ConditionsFormat.percent(h.cloudMid), ConditionsFormat.percent(h.cloudHigh)] : [])
                    + [ConditionsFormat.percent(h.precipChance)]
                    + (full ? [ConditionsFormat.visibility(h.visibilityKm)] : [])
                    + [ConditionsFormat.temperature(h.tempC), ConditionsFormat.wind(h.windMs)]
                row(cells, full: full, header: false)
                    .background(h.time == scrubHour ? IterColor.selection : .clear, in: RoundedRectangle(cornerRadius: IterRadius.badge, style: .continuous))
            }
        }
        .frame(minWidth: full ? 440 : 0)
        .accessibilityElement(children: .contain)
    }

    /// One row on fixed lanes: the time lane, then equal-width numeric lanes, all trailing-aligned so every column lines up.
    private func row(_ cells: [String], full: Bool, header: Bool) -> some View {
        HStack(spacing: IterSpace.xs) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, text in
                Text(verbatim: text)
                    .font(header ? IterFont.secondary.weight(.semibold) : IterFont.secondary.monospacedDigit())
                    .foregroundStyle(header || i > 0 ? IterColor.textSecondary : IterColor.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: i == 0 ? 48 : nil, alignment: i == 0 ? .leading : .trailing)
                    .frame(maxWidth: i == 0 ? 48 : .infinity, alignment: i == 0 ? .leading : .trailing)
            }
        }
        .frame(minHeight: header ? 22 : 20)
    }
}

struct NowModule: View {
    let model: ConditionsModel
    @Environment(\.isSampleData) private var isSampleData

    var body: some View {
        ModuleCard(title: "Now", symbol: "dot.radiowaves.left.and.right") {
            VStack(alignment: .leading, spacing: IterSpace.sm) {
                if let o = model.observation {
                    station(o)
                } else if model.status == .loading || model.isUpdating {
                    SkeletonBar(width: 240); SkeletonBar(width: 160)
                } else {
                    Text("No recent station report near this place.").font(IterFont.body).foregroundStyle(IterColor.textSecondary)
                }
                if let live = model.live {
                    liveRow(live)
                } else if model.liveLoad == .loading {
                    DataStateView(.loading, zone: model.place.timeZone)
                }
            }
        }
        .task(id: model.place.id) { await model.loadLive() }
    }

    private func station(_ o: StationObservation) -> some View {
        VStack(alignment: .leading, spacing: IterSpace.xs) {
            Text(verbatim: ConditionsFormat.observationTitle(o)).font(IterFont.headline).foregroundStyle(IterColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .firstTextBaseline, spacing: IterSpace.xs) {
                if o.isMilitary { Image(systemName: "shield.lefthalf.filled").accessibilityHidden(true) }
                Text(verbatim: o.originLabel)
            }
            .font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
            Text(verbatim: metrics(o)).font(IterFont.body).foregroundStyle(IterColor.textPrimary).fixedSize(horizontal: false, vertical: true)
            if !o.weather.isEmpty || o.flightCategory != nil {
                Text(verbatim: ([o.flightCategory].compactMap { $0 } + [o.weather.joined(separator: ", ")].filter { !$0.isEmpty }).joined(separator: " \u{00B7} "))
                    .font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
            }
            if o.isOld {
                Label("Older than 90 minutes, so it is not used in the live score", systemImage: "clock.badge.exclamationmark")
                    .font(IterFont.secondary).foregroundStyle(IterColor.warning)
            }
        }
    }

    private func metrics(_ o: StationObservation) -> String {
        let c = o.conditions
        var parts: [String] = []
        if let t = c.tempC { parts.append(ConditionsFormat.temperature(t)) }
        if let w = c.windMs { parts.append("Wind \(ConditionsFormat.wind(w))" + (c.windDirDeg.map { " from \(ConditionsFormat.cardinal($0))" } ?? "")) }
        if let v = c.visibilityKm { parts.append("Visibility \(ConditionsFormat.visibility(v))") }
        if let cl = c.cloudTotal { parts.append("Cloud \(ConditionsFormat.percent(cl))") }
        return parts.isEmpty ? "No readings in the report" : parts.joined(separator: " \u{00B7} ")
    }

    private func liveRow(_ live: LiveConditions) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: IterSpace.sm) {
            Text(verbatim: SampleDataText.liveWord(sample: isSampleData)).font(IterFont.captionStrong).foregroundStyle(IterColor.accentText)
            if let score = live.reading.score, let kind = live.reading.kind {
                Text(verbatim: "\(ConditionsText.name(kind)) \(score)" + (live.reading.forecastScore.map { " (forecast \($0))" } ?? ""))
                    .font(IterFont.body).foregroundStyle(IterColor.textPrimary)
            } else {
                Text(verbatim: live.notice?.text ?? "No window is in progress").font(IterFont.body).foregroundStyle(IterColor.textSecondary)
            }
        }
    }
}

struct GoodToKnowModule: View {
    let model: ConditionsModel

    var body: some View {
        ModuleCard(title: "Good to Know", symbol: "info.circle") {
            VStack(alignment: .leading, spacing: IterSpace.sm) {
                ForEach(model.alerts) { a in alert(a) }
                ForEach(ConditionsFormat.smokeLines(model.smoke), id: \.self) { line in item("smoke", line) }
                if let a = model.aurora { item("sparkles", ConditionsFormat.auroraLine(a)) }
                horizon
                if let mw = model.compassDay.milkyWay {
                    item("moon.stars", mw.isVisible
                         ? "Milky Way core rises to \(Int(mw.peakAltitude.rounded()))\u{00B0} at \(TimeText.time(mw.peakTime, in: model.place.timeZone))"
                         : "Milky Way core is not up in the dark this night")
                }
                ForEach(model.gaps) { g in item("circle.dashed", ConditionsFormat.gapLine(g), muted: true) }
                if model.alerts.isEmpty, model.smoke.isEmpty, model.aurora == nil, model.gaps.isEmpty, model.horizon.load != .known {
                    Text("Nothing to flag yet.").font(IterFont.body).foregroundStyle(IterColor.textSecondary)
                }
            }
        }
    }

    @ViewBuilder private var horizon: some View {
        switch model.horizon.load {
        case .known:
            if model.horizon.shortened.isEmpty {
                item("mountain.2", "Terrain horizon: tallest skyline \(Int((model.horizon.tallestDegrees ?? 0).rounded()))\u{00B0}, no window is shortened")
            } else {
                ForEach(model.horizon.shortened, id: \.kind) { s in item("mountain.2", ConditionsFormat.terrainLine(s, zone: model.place.timeZone)) }
            }
        case .loading: item("mountain.2", "Terrain horizon is loading", muted: true)
        case .unavailable: item("mountain.2", "Terrain horizon: unavailable", muted: true)
        }
    }

    private func alert(_ a: AlertRow) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: IterSpace.sm) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(IterColor.warning).frame(width: IterSize.iconMedium).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: IterSpace.xxs) {
                Text(verbatim: a.event).font(IterFont.headline).foregroundStyle(IterColor.textPrimary)
                if let h = a.headline { Text(verbatim: h).font(IterFont.body).foregroundStyle(IterColor.textPrimary).fixedSize(horizontal: false, vertical: true) }
                Text(verbatim: [a.sender, a.ends.map { "until \(TimeText.time($0, in: model.place.timeZone))" }].compactMap { $0 }.joined(separator: " \u{00B7} "))
                    .font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
            }
        }
    }

    private func item(_ symbol: String, _ text: String, muted: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: IterSpace.sm) {
            Image(systemName: symbol).foregroundStyle(IterColor.textSecondary).frame(width: IterSize.iconMedium).accessibilityHidden(true)
            Text(verbatim: text).font(IterFont.body).foregroundStyle(muted ? IterColor.textSecondary : IterColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct SourcesFoot: View {
    let model: ConditionsModel

    var body: some View {
        VStack(alignment: .leading, spacing: IterSpace.xs) {
            Text("Sources").font(IterFont.moduleTitle).foregroundStyle(IterColor.textSecondary)
            if model.sourceLines.isEmpty {
                Text("Sources appear with the forecast.").font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
            }
            ForEach(Array(model.sourceLines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: IterSpace.xs) {
                    if line.staleAge != nil { Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(IterColor.warning) }
                    Text(verbatim: line.line).foregroundStyle(IterColor.textSecondary)
                }
                .font(IterFont.secondary)
            }
            Text("Full credits are in Settings.").font(IterFont.secondary).foregroundStyle(IterColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, IterGrid.inset)
    }
}
