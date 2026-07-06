import Foundation

/// Authentication status (opcode `0x05`) observed on the authentication
/// characteristic.
///
/// DexcomKit never authenticates; it waits for the sensor to report that a
/// bonded, authenticated session exists (established by the official Dexcom
/// app or receiver) before subscribing to glucose data.
struct AuthStatusMessage: Sendable, Equatable {
    let isAuthenticated: Bool
    let isBonded: Bool

    init?(data: Data) {
        guard data.count >= 3, data.byte(at: 0) == G7Opcode.authStatus else { return nil }
        isAuthenticated = data.byte(at: 1) == 0x01
        isBonded = data.byte(at: 2) == 0x01
    }
}
