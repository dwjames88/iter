import Foundation
import Testing
import IterSourcesLive

// Every fixture against the independent ecCodes reading in <name>.eccodes.json (see make-reference.py).

private func lonDiff(_ a: Double, _ b: Double) -> Double {
    var d = (a - b).truncatingRemainder(dividingBy: 360)
    if d > 180 { d -= 360 }
    if d < -180 { d += 360 }
    return abs(d)
}

@Suite struct GRIB2ReferenceTests {
    @Test func identificationMatchesEccodes() throws {
        for name in GRIB2Fixtures.all {
            let file = try GRIB2File(data: GRIB2Fixtures.data(name)), ref = try GRIB2Fixtures.reference(name)
            #expect(file.failures.isEmpty, "\(name)")
            #expect(file.fields.count == ref.messages.count, "\(name) message count")
            for (f, m) in zip(file.fields, ref.messages) {
                let tag = "\(name) message \(f.messageIndex)"
                #expect(f.parameter == GRIB2Parameter(m.discipline, m.parameterCategory, m.parameterNumber), "\(tag)")
                #expect(f.product.firstSurface?.type == m.typeOfFirstFixedSurface, "\(tag)")
                #expect(f.product.firstSurface?.value == Double(m.level), "\(tag) level")
                #expect(f.product.templateNumber == m.productDefinitionTemplateNumber, "\(tag)")
                #expect(m.dataRepresentationTemplateNumber == 0, "\(tag)")
                #expect(f.grid.templateNumber == m.gridDefinitionTemplateNumber, "\(tag)")
                #expect(f.grid.nx == m.nx && f.grid.ny == m.ny, "\(tag)")
                #expect(f.product.forecastTime == m.forecastTime, "\(tag)")
                let start = Int(Double(f.product.forecastSeconds ?? -1) / 3600), end = Int(f.forecastHour ?? -1)
                #expect(m.stepRange == (f.isStatistical ? "\(start)-\(end)" : "\(end)"), "\(tag) stepRange \(m.stepRange)")
                let c = f.identification.referenceDateComponents
                #expect((c.year ?? 0) * 10_000 + (c.month ?? 0) * 100 + (c.day ?? 0) == m.dataDate, "\(tag)")
                #expect((c.hour ?? 0) * 100 + (c.minute ?? 0) == m.dataTime, "\(tag)")
            }
        }
    }

    @Test func valuesMatchEccodes() throws {
        var maxAbs = 0.0, maxRel = 0.0, count = 0
        for name in GRIB2Fixtures.all {
            let file = try GRIB2File(data: GRIB2Fixtures.data(name)), ref = try GRIB2Fixtures.reference(name)
            for (f, m) in zip(file.fields, ref.messages) {
                #expect(f.values.count == m.values.count, "\(name) message \(f.messageIndex)")
                for (v, e) in zip(f.values, m.values) {
                    guard let e else { #expect(v.isNaN); continue }
                    let d = abs(v - e)
                    maxAbs = max(maxAbs, d)
                    maxRel = max(maxRel, d / max(1, abs(e)))
                    count += 1
                    #expect(d <= 1e-5 * max(1, abs(e)), "\(name) message \(f.messageIndex): \(v) vs \(e)")
                }
            }
        }
        print("GRIB2 values compared: \(count), max abs diff \(maxAbs), max relative (|d|/max(1,|v|)) \(maxRel)")
    }

    @Test func gridCoordinatesMatchEccodes() throws {
        var maxHRRR = 0.0, maxGFS = 0.0
        for name in GRIB2Fixtures.all {
            let file = try GRIB2File(data: GRIB2Fixtures.data(name)), ref = try GRIB2Fixtures.reference(name)
            for f in file.fields {
                #expect(f.grid.pointCount == ref.grid.lats.count, "\(name)")
                var worst = 0.0
                for k in 0..<f.grid.pointCount {
                    guard let lat = f.latitude(ofIndex: k), let lon = f.longitude(ofIndex: k) else {
                        Issue.record("\(name): no coordinate for index \(k)"); break
                    }
                    worst = max(worst, abs(lat - ref.grid.lats[k]), lonDiff(lon, ref.grid.lons[k]))
                }
                #expect(worst <= 1e-4, "\(name): grid lat/lon differ by \(worst) degrees")
                if name.hasPrefix("hrrr") { maxHRRR = max(maxHRRR, worst) } else { maxGFS = max(maxGFS, worst) }
                #expect(f.latitude(ofIndex: -1) == nil && f.latitude(ofIndex: f.grid.pointCount) == nil)
            }
        }
        print("GRIB2 grid lat/lon max diff: Lambert (HRRR) \(maxHRRR) deg, lat/lon (GFS) \(maxGFS) deg")
    }

    @Test func nearestPointMatchesEccodes() throws {
        for name in GRIB2Fixtures.all {
            let file = try GRIB2File(data: GRIB2Fixtures.data(name)), ref = try GRIB2Fixtures.reference(name)
            let p = ref.testPoint
            for (f, m) in zip(file.fields, ref.messages) {
                #expect(f.nearestIndex(lat: p.lat, lon: p.lon) == m.nearest.index, "\(name) message \(f.messageIndex)")
                // Callers pass -180...180 or 0...360 alike.
                #expect(f.nearestIndex(lat: p.lat, lon: p.lon + 360) == m.nearest.index)
                let v = f.value(atLat: p.lat, lon: p.lon, interpolation: .nearest)
                #expect(v.map { abs($0 - m.nearest.value) <= 1e-5 * max(1, abs($0)) } ?? m.nearest.value.isNaN)
            }
        }
    }

    @Test func bilinearAgainstIndependentComputation() throws {
        var worst = 0.0
        for name in GRIB2Fixtures.gfs {
            let file = try GRIB2File(data: GRIB2Fixtures.data(name)), ref = try GRIB2Fixtures.reference(name)
            let p = ref.testPoint
            for (f, m) in zip(file.fields, ref.messages) {
                guard let expected = m.bilinear else { Issue.record("no reference bilinear in \(name)"); continue }
                guard let got = f.value(atLat: p.lat, lon: p.lon, interpolation: .bilinear) else {
                    Issue.record("\(name) message \(f.messageIndex): nil bilinear"); continue
                }
                worst = max(worst, abs(got - expected) / max(1, abs(expected)))
                #expect(abs(got - expected) <= 1e-6 * max(1, abs(expected)), "\(name) message \(f.messageIndex)")
            }
        }
        print("GRIB2 GFS bilinear max relative diff vs python: \(worst)")
    }

    @Test func bilinearExactAtNodesAndBoundedBetween() throws {
        for name in GRIB2Fixtures.all {
            let file = try GRIB2File(data: GRIB2Fixtures.data(name))
            for f in file.fields.prefix(4) {
                let n = f.grid.pointCount
                for k in stride(from: 0, to: n, by: max(1, n / 37)) {
                    guard let lat = f.latitude(ofIndex: k), let lon = f.longitude(ofIndex: k) else { continue }
                    let v = f.value(atLat: lat, lon: lon, interpolation: .bilinear)
                    #expect(v.map { abs($0 - f.values[k]) <= 1e-6 * max(1, abs(f.values[k])) } == true, "\(name) node \(k)")
                    #expect(f.nearestIndex(lat: lat, lon: lon) == k)
                }
                // Points between nodes lie within the min/max of the four neighbours.
                for step in 0..<40 {
                    guard let a = f.latitude(ofIndex: step * n / 41 + 1), let b = f.longitude(ofIndex: step * n / 41 + 1),
                        let a2 = f.latitude(ofIndex: step * n / 43 + 2), let b2 = f.longitude(ofIndex: step * n / 43 + 2)
                    else { continue }
                    let lat = (a + a2) / 2, lon = (b + b2) / 2
                    guard let s = f.grid.bilinearStencil(lat: lat, lon: lon), let v = f.value(atLat: lat, lon: lon) else { continue }
                    let nb = s.indices.map { f.values[$0] }
                    #expect(v >= nb.min()! - 1e-9 && v <= nb.max()! + 1e-9, "\(name) bilinear outside neighbour range")
                    #expect(abs(s.weights.reduce(0, +) - 1) < 1e-12)
                }
                #expect(f.value(atLat: 0, lon: 0) == nil)
                #expect(f.value(atLat: 89, lon: 100, interpolation: .nearest) == nil)
            }
        }
    }

    @Test func queryAPIFindsCloudAndPrecipFields() throws {
        let hrrr = try GRIB2File(data: GRIB2Fixtures.data("hrrr-W-20261122t12z-f06"))
        #expect(hrrr.field(parameter: .lowCloudCover, level: .lowCloudLayer, forecastHour: 6) != nil)
        #expect(hrrr.field(parameter: .temperature, level: .height2m, forecastHour: 6)?.product.firstSurface?.value == 2)
        #expect(hrrr.field(parameter: .uWind, level: .height10m, forecastHour: 6) != nil)
        #expect(hrrr.field(parameter: .massDensity, level: .height8m, forecastHour: 6) != nil)
        #expect(hrrr.field(parameter: .columnMassDensity, level: .entireAtmosphereSingleLayer, forecastHour: 6) != nil)
        #expect(hrrr.field(parameter: .aerosolOpticalThickness, level: .entireAtmosphereSingleLayer, forecastHour: 6) != nil)
        #expect(hrrr.field(parameter: .totalPrecipitation, level: .surface, forecastHour: 6, statistical: true) != nil)
        #expect(hrrr.field(parameter: .totalPrecipitation, level: .surface, forecastHour: 6, statistical: false) == nil)
        #expect(hrrr.field(parameter: .lowCloudCover, level: .lowCloudLayer, forecastHour: 5) == nil)
        #expect(hrrr.field(parameter: .temperature, level: .height10m, forecastHour: 6) == nil)

        let gfs = try GRIB2File(data: GRIB2Fixtures.data("gfs-W-20261122t06z-f006"))
        let inst = gfs.field(parameter: .lowCloudCover, level: .lowCloudLayer, forecastHour: 6, statistical: false)
        let avg = gfs.field(parameter: .lowCloudCover, level: .lowCloudLayer, forecastHour: 6, statistical: true)
        #expect(inst != nil && avg != nil && inst?.isStatistical == false && avg?.product.statistical?.isAverage == true)
        #expect(avg?.product.statistical?.rangeHours == 6)
        #expect(gfs.field(parameter: .totalCloudCover, level: .entireAtmosphere, forecastHour: 6, statistical: true) != nil)
        #expect(gfs.field(parameter: .visibility, level: .surface, forecastHour: 6)?.validTime
            == gfs.fields.first?.identification.referenceTime.addingTimeInterval(6 * 3600))
    }

    @Test func printTemplatesSeen() throws {
        for name in GRIB2Fixtures.all {
            let file = try GRIB2File(data: GRIB2Fixtures.data(name))
            let pdt = Set(file.fields.map(\.product.templateNumber)).sorted(), gdt = Set(file.fields.map(\.grid.templateNumber)).sorted()
            print("GRIB2 \(name): \(file.fields.count) fields, grid templates \(gdt), product templates \(pdt), simple packing (5.0) only, failures \(file.failures.count)")
        }
    }
}
