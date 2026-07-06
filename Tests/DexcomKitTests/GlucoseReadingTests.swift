import Foundation
import Testing

@testable import DexcomKit

@Suite struct GlucoseReadingTests {
    let activation = Date(timeIntervalSince1970: 1_750_000_000)

    @Test func buildsFromRealTimeMessage() throws {
        let message = try #require(GlucoseMessage(data: G7Fixtures.glucose))
        let reading = GlucoseReading(
            message: message, sensorName: "DXCM8T", activationDate: activation)

        #expect(reading.glucose == 113)
        #expect(reading.trendRate == -0.2)
        #expect(reading.trendArrow == .steady)
        #expect(reading.sequence == 1000)
        #expect(reading.predictedGlucose == 110)
        #expect(!reading.isBackfilled)
        #expect(reading.timestampOffset == 299_994)
        // Reading time = activation + (messageTimestamp − age)
        #expect(reading.date == activation.addingTimeInterval(299_994))
        #expect(reading.sensorName == "DXCM8T")
    }

    @Test func buildsFromBackfillRecord() throws {
        let record = try #require(BackfillRecord(data: G7Fixtures.backfillRecord))
        let reading = GlucoseReading(
            record: record, sensorName: "DXCM8T", activationDate: activation)

        #expect(reading.glucose == 120)
        #expect(reading.isBackfilled)
        #expect(reading.sequence == nil)
        #expect(reading.predictedGlucose == nil)
        #expect(reading.timestampOffset == 299_700)
        #expect(reading.date == activation.addingTimeInterval(299_700))
    }

    @Test func identityIsStableAcrossSources() throws {
        let message = try #require(GlucoseMessage(data: G7Fixtures.glucose))
        let a = GlucoseReading(message: message, sensorName: "DXCM8T", activationDate: activation)
        let b = GlucoseReading(
            message: message, sensorName: "DXCM8T",
            activationDate: activation.addingTimeInterval(1))
        // Same reading anchored to slightly different clock estimates keeps
        // the same identity.
        #expect(a.id == b.id)
    }

    @Test func usableRequiresValueOKStateAndNotDisplayOnly() throws {
        let message = try #require(GlucoseMessage(data: G7Fixtures.glucose))
        let reading = GlucoseReading(
            message: message, sensorName: "DXCM8T", activationDate: activation)
        #expect(reading.isUsableForTreatment)

        var warmupBytes = Data(G7Fixtures.glucose)
        warmupBytes[14] = AlgorithmState.State.warmup.rawValue
        let warmupMessage = try #require(GlucoseMessage(data: warmupBytes))
        let warmupReading = GlucoseReading(
            message: warmupMessage, sensorName: "DXCM8T", activationDate: activation)
        #expect(!warmupReading.isUsableForTreatment)

        var displayOnlyBytes = Data(G7Fixtures.glucose)
        displayOnlyBytes[18] = 0x10
        let displayOnlyMessage = try #require(GlucoseMessage(data: displayOnlyBytes))
        let displayOnlyReading = GlucoseReading(
            message: displayOnlyMessage, sensorName: "DXCM8T", activationDate: activation)
        #expect(!displayOnlyReading.isUsableForTreatment)

        var noValueBytes = Data(G7Fixtures.glucose)
        noValueBytes[12] = 0xFF
        noValueBytes[13] = 0xFF
        let noValueMessage = try #require(GlucoseMessage(data: noValueBytes))
        let noValueReading = GlucoseReading(
            message: noValueMessage, sensorName: "DXCM8T", activationDate: activation)
        #expect(!noValueReading.isUsableForTreatment)
    }

    @Test func codableRoundTrips() throws {
        let message = try #require(GlucoseMessage(data: G7Fixtures.glucose))
        let reading = GlucoseReading(
            message: message, sensorName: "DXCM8T", activationDate: activation)
        let decoded = try JSONDecoder().decode(
            GlucoseReading.self, from: JSONEncoder().encode(reading))
        #expect(decoded == reading)
    }
}
