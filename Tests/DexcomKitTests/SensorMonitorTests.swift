import Foundation
import Testing

@testable import DexcomKit

@MainActor
@Suite(.timeLimit(.minutes(1))) struct SensorMonitorTests {
    let fixedNow = Date(timeIntervalSince1970: 1_750_300_000)

    func makeMonitor(
        selection: SensorSelection = .automatic
    ) -> (central: MockCentral, monitor: G7SensorMonitor) {
        let central = MockCentral()
        let configuration = G7Configuration(selection: selection, store: InMemoryStore())
        let now = fixedNow
        let monitor = G7SensorMonitor(
            configuration: configuration, central: central, sleep: { _ in }, now: { now })
        return (central, monitor)
    }

    /// Awaits a collection task's value, cancelling it after a timeout so a
    /// missed subscription fails fast instead of hanging the suite.
    func boundedValue<T: Sendable>(
        of task: Task<T, Never>, within duration: Duration = .seconds(5)
    ) async -> T {
        let deadline = Task {
            try? await Task.sleep(for: duration)
            task.cancel()
        }
        let value = await task.value
        deadline.cancel()
        return value
    }

    struct TimeoutError: Error {}

    /// Polls until the condition holds; records and throws on timeout so
    /// the test fails fast instead of cascading through later waits.
    func waitUntil(
        _ comment: Comment,
        _ condition: @MainActor () -> Bool
    ) async throws {
        for _ in 0..<2000 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Timed out waiting for \(comment)")
        throw TimeoutError()
    }

    /// Waits until the engine's broadcaster has the expected number of
    /// consumers (the monitor's mirror plus any pump streams), so events
    /// emitted afterwards are guaranteed to reach every stream.
    func waitForSubscribers(
        _ count: Int, of monitor: G7SensorMonitor
    ) async throws {
        for _ in 0..<2000 {
            if await monitor.engine.eventSubscriberCount() >= count { return }
            try await Task.sleep(for: .milliseconds(1))
        }
        Issue.record("Timed out waiting for \(count) event subscribers")
        throw TimeoutError()
    }

    /// Drives the mock through an authenticated connection.
    func driveToConnected(central: MockCentral, peripheral: MockPeripheral) async throws {
        // The monitor starts the engine asynchronously; events emitted
        // before it attaches to the central would be dropped.
        try await waitUntil("engine start") { central.calls.contains(.start) }
        central.emit(.stateChanged(.poweredOn))
        try await waitUntil("scan") { central.calls.contains(.scanForSensors) }
        central.emit(.discovered(peripheral: peripheral, name: peripheral.name, rssi: -60))
        try await waitUntil("connect") { central.calls.contains(.connect(peripheral.identifier)) }
        central.emit(.connected(peripheral.identifier))
        central.emit(.servicesReady(peripheral.identifier, success: true))
        try await waitUntil("auth subscription") {
            peripheral.calls.contains(.setNotify(true, .authentication))
        }
        central.emit(
            .value(peripheral.identifier, characteristic: .authentication, data: G7Fixtures.authOK))
    }

    @Test func startThrowsOnEmptyNameSuffix() {
        let (_, monitor) = makeMonitor(selection: .nameSuffix("  "))
        #expect(throws: DexcomError.invalidConfiguration("nameSuffix must not be empty")) {
            try monitor.start()
        }
    }

    @Test func snapshotsMirrorTheSession() async throws {
        let (central, monitor) = makeMonitor()
        #expect(monitor.connectionState == .idle)

        try monitor.start()
        let peripheral = MockPeripheral(name: "DXCM8T")
        try await driveToConnected(central: central, peripheral: peripheral)
        try await waitUntil("connected state") { monitor.connectionState == .connected }

        central.emit(
            .value(peripheral.identifier, characteristic: .control, data: G7Fixtures.glucose))
        try await waitUntil("latest reading") { monitor.latestReading != nil }

        #expect(monitor.latestReading?.glucose == 113)
        #expect(monitor.session?.sensorName == "DXCM8T")
        #expect(monitor.session?.activationDate == fixedNow.addingTimeInterval(-300_000))
    }

    @Test func readingsStreamFlattensBackfill() async throws {
        let (central, monitor) = makeMonitor()
        try monitor.start()

        let readingsTask = Task {
            var collected: [GlucoseReading] = []
            for await reading in monitor.readings() {
                collected.append(reading)
                if collected.count == 3 { break }
            }
            return collected
        }
        // The monitor's mirror plus the readings pump must both be
        // subscribed before events flow.
        try await waitForSubscribers(2, of: monitor)

        let peripheral = MockPeripheral(name: "DXCM8T")
        try await driveToConnected(central: central, peripheral: peripheral)
        central.emit(
            .value(peripheral.identifier, characteristic: .control, data: G7Fixtures.glucose))
        central.emit(
            .value(
                peripheral.identifier, characteristic: .backfill,
                data: backfillRecordBytes(timestamp: 299_700)
                    + backfillRecordBytes(timestamp: 299_400)))
        central.emit(
            .value(peripheral.identifier, characteristic: .control, data: Data([0x59])))

        let readings = await boundedValue(of: readingsTask)
        #expect(readings.map(\.timestampOffset) == [299_994, 299_400, 299_700])
        #expect(readings.map(\.isBackfilled) == [false, true, true])
    }

    @Test func multipleEventConsumersSeeTheSameEvents() async throws {
        let (central, monitor) = makeMonitor()
        try monitor.start()

        func collectReadings() -> Task<[GlucoseReading], Never> {
            Task {
                var collected: [GlucoseReading] = []
                for await event in monitor.events() {
                    if case .reading(let reading) = event {
                        collected.append(reading)
                        break
                    }
                }
                return collected
            }
        }
        let first = collectReadings()
        let second = collectReadings()
        // Mirror + two event pumps.
        try await waitForSubscribers(3, of: monitor)

        let peripheral = MockPeripheral(name: "DXCM8T")
        try await driveToConnected(central: central, peripheral: peripheral)
        central.emit(
            .value(peripheral.identifier, characteristic: .control, data: G7Fixtures.glucose))

        let firstReadings = await boundedValue(of: first)
        let secondReadings = await boundedValue(of: second)
        #expect(firstReadings.map(\.glucose) == [113])
        #expect(firstReadings == secondReadings)
    }

    @Test func stopReturnsToIdle() async throws {
        let (central, monitor) = makeMonitor()
        try monitor.start()
        let peripheral = MockPeripheral(name: "DXCM8T")
        try await driveToConnected(central: central, peripheral: peripheral)
        try await waitUntil("connected state") { monitor.connectionState == .connected }

        monitor.stop()
        try await waitUntil("idle state") { monitor.connectionState == .idle }
        #expect(central.calls.contains(.cancelConnection(peripheral.identifier)))
    }

    @Test func forgetSensorClearsSnapshots() async throws {
        let (central, monitor) = makeMonitor()
        try monitor.start()
        let peripheral = MockPeripheral(name: "DXCM8T")
        try await driveToConnected(central: central, peripheral: peripheral)
        central.emit(
            .value(peripheral.identifier, characteristic: .control, data: G7Fixtures.glucose))
        try await waitUntil("latest reading") { monitor.latestReading != nil }

        monitor.forgetSensor()
        #expect(monitor.latestReading == nil)
        #expect(monitor.session == nil)
    }
}
