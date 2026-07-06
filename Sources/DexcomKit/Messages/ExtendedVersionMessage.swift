import Foundation

/// Session parameters (response to opcode `0x52`) from the control
/// characteristic.
///
/// Requested once per session after the first glucose reading; its values
/// take precedence over the package's defaults so 15-day sensors and future
/// hardware report correct lifecycle dates.
///
/// Layout (little-endian):
/// ```
/// [0]       opcode 0x52
/// [2..<6]   session length, seconds
/// [6..<8]   warmup length, seconds
/// [8..<12]  algorithm version
/// [12]      hardware version
/// [13..<15] maximum lifetime, days
/// ```
struct ExtendedVersionMessage: Sendable, Equatable {
    /// The bytes written to the control characteristic to request this
    /// message.
    static let request = Data([G7Opcode.extendedVersion])

    /// Total session length in seconds (e.g. 10 or 15 days).
    let sessionLength: UInt32
    /// Warmup length in seconds (~27 minutes).
    let warmupLength: UInt16
    let algorithmVersion: UInt32
    let hardwareVersion: UInt8
    /// Maximum sensor lifetime in days, including any grace period.
    let maxLifetimeDays: UInt16

    init?(data: Data) {
        guard
            data.count >= 15,
            data.byte(at: 0) == G7Opcode.extendedVersion,
            let sessionLength = data.uint32(at: 2),
            let warmupLength = data.uint16(at: 6),
            let algorithmVersion = data.uint32(at: 8),
            let hardwareVersion = data.byte(at: 12),
            let maxLifetimeDays = data.uint16(at: 13)
        else { return nil }

        self.sessionLength = sessionLength
        self.warmupLength = warmupLength
        self.algorithmVersion = algorithmVersion
        self.hardwareVersion = hardwareVersion
        self.maxLifetimeDays = maxLifetimeDays
    }
}
