import CoreBluetooth
import Foundation

/// The production ``PeripheralLink``: a thin wrapper over `CBPeripheral`.
///
/// Thread-safety invariant for `@unchecked Sendable`: all `CBPeripheral`
/// access happens on the central's serial `queue`. The engine calls in from
/// its actor; every call hops onto the queue.
final class CoreBluetoothPeripheral: PeripheralLink, @unchecked Sendable {
    let peripheral: CBPeripheral
    private let queue: DispatchQueue

    /// Cached at creation: `CBPeer.identifier` is immutable, so this is safe
    /// to read from any isolation domain without a queue hop.
    let identifier: UUID

    init(peripheral: CBPeripheral, queue: DispatchQueue) {
        self.peripheral = peripheral
        self.queue = queue
        self.identifier = peripheral.identifier
    }

    var name: String? {
        // `CBPeripheral.name` is mutable state the CoreBluetooth stack
        // updates on the serial queue (e.g. after GAP name resolution), so
        // reads must hop onto the queue too.
        queue.sync { peripheral.name }
    }

    var isConnected: Bool {
        queue.sync { peripheral.state == .connected }
    }

    func discoverG7Services() {
        queue.async {
            self.peripheral.discoverServices([G7UUID.cgmService])
        }
    }

    func setNotify(_ enabled: Bool, for characteristic: G7Characteristic) {
        queue.async {
            guard let target = self.characteristic(for: characteristic) else {
                Log.connection.error(
                    "Cannot set notify: \(String(describing: characteristic), privacy: .public) not discovered"
                )
                return
            }
            self.peripheral.setNotifyValue(enabled, for: target)
        }
    }

    func write(_ data: Data, to characteristic: G7Characteristic) {
        queue.async {
            guard let target = self.characteristic(for: characteristic) else {
                Log.connection.error(
                    "Cannot write: \(String(describing: characteristic), privacy: .public) not discovered"
                )
                return
            }
            self.peripheral.writeValue(data, for: target, type: .withResponse)
        }
    }

    /// Must be called on the queue.
    private func characteristic(for characteristic: G7Characteristic) -> CBCharacteristic? {
        peripheral.services?
            .first { $0.uuid == G7UUID.cgmService }?
            .characteristics?
            .first { $0.uuid == G7UUID.uuid(for: characteristic) }
    }
}
