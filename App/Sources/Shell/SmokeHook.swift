import Foundation
import IterCore
import IterFeatures

/// Filled in during integration.
enum SmokeHook {
    @MainActor static func run(_ model: AppModel) async {
        AppLaunch.log.notice("smoke: start")
    }
}
