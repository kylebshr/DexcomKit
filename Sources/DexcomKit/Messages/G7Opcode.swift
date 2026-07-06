/// Opcodes observed as byte 0 of control- and authentication-characteristic
/// messages. Values match the G7 wire protocol as documented by
/// LoopKit/G7SensorKit.
enum G7Opcode {
    /// Authentication status broadcast on the authentication characteristic.
    static let authStatus: UInt8 = 0x05
    /// The sensor reports its session has been stopped.
    static let sessionStop: UInt8 = 0x28
    /// A real-time glucose reading.
    static let glucose: UInt8 = 0x4E
    /// Extended version request (write) and response (indication).
    static let extendedVersion: UInt8 = 0x52
    /// The backfill stream on the backfill characteristic is complete.
    static let backfillFinished: UInt8 = 0x59
}
