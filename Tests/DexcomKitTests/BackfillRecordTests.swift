import Foundation
import Testing

@testable import DexcomKit

@Suite struct BackfillRecordTests {
    @Test func parsesRealisticRecord() throws {
        let record = try #require(BackfillRecord(data: G7Fixtures.backfillRecord))
        #expect(record.timestamp == 299_700)
        #expect(record.glucose == 120)
        #expect(record.algorithmState == .known(.ok))
        #expect(!record.isDisplayOnly)
        #expect(record.trendRate == 0.1)
    }

    @Test func parsesSliceWithNonZeroStartIndex() throws {
        let record = try #require(BackfillRecord(data: G7Fixtures.backfillRecord.resliced))
        #expect(record.glucose == 120)
    }

    @Test func rejectsWrongLength() {
        #expect(BackfillRecord(data: G7Fixtures.backfillRecord.prefix(8)) == nil)
        #expect(BackfillRecord(data: G7Fixtures.backfillRecord + Data([0x00])) == nil)
        #expect(BackfillRecord(data: Data()) == nil)
    }

    @Test func missingGlucoseIsNil() throws {
        var bytes = Data(G7Fixtures.backfillRecord)
        bytes[4] = 0xFF
        bytes[5] = 0xFF
        let record = try #require(BackfillRecord(data: bytes))
        #expect(record.glucose == nil)
    }

    @Test func glucoseHighBitsAreMasked() throws {
        var bytes = Data(G7Fixtures.backfillRecord)
        bytes[4] = 0x78
        bytes[5] = 0x30
        let record = try #require(BackfillRecord(data: bytes))
        #expect(record.glucose == 0x078)
    }

    @Test func missingTrendIsNil() throws {
        var bytes = Data(G7Fixtures.backfillRecord)
        bytes[8] = 0x7F
        let record = try #require(BackfillRecord(data: bytes))
        #expect(record.trendRate == nil)
    }

    @Test func timestampHighByteParses() throws {
        var bytes = Data(G7Fixtures.backfillRecord)
        bytes[0] = 0x00
        bytes[1] = 0x00
        bytes[2] = 0x80
        let record = try #require(BackfillRecord(data: bytes))
        #expect(record.timestamp == 0x800000)
    }

    @Test func displayOnlyFlagParses() throws {
        var bytes = Data(G7Fixtures.backfillRecord)
        bytes[7] = 0x10
        let record = try #require(BackfillRecord(data: bytes))
        #expect(record.isDisplayOnly)
    }

    @Test func unknownAlgorithmStateIsPreserved() throws {
        var bytes = Data(G7Fixtures.backfillRecord)
        bytes[6] = 42
        let record = try #require(BackfillRecord(data: bytes))
        #expect(record.algorithmState == .unknown(42))
    }
}
