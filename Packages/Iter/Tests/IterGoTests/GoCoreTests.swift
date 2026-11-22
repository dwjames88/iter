import Foundation
import Testing
import IterGo

@Test func powerSavingRule() {
    #expect(PowerState(isLowPowerMode: true).isSaving)
    #expect(PowerState(batteryLevel: 0.15).isSaving)
    #expect(!PowerState(batteryLevel: 0.15, isCharging: true).isSaving)
    #expect(!PowerState.normal.isSaving)
}
