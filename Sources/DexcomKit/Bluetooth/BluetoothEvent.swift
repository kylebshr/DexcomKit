import Foundation

/// Everything the session engine reacts to, unified into one `Sendable`
/// stream so the engine is a single serialized event loop.
///
/// The production central translates CoreBluetooth delegate callbacks into
/// these events, copying payloads into value types at the boundary; mocks
/// script them directly.
enum BluetoothEvent: Sendable {
    /// The central's state changed.
    case stateChanged(CentralState)

    /// A matching advertisement was seen while scanning.
    case discovered(peripheral: any PeripheralLink, name: String?, rssi: Int)

    /// A connection completed.
    case connected(UUID)

    /// A connection attempt failed.
    case failedToConnect(UUID)

    /// The peripheral disconnected. `isRemoteInitiated` is true when the
    /// sensor closed the link itself (its normal behavior after delivering
    /// data), as opposed to a local cancel or a link error.
    case disconnected(UUID, isRemoteInitiated: Bool)

    /// Service and characteristic discovery finished.
    case servicesReady(UUID, success: Bool)

    /// A notification subscription was confirmed or failed.
    case notificationState(UUID, characteristic: G7Characteristic, enabled: Bool, success: Bool)

    /// A characteristic delivered a value.
    case value(UUID, characteristic: G7Characteristic, data: Data)

    /// iOS relaunched the app and restored these peripherals
    /// (state restoration).
    case willRestore(peripherals: [any PeripheralLink])
}

/// Whether Bluetooth is usable.
enum CentralState: Sendable, Hashable {
    case poweredOn
    case unavailable(BluetoothUnavailableReason)
}
