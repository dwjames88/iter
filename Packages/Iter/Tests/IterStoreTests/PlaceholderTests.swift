import Testing
import IterStore

// Smoke test: the target builds and links. Replace with real tests when the target is filled.
@Test func IterStoreLinks() {
    #expect(IterStoreModule.name == "IterStore")
}
