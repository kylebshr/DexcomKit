import CoreBluetooth

/// BLE identifiers for the G7 family, as documented by LoopKit/G7SensorKit.
///
/// `CBUUID` isn't declared `Sendable`, but it is an immutable value-like
/// class, so sharing these constants across isolation domains is safe —
/// hence `nonisolated(unsafe)`.
enum G7UUID {
    /// The 16-bit service UUID the sensor advertises (`FEBC`); scanning
    /// filters on this.
    nonisolated(unsafe) static let advertisedService = CBUUID(string: "FEBC")

    /// The CGM service containing the characteristics DexcomKit uses.
    nonisolated(unsafe) static let cgmService = CBUUID(
        string: "F8083532-849E-531C-C594-30F1F86A4EA5")

    static func uuid(for characteristic: G7Characteristic) -> CBUUID {
        switch characteristic {
        case .authentication: CBUUID(string: "F8083535-849E-531C-C594-30F1F86A4EA5")
        case .control: CBUUID(string: "F8083534-849E-531C-C594-30F1F86A4EA5")
        case .backfill: CBUUID(string: "F8083536-849E-531C-C594-30F1F86A4EA5")
        }
    }

    static func characteristic(for uuid: CBUUID) -> G7Characteristic? {
        G7Characteristic.allCases.first { self.uuid(for: $0) == uuid }
    }

    /// Advertised name prefixes for the sensor family: G7 (`DXCM`) and
    /// Dexcom One+ (`DX02`). The original Dexcom One (`DX01`) speaks the
    /// G6 protocol and is deliberately excluded.
    static let namePrefixes = ["DXCM", "DX02"]
}

/// The G7 CGM-service characteristics DexcomKit interacts with, abstracted
/// from their `CBUUID`s so the engine and tests never touch CoreBluetooth.
enum G7Characteristic: Sendable, Hashable, CaseIterable {
    /// Notifies the authentication status (opcode 0x05).
    case authentication
    /// Delivers glucose readings and control responses; writable.
    case control
    /// Streams historical readings as 9-byte records.
    case backfill
}
