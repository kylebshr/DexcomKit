import Foundation

/// A single glucose reading from the sensor, either real-time or recovered
/// from the sensor's backfill buffer.
public struct GlucoseReading: Sendable, Hashable, Codable, Identifiable {
    /// Stable identity: the sensor name plus the reading's offset from
    /// activation, which uniquely identifies a reading within a session.
    public var id: String { "\(sensorName)-\(timestampOffset)" }

    /// Glucose in mg/dL; `nil` when the sensor could not produce a value.
    public let glucose: Int?

    /// Rate of change in mg/dL per minute; `nil` when unavailable.
    public let trendRate: Double?

    /// Wall-clock time the reading was taken.
    public let date: Date

    /// Seconds since sensor activation when the reading was taken. Stable
    /// across reconnections and backfill, unlike `date`, which is derived
    /// from the phone's clock.
    public let timestampOffset: UInt32

    /// The reading's sequence number; `nil` for backfilled readings, which
    /// don't carry one.
    public let sequence: UInt16?

    /// The sensor algorithm state at the time of the reading.
    public let algorithmState: AlgorithmState

    /// Whether the sensor marked this value for display/calibration only.
    public let isDisplayOnly: Bool

    /// Whether this reading was recovered from the sensor's backfill buffer
    /// rather than delivered in real time.
    public let isBackfilled: Bool

    /// The sensor's predicted glucose in mg/dL; real-time readings only.
    public let predictedGlucose: Int?

    /// The advertised name of the sensor that produced this reading.
    public let sensorName: String

    /// The display bucket for ``trendRate``.
    public var trendArrow: TrendArrow? { TrendArrow(rate: trendRate) }

    /// Whether this value is reliable enough to act on: a glucose value is
    /// present, the algorithm reports ``AlgorithmState/State/ok``, and the
    /// value isn't display-only.
    ///
    /// > Important: DexcomKit is not a medical device. This flag mirrors the
    /// > sensor's own reliability reporting; it is not a treatment
    /// > recommendation.
    public var isUsableForTreatment: Bool {
        glucose != nil && algorithmState.isUsable && !isDisplayOnly
    }

    public init(
        glucose: Int?,
        trendRate: Double?,
        date: Date,
        timestampOffset: UInt32,
        sequence: UInt16?,
        algorithmState: AlgorithmState,
        isDisplayOnly: Bool,
        isBackfilled: Bool,
        predictedGlucose: Int?,
        sensorName: String
    ) {
        self.glucose = glucose
        self.trendRate = trendRate
        self.date = date
        self.timestampOffset = timestampOffset
        self.sequence = sequence
        self.algorithmState = algorithmState
        self.isDisplayOnly = isDisplayOnly
        self.isBackfilled = isBackfilled
        self.predictedGlucose = predictedGlucose
        self.sensorName = sensorName
    }
}

extension GlucoseReading {
    /// Builds a reading from a real-time glucose message, anchoring its
    /// activation-relative timestamp to a wall-clock activation date.
    init(message: GlucoseMessage, sensorName: String, activationDate: Date) {
        self.init(
            glucose: message.glucose.map(Int.init),
            trendRate: message.trendRate,
            date: activationDate.addingTimeInterval(TimeInterval(message.glucoseTimestamp)),
            timestampOffset: message.glucoseTimestamp,
            sequence: message.sequence,
            algorithmState: message.algorithmState,
            isDisplayOnly: message.isDisplayOnly,
            isBackfilled: false,
            predictedGlucose: message.predictedGlucose.map(Int.init),
            sensorName: sensorName
        )
    }

    /// Builds a reading from a backfill record.
    init(record: BackfillRecord, sensorName: String, activationDate: Date) {
        self.init(
            glucose: record.glucose.map(Int.init),
            trendRate: record.trendRate,
            date: activationDate.addingTimeInterval(TimeInterval(record.timestamp)),
            timestampOffset: record.timestamp,
            sequence: nil,
            algorithmState: record.algorithmState,
            isDisplayOnly: record.isDisplayOnly,
            isBackfilled: true,
            predictedGlucose: nil,
            sensorName: sensorName
        )
    }
}
