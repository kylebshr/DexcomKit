import Foundation
import Testing

@testable import DexcomKit

@Suite(.timeLimit(.minutes(1))) struct SessionEngineTests {
    let fixedNow = Date(timeIntervalSince1970: 1_750_300_000)

    func makeHarness(
        selection: SensorSelection = .automatic,
        backfillEnabled: Bool = true,
        store: InMemoryStore = InMemoryStore(),
        sleep: @escaping G7SessionEngine.SleepFunction = { _ in }
    ) -> (central: MockCentral, store: InMemoryStore, engine: G7SessionEngine) {
        let central = MockCentral()
        let configuration = G7Configuration(
            selection: selection, store: store, backfillEnabled: backfillEnabled)
        let now = fixedNow
        let engine = G7SessionEngine(
            configuration: configuration, central: central, sleep: sleep, now: { now })
        return (central, store, engine)
    }

    /// Drives the engine from start through an authenticated connection.
    func driveToConnected(
        central: MockCentral,
        engine: G7SessionEngine,
        peripheral: MockPeripheral,
        iterator: inout AsyncStream<G7Event>.AsyncIterator
    ) async {
        await engine.start()
        central.emit(.stateChanged(.poweredOn))
        #expect(await nextConnectionState(&iterator) == .scanning)

        central.emit(.discovered(peripheral: peripheral, name: peripheral.name, rssi: -60))
        #expect(await nextConnectionState(&iterator) == .connecting)

        central.emit(.connected(peripheral.identifier))
        central.emit(.servicesReady(peripheral.identifier, success: true))
        #expect(await nextConnectionState(&iterator) == .authenticating)

        central.emit(
            .value(peripheral.identifier, characteristic: .authentication, data: G7Fixtures.authOK))
        #expect(await nextConnectionState(&iterator) == .connected)
    }

    @Test func happyPathDeliversReadingAndPersistsAdoption() async throws {
        let (central, store, engine) = makeHarness()
        var iterator = await engine.eventStream().makeAsyncIterator()
        let peripheral = MockPeripheral(name: "DXCM8T")

        await driveToConnected(
            central: central, engine: engine, peripheral: peripheral, iterator: &iterator)

        // Exactly one connection, scan stopped before connecting.
        let centralCalls = central.calls
        #expect(centralCalls.contains(.start))
        #expect(central.calls(matching: .connect(peripheral.identifier)) == 1)
        let scanStop = try #require(centralCalls.firstIndex(of: .stopScan))
        let connect = try #require(centralCalls.firstIndex(of: .connect(peripheral.identifier)))
        #expect(scanStop < connect)

        // Subscription order: authentication first, control only after the
        // auth status confirms a session, backfill not until first glucose.
        let peripheralCalls = peripheral.calls
        #expect(peripheral.calls(matching: .setNotify(true, .authentication)) == 1)
        #expect(peripheral.calls(matching: .setNotify(true, .control)) == 1)
        #expect(peripheral.calls(matching: .setNotify(true, .backfill)) == 0)
        let authNotify = try #require(
            peripheralCalls.firstIndex(of: .setNotify(true, .authentication)))
        let controlNotify = try #require(
            peripheralCalls.firstIndex(of: .setNotify(true, .control)))
        #expect(authNotify < controlNotify)
        #expect(peripheral.calls.contains(.discoverG7Services))

        central.emit(
            .value(peripheral.identifier, characteristic: .control, data: G7Fixtures.glucose))

        let session = await nextEvent(&iterator) {
            if case .sessionEstablished(let session) = $0 { session } else { nil }
        }
        #expect(session?.sensorName == "DXCM8T")
        #expect(session?.activationDate == fixedNow.addingTimeInterval(-300_000))

        let reading = await nextReading(&iterator)
        #expect(reading?.glucose == 113)
        #expect(reading?.sensorName == "DXCM8T")
        #expect(reading?.isBackfilled == false)
        // Reading time = activation + (messageTimestamp − age) = now − age.
        #expect(reading?.date == fixedNow.addingTimeInterval(-6))

        #expect(peripheral.calls.contains(.write(ExtendedVersionMessage.request, .control)))
        // Backfill subscription happens on the first reading, matching the
        // G7SensorKit reference order.
        #expect(peripheral.calls(matching: .setNotify(true, .backfill)) == 1)

        let followed = store.loadFollowedSensor()
        #expect(followed?.name == "DXCM8T")
        #expect(followed?.peripheralIdentifier == peripheral.identifier)
        #expect(followed?.activationDate == fixedNow.addingTimeInterval(-300_000))
    }

    @Test func duplicateReadingsAreDeliveredOnce() async throws {
        let (central, _, engine) = makeHarness()
        var iterator = await engine.eventStream().makeAsyncIterator()
        let peripheral = MockPeripheral(name: "DXCM8T")
        await driveToConnected(
            central: central, engine: engine, peripheral: peripheral, iterator: &iterator)

        central.emit(
            .value(peripheral.identifier, characteristic: .control, data: G7Fixtures.glucose))
        #expect(await nextReading(&iterator) != nil)

        // The same message again, then a session-stop marker to synchronize:
        // the next observed event must be the session end, not a reading.
        central.emit(
            .value(peripheral.identifier, characteristic: .control, data: G7Fixtures.glucose))
        central.emit(
            .value(peripheral.identifier, characteristic: .control, data: Data([0x28])))

        let next = await nextEvent(&iterator) { event -> G7Event? in
            switch event {
            case .reading, .sessionEnded: event
            default: nil
            }
        }
        #expect(next == .sessionEnded(.stopped))
    }

    @Test func extendedVersionIsRequestedOncePerSession() async throws {
        let (central, _, engine) = makeHarness()
        var iterator = await engine.eventStream().makeAsyncIterator()
        let peripheral = MockPeripheral(name: "DXCM8T")
        await driveToConnected(
            central: central, engine: engine, peripheral: peripheral, iterator: &iterator)

        central.emit(
            .value(peripheral.identifier, characteristic: .control, data: G7Fixtures.glucose))
        #expect(await nextReading(&iterator) != nil)

        // A later reading with a fresh timestamp.
        var later = Data(G7Fixtures.glucose)
        later[2] = 0x2C  // messageTimestamp 300_300 = 0x0004952C
        later[3] = 0x95
        central.emit(.value(peripheral.identifier, characteristic: .control, data: later))
        #expect(await nextReading(&iterator) != nil)

        #expect(peripheral.calls(matching: .write(ExtendedVersionMessage.request, .control)) == 1)
    }

    @Test func extendedVersionRefinesSessionDates() async throws {
        let (central, _, engine) = makeHarness()
        var iterator = await engine.eventStream().makeAsyncIterator()
        let peripheral = MockPeripheral(name: "DXCM8T")
        await driveToConnected(
            central: central, engine: engine, peripheral: peripheral, iterator: &iterator)

        central.emit(
            .value(peripheral.identifier, characteristic: .control, data: G7Fixtures.glucose))
        let initial = await nextEvent(&iterator) {
            if case .sessionEstablished(let session) = $0 { session } else { nil }
        }
        let activation = try #require(initial?.activationDate)

        central.emit(
            .value(
                peripheral.identifier, characteristic: .control,
                data: G7Fixtures.extendedVersion10Day))
        let refined = await nextEvent(&iterator) {
            if case .sessionEstablished(let session) = $0 { session } else { nil }
        }
        #expect(refined?.warmupEndDate == activation.addingTimeInterval(1620))
        #expect(refined?.expirationDate == activation.addingTimeInterval(864_000))
        #expect(refined?.algorithmVersion == 0x0001_0203)
    }

    @Test func backfillIsSortedDedupedAndDelivered() async throws {
        let (central, _, engine) = makeHarness()
        var iterator = await engine.eventStream().makeAsyncIterator()
        let peripheral = MockPeripheral(name: "DXCM8T")
        await driveToConnected(
            central: central, engine: engine, peripheral: peripheral, iterator: &iterator)

        // Real-time reading first, at offset 299_994.
        central.emit(
            .value(peripheral.identifier, characteristic: .control, data: G7Fixtures.glucose))
        #expect(await nextReading(&iterator) != nil)

        // One chunk carrying two records out of order, plus one record that
        // duplicates the real-time reading's offset.
        let chunk =
            backfillRecordBytes(timestamp: 299_700)
            + backfillRecordBytes(timestamp: 299_400)
            + backfillRecordBytes(timestamp: 299_994)
        central.emit(.value(peripheral.identifier, characteristic: .backfill, data: chunk))
        central.emit(
            .value(peripheral.identifier, characteristic: .control, data: Data([0x59])))

        let backfill = await nextEvent(&iterator) {
            if case .backfill(let readings) = $0 { readings } else { nil }
        }
        #expect(backfill?.map(\.timestampOffset) == [299_400, 299_700])
        #expect(backfill?.allSatisfy(\.isBackfilled) == true)
    }

    @Test func backfillFlushesOnDisconnectWithoutFinishedMarker() async throws {
        let (central, _, engine) = makeHarness()
        var iterator = await engine.eventStream().makeAsyncIterator()
        let peripheral = MockPeripheral(name: "DXCM8T")
        await driveToConnected(
            central: central, engine: engine, peripheral: peripheral, iterator: &iterator)

        central.emit(
            .value(peripheral.identifier, characteristic: .control, data: G7Fixtures.glucose))
        #expect(await nextReading(&iterator) != nil)

        central.emit(
            .value(
                peripheral.identifier, characteristic: .backfill,
                data: backfillRecordBytes(timestamp: 299_400)))
        central.emit(.disconnected(peripheral.identifier, isRemoteInitiated: true))

        let backfill = await nextEvent(&iterator) {
            if case .backfill(let readings) = $0 { readings } else { nil }
        }
        #expect(backfill?.map(\.timestampOffset) == [299_400])
    }

    @Test func backfillDisabledSkipsSubscriptionAndDelivery() async throws {
        let (central, _, engine) = makeHarness(backfillEnabled: false)
        var iterator = await engine.eventStream().makeAsyncIterator()
        let peripheral = MockPeripheral(name: "DXCM8T")
        await driveToConnected(
            central: central, engine: engine, peripheral: peripheral, iterator: &iterator)

        #expect(peripheral.calls(matching: .setNotify(true, .backfill)) == 0)

        central.emit(
            .value(peripheral.identifier, characteristic: .control, data: G7Fixtures.glucose))
        #expect(await nextReading(&iterator) != nil)

        central.emit(
            .value(
                peripheral.identifier, characteristic: .backfill,
                data: backfillRecordBytes(timestamp: 299_400)))
        central.emit(
            .value(peripheral.identifier, characteristic: .control, data: Data([0x59])))
        central.emit(
            .value(peripheral.identifier, characteristic: .control, data: Data([0x28])))

        let next = await nextEvent(&iterator) { event -> G7Event? in
            switch event {
            case .backfill, .sessionEnded: event
            default: nil
            }
        }
        #expect(next == .sessionEnded(.stopped))
    }

    @Test func unauthenticatedSensorReportsErrorAndIsNotAdopted() async throws {
        let (central, store, engine) = makeHarness()
        var iterator = await engine.eventStream().makeAsyncIterator()
        let peripheral = MockPeripheral(name: "DXCM8T")

        await engine.start()
        central.emit(.stateChanged(.poweredOn))
        #expect(await nextConnectionState(&iterator) == .scanning)
        central.emit(.discovered(peripheral: peripheral, name: "DXCM8T", rssi: -60))
        #expect(await nextConnectionState(&iterator) == .connecting)
        central.emit(.connected(peripheral.identifier))
        central.emit(.servicesReady(peripheral.identifier, success: true))
        #expect(await nextConnectionState(&iterator) == .authenticating)

        central.emit(
            .value(
                peripheral.identifier, characteristic: .authentication,
                data: Data([0x05, 0x00, 0x00])))

        let error = await nextEvent(&iterator) {
            if case .error(let error) = $0 { error } else { nil }
        }
        #expect(error == .authenticationRejected)
        #expect(peripheral.calls(matching: .setNotify(true, .control)) == 0)
        #expect(store.loadFollowedSensor() == nil)
        // The engine stays connected: the status can still update within
        // this connection window.
        #expect(central.calls(matching: .cancelConnection(peripheral.identifier)) == 0)
    }

    @Test func otherSensorsAreIgnoredWhileFollowing() async throws {
        let store = InMemoryStore()
        let followedID = UUID()
        store.saveFollowedSensor(
            FollowedSensor(
                name: "DXCM8T", peripheralIdentifier: followedID,
                activationDate: fixedNow.addingTimeInterval(-300_000)))

        let (central, _, engine) = makeHarness(store: store)
        var iterator = await engine.eventStream().makeAsyncIterator()

        await engine.start()
        // The persisted session is re-announced immediately.
        let resumed = await nextEvent(&iterator) {
            if case .sessionEstablished(let session) = $0 { session } else { nil }
        }
        #expect(resumed?.sensorName == "DXCM8T")

        central.emit(.stateChanged(.poweredOn))
        #expect(await nextConnectionState(&iterator) == .scanning)
        #expect(central.calls.contains(.retrieveKnownPeripheral(followedID)))

        let stranger = MockPeripheral(name: "DXCM9Q")
        central.emit(.discovered(peripheral: stranger, name: "DXCM9Q", rssi: -50))

        let mine = MockPeripheral(name: "DXCM8T")
        central.emit(.discovered(peripheral: mine, name: "DXCM8T", rssi: -70))
        #expect(await nextConnectionState(&iterator) == .connecting)

        #expect(central.calls(matching: .connect(stranger.identifier)) == 0)
        #expect(central.calls(matching: .connect(mine.identifier)) == 1)
    }

    @Test func knownPeripheralGetsPendingConnectWithoutDiscovery() async throws {
        let store = InMemoryStore()
        let peripheral = MockPeripheral(name: "DXCM8T")
        store.saveFollowedSensor(
            FollowedSensor(
                name: "DXCM8T", peripheralIdentifier: peripheral.identifier,
                activationDate: fixedNow.addingTimeInterval(-300_000)))

        let (central, _, engine) = makeHarness(store: store)
        central.knownPeripherals[peripheral.identifier] = peripheral
        var iterator = await engine.eventStream().makeAsyncIterator()

        await engine.start()
        central.emit(.stateChanged(.poweredOn))
        #expect(await nextConnectionState(&iterator) == .scanning)

        #expect(central.calls(matching: .connect(peripheral.identifier)) == 1)

        // The pending connect completes when the sensor comes into range.
        central.emit(.connected(peripheral.identifier))
        #expect(await nextConnectionState(&iterator) == .connecting)
        central.emit(.servicesReady(peripheral.identifier, success: true))
        #expect(await nextConnectionState(&iterator) == .authenticating)
    }

    @Test func restoredConnectedPeripheralResumesDirectly() async throws {
        let store = InMemoryStore()
        let peripheral = MockPeripheral(name: "DXCM8T")
        peripheral.isConnected = true
        store.saveFollowedSensor(
            FollowedSensor(
                name: "DXCM8T", peripheralIdentifier: peripheral.identifier,
                activationDate: fixedNow.addingTimeInterval(-300_000)))

        let (central, _, engine) = makeHarness(store: store)
        var iterator = await engine.eventStream().makeAsyncIterator()
        await engine.start()

        // willRestoreState arrives before poweredOn; the engine defers all
        // action until the central is ready.
        central.emit(.willRestore(peripherals: [peripheral]))
        central.emit(.stateChanged(.poweredOn))
        #expect(await nextConnectionState(&iterator) == .connecting)
        #expect(peripheral.calls.contains(.discoverG7Services))
        #expect(central.calls(matching: .connect(peripheral.identifier)) == 0)
    }

    @Test func serviceDiscoveryFailureReportsErrorAndRescans() async throws {
        let (central, _, engine) = makeHarness()
        var iterator = await engine.eventStream().makeAsyncIterator()
        let peripheral = MockPeripheral(name: "DXCM8T")

        await engine.start()
        central.emit(.stateChanged(.poweredOn))
        #expect(await nextConnectionState(&iterator) == .scanning)
        central.emit(.discovered(peripheral: peripheral, name: "DXCM8T", rssi: -60))
        #expect(await nextConnectionState(&iterator) == .connecting)
        central.emit(.connected(peripheral.identifier))
        central.emit(.servicesReady(peripheral.identifier, success: false))

        let error = await nextEvent(&iterator) {
            if case .error(let error) = $0 { error } else { nil }
        }
        #expect(error == .serviceDiscoveryFailed)
        #expect(await nextConnectionState(&iterator) == .waitingForReading)
        #expect(central.calls.contains(.cancelConnection(peripheral.identifier)))
    }

    @Test func sensorFailureStateEndsSession() async throws {
        let (central, _, engine) = makeHarness()
        var iterator = await engine.eventStream().makeAsyncIterator()
        let peripheral = MockPeripheral(name: "DXCM8T")
        await driveToConnected(
            central: central, engine: engine, peripheral: peripheral, iterator: &iterator)

        var failed = Data(G7Fixtures.glucose)
        failed[14] = AlgorithmState.State.sensorFailed.rawValue
        central.emit(.value(peripheral.identifier, characteristic: .control, data: failed))

        let end = await nextEvent(&iterator) {
            if case .sessionEnded(let reason) = $0 { reason } else { nil }
        }
        #expect(end == .failed)
    }

    @Test func forgetSensorClearsPersistenceAndRescans() async throws {
        let (central, store, engine) = makeHarness()
        var iterator = await engine.eventStream().makeAsyncIterator()
        let peripheral = MockPeripheral(name: "DXCM8T")
        await driveToConnected(
            central: central, engine: engine, peripheral: peripheral, iterator: &iterator)

        central.emit(
            .value(peripheral.identifier, characteristic: .control, data: G7Fixtures.glucose))
        #expect(await nextReading(&iterator) != nil)
        #expect(store.loadFollowedSensor() != nil)

        await engine.forgetSensor()
        #expect(store.loadFollowedSensor() == nil)
        #expect(central.calls.contains(.cancelConnection(peripheral.identifier)))
        #expect(await nextConnectionState(&iterator) == .scanning)
    }

    @Test func stopGoesIdleAndCancelsConnection() async throws {
        let (central, _, engine) = makeHarness()
        var iterator = await engine.eventStream().makeAsyncIterator()
        let peripheral = MockPeripheral(name: "DXCM8T")
        await driveToConnected(
            central: central, engine: engine, peripheral: peripheral, iterator: &iterator)

        await engine.stop()
        #expect(await nextConnectionState(&iterator) == .idle)
        #expect(central.calls.contains(.cancelConnection(peripheral.identifier)))
        #expect(central.calls.contains(.stopScan))
    }
}
