import Foundation
import Testing

@testable import DexcomKit

@Suite struct SensorSessionTests {
    let activation = Date(timeIntervalSince1970: 1_750_000_000)

    @Test func defaultsApplyWithoutExtendedVersion() {
        let session = SensorSession(
            sensorName: "DXCM8T", activationDate: activation, extendedVersion: nil)

        #expect(session.warmupEndDate == activation.addingTimeInterval(27 * 60))
        #expect(session.expirationDate == activation.addingTimeInterval(10 * 24 * 60 * 60))
        #expect(
            session.gracePeriodEndDate
                == session.expirationDate.addingTimeInterval(12 * 60 * 60))
        #expect(session.algorithmVersion == nil)
    }

    @Test func extendedVersionOverridesDefaults() throws {
        let version = try #require(
            ExtendedVersionMessage(data: G7Fixtures.extendedVersion15Day))
        let session = SensorSession(
            sensorName: "DXCM8T", activationDate: activation, extendedVersion: version)

        #expect(session.warmupEndDate == activation.addingTimeInterval(1620))
        // The sensor's reported length (1 339 200 s) includes the 12 h grace
        // period: expiration at 15 days, grace running until 15.5.
        #expect(session.expirationDate == activation.addingTimeInterval(1_296_000))
        #expect(session.gracePeriodEndDate == activation.addingTimeInterval(1_339_200))
        #expect(session.algorithmVersion == 0x0001_0203)
    }

    @Test func warmupAndExpiryChecks() {
        let session = SensorSession(
            sensorName: "DXCM8T", activationDate: activation, extendedVersion: nil)

        #expect(session.isInWarmup(at: activation.addingTimeInterval(60)))
        #expect(!session.isInWarmup(at: activation.addingTimeInterval(28 * 60)))
        #expect(!session.isExpired(at: activation.addingTimeInterval(24 * 60 * 60)))
        #expect(session.isExpired(at: activation.addingTimeInterval(11 * 24 * 60 * 60)))
    }

    @Test func codableRoundTrips() throws {
        let session = SensorSession(
            sensorName: "DXCM8T", activationDate: activation, extendedVersion: nil)
        let decoded = try JSONDecoder().decode(
            SensorSession.self, from: JSONEncoder().encode(session))
        #expect(decoded == session)
    }
}
