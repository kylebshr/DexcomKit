/// The sensor's algorithm state, carried in every real-time and backfilled
/// reading.
///
/// The G7 firmware can report states this package doesn't know about, so the
/// raw byte is preserved via ``unknown(_:)`` rather than dropped. Only
/// ``State/ok`` indicates a reliable glucose value — see ``isUsable``.
public enum AlgorithmState: Sendable, Hashable, Codable {
    /// A state this package recognizes.
    case known(State)
    /// A raw state byte this package doesn't recognize.
    case unknown(UInt8)

    /// Algorithm states with known meanings, as documented by
    /// LoopKit/G7SensorKit.
    public enum State: UInt8, Sendable, Hashable, Codable, CaseIterable {
        case stopped = 1
        case warmup = 2
        case excessNoise = 3
        case firstOfTwoBGsNeeded = 4
        case secondOfTwoBGsNeeded = 5
        /// The only state in which glucose values are reliable.
        case ok = 6
        case needsCalibration = 7
        case calibrationError1 = 8
        case calibrationError2 = 9
        case calibrationLinearityFitFailure = 10
        case sensorFailedDueToCountsAberration = 11
        case sensorFailedDueToResidualAberration = 12
        case outOfCalibrationDueToOutlier = 13
        case outlierCalibrationRequest = 14
        case sessionExpired = 15
        case sessionFailedDueToUnrecoverableError = 16
        case sessionFailedDueToTransmitterError = 17
        case temporarySensorIssue = 18
        case sensorFailedDueToProgressiveSensorDecline = 19
        case sensorFailedDueToHighCountsAberration = 20
        case sensorFailedDueToLowCountsAberration = 21
        case sensorFailedDueToRestart = 22
        case expired = 24
        case sensorFailed = 25
        case sessionEnded = 26
    }

    /// Creates a state from the raw byte in a glucose or backfill message.
    public init(rawValue: UInt8) {
        if let state = State(rawValue: rawValue) {
            self = .known(state)
        } else {
            self = .unknown(rawValue)
        }
    }

    /// The raw wire value of this state.
    public var rawValue: UInt8 {
        switch self {
        case .known(let state): state.rawValue
        case .unknown(let raw): raw
        }
    }

    /// Whether glucose values reported in this state are reliable.
    ///
    /// `true` only for ``State/ok``.
    public var isUsable: Bool {
        self == .known(.ok)
    }

    /// Whether the sensor is still warming up after activation.
    public var isInWarmup: Bool {
        self == .known(.warmup)
    }

    /// Whether this state indicates the sensor hardware has failed.
    public var indicatesSensorFailure: Bool {
        switch self {
        case .known(let state):
            switch state {
            case .sensorFailedDueToCountsAberration,
                .sensorFailedDueToResidualAberration,
                .sessionFailedDueToUnrecoverableError,
                .sessionFailedDueToTransmitterError,
                .sensorFailedDueToProgressiveSensorDecline,
                .sensorFailedDueToHighCountsAberration,
                .sensorFailedDueToLowCountsAberration,
                .sensorFailedDueToRestart,
                .sensorFailed:
                true
            default:
                false
            }
        case .unknown:
            false
        }
    }

    /// Whether this state indicates the sensor session is over (expired,
    /// stopped, or ended) without necessarily being a hardware failure.
    public var indicatesSessionEnd: Bool {
        switch self {
        case .known(let state):
            switch state {
            case .stopped, .sessionExpired, .expired, .sessionEnded:
                true
            default:
                false
            }
        case .unknown:
            false
        }
    }
}
