import CoreBluetooth
import Foundation
import os

/// The production ``CentralManaging``: owns a `CBCentralManager` on a private
/// serial queue and translates delegate callbacks into ``BluetoothEvent``s.
///
/// Thread-safety invariant for `@unchecked Sendable`: `manager` and
/// `wrappers` (and every CoreBluetooth object) are touched only on `queue`;
/// the stream continuation is guarded by `lock`. Payloads are copied into
/// value types before they leave the queue.
final class CoreBluetoothCentral: CentralManaging, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.kylebshr.DexcomKit.bluetooth")
    private let proxy = DelegateProxy()
    private let restoreIdentifier: String?

    private let lock = NSLock()
    private var continuation: AsyncStream<BluetoothEvent>.Continuation?

    // Queue-confined.
    private var manager: CBCentralManager?
    private var wrappers: [UUID: CoreBluetoothPeripheral] = [:]
    private var connectionSignpost: OSSignpostIntervalState?

    init(restoreIdentifier: String? = nil) {
        self.restoreIdentifier = restoreIdentifier
        proxy.owner = self
    }

    // MARK: - CentralManaging

    func events() -> AsyncStream<BluetoothEvent> {
        let (stream, continuation) = AsyncStream<BluetoothEvent>.makeStream()
        lock.withLock {
            self.continuation?.finish()
            self.continuation = continuation
        }
        return stream
    }

    func start() {
        queue.async {
            guard self.manager == nil else {
                // Restarted: replay the current state so the new event loop
                // gets an initial state event.
                if let manager = self.manager {
                    self.handleStateUpdate(manager.state)
                }
                return
            }
            var options: [String: Any] = [:]
            #if os(iOS)
                if let restoreIdentifier = self.restoreIdentifier {
                    options[CBCentralManagerOptionRestoreIdentifierKey] = restoreIdentifier
                }
            #endif
            Log.connection.info("Creating central manager")
            self.manager = CBCentralManager(delegate: self.proxy, queue: self.queue, options: options)
        }
    }

    func scanForSensors() {
        queue.async {
            guard let manager = self.manager, manager.state == .poweredOn else { return }
            manager.scanForPeripherals(withServices: [G7UUID.advertisedService], options: nil)
        }
    }

    func stopScan() {
        queue.async {
            guard let manager = self.manager, manager.state == .poweredOn else { return }
            manager.stopScan()
        }
    }

    func retrieveKnownPeripheral(withIdentifier identifier: UUID) -> (any PeripheralLink)? {
        queue.sync {
            guard let manager, manager.state == .poweredOn else { return nil }
            guard
                let peripheral = manager.retrievePeripherals(withIdentifiers: [identifier]).first
            else { return nil }
            return wrapper(for: peripheral)
        }
    }

    func connect(_ peripheral: any PeripheralLink) {
        queue.async {
            guard let wrapped = peripheral as? CoreBluetoothPeripheral else { return }
            // No connection options: requesting nothing avoids any pairing
            // or bonding UI. The sensor's session with the official Dexcom
            // app stays untouched.
            self.manager?.connect(wrapped.peripheral, options: nil)
        }
    }

    func cancelConnection(_ peripheral: any PeripheralLink) {
        queue.async {
            guard let wrapped = peripheral as? CoreBluetoothPeripheral else { return }
            self.manager?.cancelPeripheralConnection(wrapped.peripheral)
        }
    }

    // MARK: - Callbacks from DelegateProxy (all on queue)

    func handleStateUpdate(_ state: CBManagerState) {
        switch state {
        case .poweredOn:
            registerForConnectionEvents()
            yield(.stateChanged(.poweredOn))
        case .poweredOff:
            yield(.stateChanged(.unavailable(.poweredOff)))
        case .unauthorized:
            yield(.stateChanged(.unavailable(.unauthorized)))
        case .unsupported:
            yield(.stateChanged(.unavailable(.unsupported)))
        case .resetting:
            yield(.stateChanged(.unavailable(.resetting)))
        case .unknown:
            yield(.stateChanged(.unavailable(.unknown)))
        @unknown default:
            yield(.stateChanged(.unavailable(.unknown)))
        }
    }

    func handleDiscovery(_ peripheral: CBPeripheral, advertisedName: String?, rssi: Int) {
        yield(
            .discovered(
                peripheral: wrapper(for: peripheral),
                name: advertisedName ?? peripheral.name,
                rssi: rssi
            ))
    }

    func handleConnect(_ peripheral: CBPeripheral) {
        connectionSignpost = Log.signposter.beginInterval(
            "connection", id: Log.signposter.makeSignpostID())
        yield(.connected(peripheral.identifier))
    }

    func handleFailToConnect(_ peripheral: CBPeripheral, error: Error?) {
        Log.connection.error(
            "Failed to connect: \(error.map(String.init(describing:)) ?? "no error", privacy: .public)"
        )
        yield(.failedToConnect(peripheral.identifier))
    }

    func handleDisconnect(_ peripheral: CBPeripheral, error: Error?) {
        if let signpost = connectionSignpost {
            Log.signposter.endInterval("connection", signpost)
            connectionSignpost = nil
        }
        // The sensor hanging up after delivering data reports as
        // CBError.peripheralDisconnected; anything else is a local cancel or
        // a link error.
        let isRemoteInitiated = (error as? CBError)?.code == .peripheralDisconnected
        yield(.disconnected(peripheral.identifier, isRemoteInitiated: isRemoteInitiated))
    }

    func handleRestore(_ peripherals: [CBPeripheral]) {
        yield(.willRestore(peripherals: peripherals.map { wrapper(for: $0) }))
    }

    #if os(iOS)
        func handleConnectionEvent(_ event: CBConnectionEvent, for peripheral: CBPeripheral) {
            // Connection events wake the app in the background; the engine
            // drives actual connections, so this only needs to be visible.
            Log.connection.debug(
                "Connection event \(event.rawValue, privacy: .public) for known peripheral")
        }
    #endif

    func handleServicesDiscovered(_ peripheral: CBPeripheral, error: Error?) {
        guard
            error == nil,
            let service = peripheral.services?.first(where: { $0.uuid == G7UUID.cgmService })
        else {
            yield(.servicesReady(peripheral.identifier, success: false))
            return
        }
        let characteristics = G7Characteristic.allCases.map(G7UUID.uuid(for:))
        peripheral.discoverCharacteristics(characteristics, for: service)
    }

    func handleCharacteristicsDiscovered(
        _ peripheral: CBPeripheral, service: CBService, error: Error?
    ) {
        guard service.uuid == G7UUID.cgmService else { return }
        let success = error == nil && !(service.characteristics ?? []).isEmpty
        yield(.servicesReady(peripheral.identifier, success: success))
    }

    func handleNotificationStateUpdate(
        _ peripheral: CBPeripheral, characteristic: CBCharacteristic, error: Error?
    ) {
        guard let mapped = G7UUID.characteristic(for: characteristic.uuid) else { return }
        yield(
            .notificationState(
                peripheral.identifier,
                characteristic: mapped,
                enabled: characteristic.isNotifying,
                success: error == nil
            ))
    }

    func handleValueUpdate(
        _ peripheral: CBPeripheral, characteristic: CBCharacteristic, error: Error?
    ) {
        guard error == nil,
            let mapped = G7UUID.characteristic(for: characteristic.uuid),
            let value = characteristic.value
        else { return }
        // Copy the payload so no CoreBluetooth-owned buffer crosses the
        // queue boundary.
        yield(.value(peripheral.identifier, characteristic: mapped, data: Data(value)))
    }

    func handleWriteCompletion(
        _ peripheral: CBPeripheral, characteristic: CBCharacteristic, error: Error?
    ) {
        if let error {
            Log.connection.error(
                "Write failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: - Helpers (on queue)

    /// Returns the stable wrapper for a peripheral, creating it and taking
    /// over as its delegate on first sight.
    func wrapper(for peripheral: CBPeripheral) -> CoreBluetoothPeripheral {
        if let existing = wrappers[peripheral.identifier] {
            return existing
        }
        peripheral.delegate = proxy
        let wrapped = CoreBluetoothPeripheral(peripheral: peripheral, queue: queue)
        wrappers[peripheral.identifier] = wrapped
        return wrapped
    }

    private func registerForConnectionEvents() {
        #if os(iOS)
            manager?.registerForConnectionEvents(options: [
                .serviceUUIDs: [G7UUID.advertisedService, G7UUID.cgmService]
            ])
        #endif
    }

    private func yield(_ event: BluetoothEvent) {
        // Yield while holding the lock so a concurrent events() call (an
        // engine restart) can't finish-and-swap the continuation between
        // the read and the yield, silently dropping the event.
        lock.withLock {
            continuation?.yield(event)
        }
    }
}
