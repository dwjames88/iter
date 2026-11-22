import Foundation
import IterModel
import Testing
@testable import IterDiscovery

@Suite("BasicQueryParser")
struct BasicQueryParserTests {
    @Test func viewpointsNearLonePine() {
        let p = BasicQueryParser.parse("viewpoints near Lone Pine, California")
        #expect(p.features == [.viewpoint])
        #expect(p.areaText == "Lone Pine, California")
        #expect(p.areaMode == .named)
        #expect(p.windows.isEmpty)
    }

    @Test func waterfallsInYosemite() {
        let p = BasicQueryParser.parse("waterfalls in Yosemite")
        #expect(p.features == [.waterfall])
        #expect(p.areaText == "Yosemite")
        #expect(p.areaMode == .named)
    }

    @Test func sunriseLakesNearMammoth() {
        let p = BasicQueryParser.parse("sunrise lakes near Mammoth")
        #expect(p.features == [.lake])
        #expect(Set(p.windows) == [.goldenMorning, .blueMorning])
        #expect(p.areaText == "Mammoth")
    }

    @Test func nearMe() {
        for text in ["viewpoints near me", "waterfalls around here", "peaks nearby", "Lakes close to me"] {
            let p = BasicQueryParser.parse(text, hasMapRegion: true)
            #expect(p.areaMode == .nearMe, "\(text)")
            #expect(p.areaText == nil)
            #expect(!p.features.isEmpty)
        }
    }

    @Test func thisAreaUsesTheMapWhenThereIsOne() {
        #expect(BasicQueryParser.parse("waterfalls in this area", hasMapRegion: true).areaMode == .mapArea)
        #expect(BasicQueryParser.parse("waterfalls here", hasMapRegion: true).areaMode == .mapArea)
        #expect(BasicQueryParser.parse("waterfalls in this area", hasMapRegion: false).areaMode == .nearMe)
        #expect(BasicQueryParser.parse("waterfalls", hasMapRegion: true).areaMode == .mapArea)
        #expect(BasicQueryParser.parse("waterfalls", hasMapRegion: false).areaMode == .nearMe)
    }

    @Test func driveTime() {
        #expect(BasicQueryParser.parse("waterfalls within 2 hours of Bishop").maxDriveMinutes == 120)
        #expect(BasicQueryParser.parse("waterfalls within 2 hours of Bishop").areaText == "Bishop")
        #expect(BasicQueryParser.parse("lakes within 90 minutes of Reno").maxDriveMinutes == 90)
        #expect(BasicQueryParser.parse("peaks near me within an hour").maxDriveMinutes == 60)
        #expect(BasicQueryParser.parse("peaks, 3 hour drive from Denver").maxDriveMinutes == 180)
        #expect(BasicQueryParser.parse("arches in Moab").maxDriveMinutes == nil)
    }

    @Test func severalFeaturesAndLight() {
        let p = BasicQueryParser.parse("waterfalls and lakes at golden hour in Yosemite National Park")
        #expect(p.features == [.waterfall, .lake])
        #expect(Set(p.windows) == [.goldenMorning, .goldenEvening])
        #expect(p.areaText == "Yosemite National Park")
    }

    @Test func areaWithoutPreposition() {
        let p = BasicQueryParser.parse("Yosemite waterfalls")
        #expect(p.features == [.waterfall])
        #expect(p.areaText == "Yosemite")
        #expect(BasicQueryParser.parse("Mesa Arch").areaText != nil || BasicQueryParser.parse("Mesa Arch").features == [.arch])
    }

    @Test func dateAndExclusions() {
        let p = BasicQueryParser.parse("sunset viewpoints near Page this weekend without crowds")
        #expect(p.dateHint == "this weekend")
        #expect(p.exclude == ["crowds"])
        #expect(p.areaText == "Page")
    }

    @Test func keywordsAreCappedAndPlain() {
        let p = BasicQueryParser.parse("moody misty quiet foggy lonely dramatic stormy cinematic viewpoints in Big Sur")
        #expect(p.keywords.count <= QueryPlan.maximumKeywords)
        #expect(!p.keywords.isEmpty)
        #expect(p.features == [.viewpoint])
    }

    @Test func qualifiersAreNotPartOfTheArea() {
        #expect(BasicQueryParser.parse("lighthouses in Maine for sunrise").areaText == "Maine")
        #expect(BasicQueryParser.parse("lighthouses on the Oregon coast").areaText == "Oregon coast")
    }

    @Test func neverFabricatesAPlanFromNothing() {
        let p = BasicQueryParser.parse("   ", hasMapRegion: false)
        #expect(p.features.isEmpty && p.areaText == nil)
    }

    @Test func intentClassifier() {
        #expect(FindIntent.classify("waterfalls near Lone Pine at sunrise") == .ask)
        #expect(FindIntent.classify("Mesa Arch") == .place)
        #expect(FindIntent.classify("what is near me?") == .ask)
    }
}
