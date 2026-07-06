import Foundation

/// A real-time glucose reading (opcode `0x4E`) from the control
/// characteristic.
///
/// Layout (all integers little-endian):
/// ```
/// [0]      opcode 0x4E
/// [1]      status; only 0x00 is a valid reading
/// [2..<6]  message timestamp — seconds since sensor activation
/// [6..<8]  sequence number
/// [10..<12] age — seconds between the reading and its transmission
/// [12..<14] glucose (0xFFFF = none; value masked with 0x0FFF), mg/dL
/// [14]     algorithm state
/// [15]     trend rate ×10, Int8 (0x7F = none), mg/dL/min
/// [16..<18] predicted glucose (0xFFFF = none; masked with 0x0FFF), mg/dL
/// [18]     flags; bit 0x10 = display-only calibration value
/// ```
struct GlucoseMessage: Sendable, Equatable {
    /// Seconds since sensor activation when this message was sent.
    let messageTimestamp: UInt32
    let sequence: UInt16
    /// Seconds between the reading being taken and this message.
    let age: UInt16
    /// Glucose in mg/dL; `nil` when the sensor reported no value.
    let glucose: UInt16?
    let algorithmState: AlgorithmState
    /// Rate of change in mg/dL/min; `nil` when the sensor reported no trend.
    let trendRate: Double?
    /// Predicted glucose in mg/dL; `nil` when unavailable.
    let predictedGlucose: UInt16?
    /// Whether this value is for display/calibration only.
    let isDisplayOnly: Bool

    /// Seconds since sensor activation when the reading was actually taken.
    var glucoseTimestamp: UInt32 {
        messageTimestamp >= UInt32(age) ? messageTimestamp - UInt32(age) : 0
    }

    init?(data: Data) {
        guard
            data.count >= 19,
            data.byte(at: 0) == G7Opcode.glucose,
            data.byte(at: 1) == 0x00,
            let messageTimestamp = data.uint32(at: 2),
            let sequence = data.uint16(at: 6),
            let age = data.uint16(at: 10),
            let rawGlucose = data.uint16(at: 12),
            let stateByte = data.byte(at: 14),
            let trendByte = data.byte(at: 15),
            let rawPredicted = data.uint16(at: 16),
            let flags = data.byte(at: 18)
        else { return nil }

        self.messageTimestamp = messageTimestamp
        self.sequence = sequence
        self.age = age
        glucose = rawGlucose == 0xFFFF ? nil : rawGlucose & 0x0FFF
        algorithmState = AlgorithmState(rawValue: stateByte)
        trendRate = trendByte == 0x7F ? nil : Double(Int8(bitPattern: trendByte)) / 10.0
        predictedGlucose = rawPredicted == 0xFFFF ? nil : rawPredicted & 0x0FFF
        isDisplayOnly = flags & 0x10 != 0
    }
}
