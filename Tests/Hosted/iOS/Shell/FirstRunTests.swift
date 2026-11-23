import Foundation
import Testing
import IterFeatures
@testable import Iter

/// The first-run guide: short, shown once, forced or suppressed by launch switch, and never part of a test or screenshot run.
@MainActor
@Suite struct FirstRunTests {
    @Test func theGuideIsAtMostThreePages() {
        #expect(FirstRunPage.allCases.count <= 3)
        #expect(FirstRunPage.allCases.map(\.rawValue) == [0, 1, 2])
    }

    @Test func theSwitchParses() {
        #expect(IOSLaunchSwitches(arguments: ["-IterFirstRun", "YES"]).firstRun == true)
        #expect(IOSLaunchSwitches(arguments: ["-IterFirstRun", "NO"]).firstRun == false)
        #expect(IOSLaunchSwitches(arguments: ["Iter"]).firstRun == nil)
    }

    @Test func anInMemoryRunNeverShowsItUnlessForced() throws {
        let shell = try makeTestShell()
        shell.apply(IOSLaunchSwitches())
        #expect(!shell.showsFirstRun)
        shell.apply(IOSLaunchSwitches(arguments: ["-IterFirstRun", "YES"]))
        #expect(shell.showsFirstRun)
        shell.apply(IOSLaunchSwitches(arguments: ["-IterFirstRun", "NO"]))
        #expect(!shell.showsFirstRun)
    }

    @Test func closingItRemembersItWasSeen() throws {
        let shell = try makeTestShell()
        shell.apply(IOSLaunchSwitches(arguments: ["-IterFirstRun", "YES"]))
        shell.dismissFirstRun()
        #expect(!shell.showsFirstRun)
        #expect(shell.find.notices.hasSeen(.firstRunGuide))
    }
}
