import Foundation

@testable import DexcomKit

/// A scriptable `CentralManaging` for engine tests.
///
/// Tests emit `BluetoothEvent`s with ``emit(_:)`` and assert on the recorded
/// calls. Mutable state is lock-protected because the engine calls in from
/// its actor while the test drives from another task.
final class MockCentral: CentralManaging, @unchecked Sendable {
    enum Call: Equatable {
        case start
        case scanForSensors
        case stopScan
        case retrieveKnownPeripheral(UUID)
        case connect(UUID)
        case cancelConnection(UUID)
    }

    private let lock = NSLock()
    private var _calls: [Call] = []
    private var continuation: AsyncStream<BluetoothEvent>.Continuation?

    /// Peripherals returned by `retrieveKnownPeripheral(withIdentifier:)`.
    var knownPeripherals: [UUID: MockPeripheral] {
        get { lock.withLock { _knownPeripherals } }
        set { lock.withLock { _knownPeripherals = newValue } }
    }
    private var _knownPeripherals: [UUID: MockPeripheral] = [:]

    var calls: [Call] {
        lock.withLock { _calls }
    }

    func calls(matching call: Call) -> Int {
        calls.filter { $0 == call }.count
    }

    /// Delivers an event to the engine's event loop.
    func emit(_ event: BluetoothEvent) {
        lock.withLock { continuation }?.yield(event)
    }

    // MARK: CentralManaging

    func start() {
        record(.start)
    }

    func events() -> AsyncStream<BluetoothEvent> {
        let (stream, continuation) = AsyncStream<BluetoothEvent>.makeStream()
        lock.withLock { self.continuation = continuation }
        return stream
    }

    func scanForSensors() {
        record(.scanForSensors)
    }

    func stopScan() {
        record(.stopScan)
    }

    func retrieveKnownPeripheral(withIdentifier identifier: UUID) -> (any PeripheralLink)? {
        record(.retrieveKnownPeripheral(identifier))
        return lock.withLock { _knownPeripherals[identifier] }
    }

    func connect(_ peripheral: any PeripheralLink) {
        record(.connect(peripheral.identifier))
    }

    func cancelConnection(_ peripheral: any PeripheralLink) {
        record(.cancelConnection(peripheral.identifier))
    }

    private func record(_ call: Call) {
        lock.withLock { _calls.append(call) }
    }
}

/// A scriptable `PeripheralLink` recording the engine's characteristic
/// operations.
final class MockPeripheral: PeripheralLink, @unchecked Sendable {
    enum Call: Equatable {
        case discoverG7Services
        case setNotify(Bool, G7Characteristic)
        case write(Data, G7Characteristic)
    }

    let identifier: UUID
    let name: String?

    private let lock = NSLock()
    private var _calls: [Call] = []
    private var _isConnected = false

    init(identifier: UUID = UUID(), name: String?) {
        self.identifier = identifier
        self.name = name
    }

    var isConnected: Bool {
        get { lock.withLock { _isConnected } }
        set { lock.withLock { _isConnected = newValue } }
    }

    var calls: [Call] {
        lock.withLock { _calls }
    }

    func calls(matching call: Call) -> Int {
        calls.filter { $0 == call }.count
    }

    func discoverG7Services() {
        lock.withLock { _calls.append(.discoverG7Services) }
    }

    func setNotify(_ enabled: Bool, for characteristic: G7Characteristic) {
        lock.withLock { _calls.append(.setNotify(enabled, characteristic)) }
    }

    func write(_ data: Data, to characteristic: G7Characteristic) {
        lock.withLock { _calls.append(.write(data, characteristic)) }
    }
}
