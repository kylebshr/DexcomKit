import Testing

@testable import DexcomKit

@Suite struct AdoptionPolicyTests {
    @Test func automaticAdoptsAnyG7FamilySensor() {
        for name in ["DXCM8T", "DX02CD"] {
            #expect(
                AdoptionPolicy.shouldConnect(
                    advertisedName: name, selection: .automatic,
                    followedSensorName: nil, sessionHasEnded: false))
        }
    }

    @Test func rejectsNonG7Names() {
        // DX01 (original Dexcom One) speaks the G6 protocol, not this one.
        for name in ["Flex", "dxcm8T", "XDXCM8T", "DX01AB", ""] {
            #expect(
                !AdoptionPolicy.shouldConnect(
                    advertisedName: name, selection: .automatic,
                    followedSensorName: nil, sessionHasEnded: false),
                "name \(name)")
        }
        #expect(
            !AdoptionPolicy.shouldConnect(
                advertisedName: nil, selection: .automatic,
                followedSensorName: nil, sessionHasEnded: false))
    }

    @Test func nameSuffixMatchesCaseInsensitively() {
        #expect(
            AdoptionPolicy.shouldConnect(
                advertisedName: "DXCM8T", selection: .nameSuffix("8t"),
                followedSensorName: nil, sessionHasEnded: false))
        #expect(
            !AdoptionPolicy.shouldConnect(
                advertisedName: "DXCM9Q", selection: .nameSuffix("8T"),
                followedSensorName: nil, sessionHasEnded: false))
    }

    @Test func emptySuffixNeverMatches() {
        #expect(
            !AdoptionPolicy.shouldConnect(
                advertisedName: "DXCM8T", selection: .nameSuffix(""),
                followedSensorName: nil, sessionHasEnded: false))
    }

    @Test func followedSensorExcludesOthers() {
        #expect(
            AdoptionPolicy.shouldConnect(
                advertisedName: "DXCM8T", selection: .automatic,
                followedSensorName: "DXCM8T", sessionHasEnded: false))
        #expect(
            !AdoptionPolicy.shouldConnect(
                advertisedName: "DXCM9Q", selection: .automatic,
                followedSensorName: "DXCM8T", sessionHasEnded: false))
    }

    @Test func endedSessionReopensAdoption() {
        #expect(
            AdoptionPolicy.shouldConnect(
                advertisedName: "DXCM9Q", selection: .automatic,
                followedSensorName: "DXCM8T", sessionHasEnded: true))
        // The suffix filter still applies to replacements.
        #expect(
            !AdoptionPolicy.shouldConnect(
                advertisedName: "DXCM9Q", selection: .nameSuffix("8T"),
                followedSensorName: "DXCM8T", sessionHasEnded: true))
    }
}
