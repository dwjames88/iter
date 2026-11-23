import SwiftUI
import Testing
import IterUI
@testable import Iter

/// System sheets, tab bars in sheets, map tiles and glass do not draw in offscreen renders, so the phone shell is rendered as
/// the map layer plus the sheet's content laid out at the sheet's height (a rounded card over the map), per tab.
@MainActor
@Suite struct ShellSnapshotTests {
    @Test func phoneShellPerTab() async throws {
        for tab in PhoneTab.allCases {
            let shell = try makeTestShell()
            shell.tab = tab
            let scene = ZStack(alignment: .bottom) {
                PhoneMap(shell: shell)
                PhoneSheetContent(shell: shell)
                    .environment(\.isOnGlass, true)
                    .environment(shell.navigator)
                    .environment(shell.library)
                    .frame(height: 436)
                    .background(.background, in: RoundedRectangle(cornerRadius: 36, style: .continuous))
            }
            let images = try await IOSSnapshot.render(scene, name: "shell-phone-\(tab.rawValue)", size: CGSize(width: 402, height: 874))
            #expect(images.allSatisfy { !IOSSnapshot.isBlank($0) })
        }
    }

    @Test func padSplitView() async throws {
        let shell = try makeTestShell()
        let scene = PadShell(shell: shell).environment(shell.navigator).environment(shell.library)
        let images = try await IOSSnapshot.render(scene, name: "shell-pad", size: CGSize(width: 1210, height: 834))
        #expect(images.allSatisfy { !IOSSnapshot.isBlank($0) })
    }
}
