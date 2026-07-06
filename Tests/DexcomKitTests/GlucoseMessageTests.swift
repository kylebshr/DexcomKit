import Foundation
import Testing

@testable import DexcomKit

@Suite struct GlucoseMessageTests {
    @Test func parsesRealisticMessage() throws {
        let message = try #require(GlucoseMessage(data: G7Fixtures.glucose))
        #expect(message.messageTimestamp == 300_000)
        #expect(message.sequence == 1000)
        #expect(message.age == 6)
        #expect(message.glucose == 113)
        #expect(message.algorithmState == .known(.ok))
        #expect(message.trendRate == -0.2)
        #expect(message.predictedGlucose == 110)
        #expect(!message.isDisplayOnly)
    }

    @Test func glucoseTimestampSubtractsAge() throws {
        let message = try #require(GlucoseMessage(data: G7Fixtures.glucose))
        #expect(message.glucoseTimestamp == 300_000 - 6)
    }

    @Test func parsesSliceWithNonZeroStartIndex() throws {
        let message = try #require(GlucoseMessage(data: G7Fixtures.glucose.resliced))
        #expect(message.glucose == 113)
    }

    @Test func missingGlucoseIsNil() throws {
        var bytes = Data(G7Fixtures.glucose)
        bytes[12] = 0xFF
        bytes[13] = 0xFF
        let message = try #require(GlucoseMessage(data: bytes))
        #expect(message.glucose == nil)
    }

    @Test func glucoseHighBitsAreMasked() throws {
        var bytes = Data(G7Fixtures.glucose)
        // Raw 0x1071; masking with 0x0FFF must yield 0x071 = 113.
        bytes[12] = 0x71
        bytes[13] = 0x10
        let message = try #require(GlucoseMessage(data: bytes))
        #expect(message.glucose == 113)
    }

    @Test func missingTrendIsNil() throws {
        var bytes = Data(G7Fixtures.glucose)
        bytes[15] = 0x7F
        let message = try #require(GlucoseMessage(data: bytes))
        #expect(message.trendRate == nil)
    }

    @Test func positiveTrendParses() throws {
        var bytes = Data(G7Fixtures.glucose)
        bytes[15] = 25  // +2.5 mg/dL/min
        let message = try #require(GlucoseMessage(data: bytes))
        #expect(message.trendRate == 2.5)
    }

    @Test func stronglyNegativeTrendParses() throws {
        var bytes = Data(G7Fixtures.glucose)
        bytes[15] = UInt8(bitPattern: -30)  // -3.0 mg/dL/min
        let message = try #require(GlucoseMessage(data: bytes))
        #expect(message.trendRate == -3.0)
    }

    @Test func missingPredictedGlucoseIsNil() throws {
        var bytes = Data(G7Fixtures.glucose)
        bytes[16] = 0xFF
        bytes[17] = 0xFF
        let message = try #require(GlucoseMessage(data: bytes))
        #expect(message.predictedGlucose == nil)
    }

    @Test func displayOnlyFlagParses() throws {
        var bytes = Data(G7Fixtures.glucose)
        bytes[18] = 0x10
        let message = try #require(GlucoseMessage(data: bytes))
        #expect(message.isDisplayOnly)
    }

    @Test func unknownAlgorithmStateIsPreserved() throws {
        var bytes = Data(G7Fixtures.glucose)
        bytes[14] = 99
        let message = try #require(GlucoseMessage(data: bytes))
        #expect(message.algorithmState == .unknown(99))
    }

    @Test func rejectsWrongOpcode() {
        var bytes = Data(G7Fixtures.glucose)
        bytes[0] = 0x4F
        #expect(GlucoseMessage(data: bytes) == nil)
    }

    @Test func rejectsNonZeroStatus() {
        var bytes = Data(G7Fixtures.glucose)
        bytes[1] = 0x01
        #expect(GlucoseMessage(data: bytes) == nil)
    }

    @Test func rejectsShortData() {
        #expect(GlucoseMessage(data: G7Fixtures.glucose.prefix(18)) == nil)
        #expect(GlucoseMessage(data: Data()) == nil)
    }

    @Test func acceptsLongerData() {
        let padded = G7Fixtures.glucose + Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        #expect(GlucoseMessage(data: padded) != nil)
    }
}
