import Foundation

/// The slice of a Bluetooth central the session engine needs.
///
/// This is the package's testability seam: the engine is written entirely
/// against this protocol and ``PeripheralLink``, so its state machine can be
/// driven by scripted mocks with no CoreBluetooth involved. The production
/// conformance wraps `CBCentralManager`.
protocol CentralManaging: Sendable {
    /// Starts the central. State events (including the initial one) arrive on
    /// the stream returned by ``events()``.
    func start()

    /// Returns the stream of Bluetooth events. Called once per engine start;
    /// the engine is the only consumer.
    func events() -> AsyncStream<BluetoothEvent>

    /// Scans for peripherals advertising the G7 service.
    func scanForSensors()

    func stopScan()

    /// Returns a previously connected peripheral by identifier, for the fast
    /// reconnect path that avoids waiting for an advertisement.
    func retrieveKnownPeripheral(withIdentifier identifier: UUID) -> (any PeripheralLink)?

    /// Initiates a connection. Pending connections don't time out; they
    /// complete whenever the sensor next becomes reachable.
    func connect(_ peripheral: any PeripheralLink)

    func cancelConnection(_ peripheral: any PeripheralLink)
}

/// The slice of a connected peripheral the session engine needs.
protocol PeripheralLink: Sendable {
    var identifier: UUID { get }
    var name: String? { get }
    var isConnected: Bool { get }

    /// Discovers the CGM service and its characteristics. Completion arrives
    /// as ``BluetoothEvent/servicesReady(_:success:)``.
    func discoverG7Services()

    /// Enables or disables notifications for a characteristic.
    func setNotify(_ enabled: Bool, for characteristic: G7Characteristic)

    /// Writes to a characteristic (with response).
    func write(_ data: Data, to characteristic: G7Characteristic)
}
