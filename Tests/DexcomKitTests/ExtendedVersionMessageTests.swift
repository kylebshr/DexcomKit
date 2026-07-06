import Foundation
import Testing

@testable import DexcomKit

@Suite struct ExtendedVersionMessageTests {
    @Test func parsesTenDaySensor() throws {
        let message = try #require(ExtendedVersionMessage(data: G7Fixtures.extendedVersion10Day))
        #expect(message.sessionLength == 864_000)  // 10 days
        #expect(message.warmupLength == 1620)  // 27 minutes
        #expect(message.algorithmVersion == 0x0001_0203)
        #expect(message.hardwareVersion == 1)
        #expect(message.maxLifetimeDays == 12)
    }

    @Test func parsesFifteenDaySensor() throws {
        let message = try #require(ExtendedVersionMessage(data: G7Fixtures.extendedVersion15Day))
        #expect(message.sessionLength == 1_296_000)  // 15 days
        #expect(message.maxLifetimeDays == 17)
    }

    @Test func parsesSliceWithNonZeroStartIndex() throws {
        let message = try #require(
            ExtendedVersionMessage(data: G7Fixtures.extendedVersion10Day.resliced))
        #expect(message.sessionLength == 864_000)
    }

    @Test func rejectsShortData() {
        #expect(ExtendedVersionMessage(data: G7Fixtures.extendedVersion10Day.prefix(14)) == nil)
    }

    @Test func rejectsWrongOpcode() {
        var bytes = Data(G7Fixtures.extendedVersion10Day)
        bytes[0] = 0x4E
        #expect(ExtendedVersionMessage(data: bytes) == nil)
    }

    @Test func requestIsSingleOpcodeByte() {
        #expect(ExtendedVersionMessage.request == Data([0x52]))
    }
}
