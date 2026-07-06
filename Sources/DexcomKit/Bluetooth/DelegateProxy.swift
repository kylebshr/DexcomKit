import CoreBluetooth
import Foundation

/// Receives CoreBluetooth delegate callbacks and forwards them to the owning
/// ``CoreBluetoothCentral``.
///
/// All callbacks arrive on the central's private serial queue (the queue the
/// `CBCentralManager` was created with), and the owner's handlers run inline
/// on it — CoreBluetooth objects never leave that queue.
final class DelegateProxy: NSObject, @unchecked Sendable {
    weak var owner: CoreBluetoothCentral?
}

extension DelegateProxy: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        owner?.handleStateUpdate(central.state)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        owner?.handleDiscovery(peripheral, advertisedName: advertisedName, rssi: RSSI.intValue)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        owner?.handleConnect(peripheral)
    }

    func centralManager(
        _ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?
    ) {
        owner?.handleFailToConnect(peripheral, error: error)
    }

    func centralManager(
        _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        owner?.handleDisconnect(peripheral, error: error)
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let peripherals =
            dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        owner?.handleRestore(peripherals)
    }

    #if os(iOS)
        func centralManager(
            _ central: CBCentralManager, connectionEventDidOccur event: CBConnectionEvent,
            for peripheral: CBPeripheral
        ) {
            owner?.handleConnectionEvent(event, for: peripheral)
        }
    #endif
}

extension DelegateProxy: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        owner?.handleServicesDiscovered(peripheral, error: error)
    }

    func peripheral(
        _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        owner?.handleCharacteristicsDiscovered(peripheral, service: service, error: error)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateNotificationStateFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        owner?.handleNotificationStateUpdate(peripheral, characteristic: characteristic, error: error)
    }

    func peripheral(
        _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        owner?.handleValueUpdate(peripheral, characteristic: characteristic, error: error)
    }

    func peripheral(
        _ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        owner?.handleWriteCompletion(peripheral, characteristic: characteristic, error: error)
    }
}
