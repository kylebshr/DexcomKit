import Testing

@testable import DexcomKit

@Suite struct DexcomKitInfoTests {
    @Test func versionIsNonEmpty() {
        #expect(!DexcomKitInfo.version.isEmpty)
    }
}
