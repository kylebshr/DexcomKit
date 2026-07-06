import Foundation
import Testing

@testable import DexcomKit

@Suite struct AlgorithmStateTests {
    @Test func knownRawValuesMap() {
        for state in AlgorithmState.State.allCases {
            #expect(AlgorithmState(rawValue: state.rawValue) == .known(state))
        }
    }

    @Test func unknownRawValuesArePreserved() {
        #expect(AlgorithmState(rawValue: 99) == .unknown(99))
        #expect(AlgorithmState(rawValue: 0) == .unknown(0))
        #expect(AlgorithmState(rawValue: 23) == .unknown(23))  // gap in known values
        #expect(AlgorithmState(rawValue: 99).rawValue == 99)
    }

    @Test func rawValueRoundTrips() {
        for raw in UInt8.min...UInt8.max {
            #expect(AlgorithmState(rawValue: raw).rawValue == raw)
        }
    }

    @Test func onlyOKIsUsable() {
        for state in AlgorithmState.State.allCases {
            #expect(AlgorithmState.known(state).isUsable == (state == .ok))
        }
        #expect(!AlgorithmState.unknown(99).isUsable)
    }

    @Test func warmupIsDetected() {
        #expect(AlgorithmState.known(.warmup).isInWarmup)
        #expect(!AlgorithmState.known(.ok).isInWarmup)
    }

    @Test func sensorFailureStates() {
        let failed: [AlgorithmState.State] = [
            .sensorFailedDueToCountsAberration,
            .sensorFailedDueToResidualAberration,
            .sessionFailedDueToUnrecoverableError,
            .sessionFailedDueToTransmitterError,
            .sensorFailedDueToProgressiveSensorDecline,
            .sensorFailedDueToHighCountsAberration,
            .sensorFailedDueToLowCountsAberration,
            .sensorFailedDueToRestart,
            .sensorFailed,
        ]
        for state in AlgorithmState.State.allCases {
            #expect(
                AlgorithmState.known(state).indicatesSensorFailure == failed.contains(state),
                "state \(state)")
        }
    }

    @Test func sessionEndStates() {
        let ended: [AlgorithmState.State] = [.stopped, .sessionExpired, .expired, .sessionEnded]
        for state in AlgorithmState.State.allCases {
            #expect(
                AlgorithmState.known(state).indicatesSessionEnd == ended.contains(state),
                "state \(state)")
        }
    }

    @Test func codableRoundTrips() throws {
        for state in [AlgorithmState.known(.ok), .known(.warmup), .unknown(42)] {
            let encoded = try JSONEncoder().encode(state)
            let decoded = try JSONDecoder().decode(AlgorithmState.self, from: encoded)
            #expect(decoded == state)
        }
    }
}
