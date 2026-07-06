import Foundation

/// One historical reading from the backfill characteristic.
///
/// Backfill notifications carry one or more consecutive 9-byte records:
/// ```
/// [0..<3]  timestamp — seconds since sensor activation (24-bit LE)
/// [4..<6]  glucose (0xFFFF = none; masked with 0x0FFF), mg/dL
/// [6]      algorithm state
/// [7]      flags; bit 0x10 = display-only calibration value
/// [8]      trend rate ×10, Int8 (0x7F = none), mg/dL/min
/// ```
struct BackfillRecord: Sendable, Equatable {
    static let byteCount = 9

    /// Seconds since sensor activation when the reading was taken.
    let timestamp: UInt32
    /// Glucose in mg/dL; `nil` when the sensor reported no value.
    let glucose: UInt16?
    let algorithmState: AlgorithmState
    /// Whether this value is for display/calibration only.
    let isDisplayOnly: Bool
    /// Rate of change in mg/dL/min; `nil` when the sensor reported no trend.
    let trendRate: Double?

    init?(data: Data) {
        guard
            data.count == Self.byteCount,
            let timestamp = data.uint24(at: 0),
            let rawGlucose = data.uint16(at: 4),
            let stateByte = data.byte(at: 6),
            let flags = data.byte(at: 7),
            let trendByte = data.byte(at: 8)
        else { return nil }

        self.timestamp = timestamp
        glucose = rawGlucose == 0xFFFF ? nil : rawGlucose & 0x0FFF
        algorithmState = AlgorithmState(rawValue: stateByte)
        isDisplayOnly = flags & 0x10 != 0
        trendRate = trendByte == 0x7F ? nil : Double(Int8(bitPattern: trendByte)) / 10.0
    }
}
