import Foundation
import Testing
import IterSources
@testable import IterFeatures

@Suite("Legacy key carry-over at launch") struct KeyVaultLaunchTests {
    @Test func copiesOldItemsLeavesThemInPlaceAndRunsOnce() throws {
        let kc = InMemoryKeychain()
        for item in LegacyKeyMapping.items {
            try kc.write(Data("v-\(item.legacyAccount)".utf8), service: item.legacyService, account: item.legacyAccount)
        }
        let vault = KeyVault(keychain: kc)
        let first = vault.carryOverLegacyKeys()
        #expect(first.copied.count == LegacyKeyMapping.items.count && first.markerSet)
        #expect(vault.key(for: LegacyKeyMapping.windy) == "v-windy")
        // Old items are still there.
        for item in LegacyKeyMapping.items {
            #expect(try kc.read(service: item.legacyService, account: item.legacyAccount) != nil)
        }
        // A second launch reads nothing and changes nothing.
        let second = vault.carryOverLegacyKeys()
        #expect(second.alreadyMigrated && second.entries.isEmpty)
    }

    @Test func aNewKeyIsNeverOverwritten() throws {
        let kc = InMemoryKeychain()
        let vault = KeyVault(keychain: kc)
        try vault.setKey("new", for: LegacyKeyMapping.windy)
        try kc.write(Data("old".utf8), service: LegacyKeyMapping.items.first { $0.source == LegacyKeyMapping.windy }!.legacyService, account: "windy")
        vault.carryOverLegacyKeys()
        #expect(vault.key(for: LegacyKeyMapping.windy) == "new")
    }
}
