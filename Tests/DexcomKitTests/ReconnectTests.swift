import Foundation
import Testing

@testable import DexcomKit

@Suite(.timeLimit(.minutes(1))) struct ReconnectTests {
    let fixedNow = Date(timeIntervalSince1970: 1_750_300_000)

    func makeEngine(
        central: MockCentral,
        store: InMemoryStore = InMemoryStore(),
        sleep: @escaping G7SessionEngine.SleepFunction
    ) -> G7SessionEngine {
        let now = fixedNow
        return G7SessionEngine(
            configuration: G7Configuration(store: store),
            central: central,
            sleep: sleep,
            now: { now }
        )
    }

    /// A store already following DXCM8T, so auth-strike heuristics (which
    /// only apply to a followed session) are active.
    func storeFollowing(_ peripheral: MockPeripheral) -> InMemoryStore {
        let store = InMemoryStore()
        store.saveFollowedSensor(
            FollowedSensor(
                name: peripheral.name ?? "DXCM8T",
                peripheralIdentifier: peripheral.identifier,
                activationDate: fixedNow.addingTimeInterval(-300_000)))
        return store
    }

    /// Drives from start through an authenticated connection.
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

    /// Drives one connect → authenticating → remote-disconnect cycle,
    /// returning the first session-end or waiting-state event after the
    /// disconnect.
    func driveAuthPendingDisconnect(
        central: MockCentral,
        peripheral: MockPeripheral,
        iterator: inout AsyncStream<G7Event>.AsyncIterator
    ) async -> G7Event? {
        central.emit(.discovered(peripheral: peripheral, name: peripheral.name, rssi: -60))
        #expect(await nextConnectionState(&iterator) == .connecting)
        central.emit(.connected(peripheral.identifier))
        central.emit(.servicesReady(peripheral.identifier, success: true))
        #expect(await nextConnectionState(&iterator) == .authenticating)
        central.emit(.disconnected(peripheral.identifier, isRemoteInitiated: true))
        // sessionEnded (if any) is emitted before the state change, so this
        // matcher sees whichever comes first.
        return await nextEvent(&iterator) { event -> G7Event? in
            switch event {
            case .sessionEnded, .connectionStateChanged(.waitingForReading): event
            default: nil
            }
        }
    }

    @Test func rescansTwoSecondsAfterDisconnect() async throws {
        let central = MockCentral()
        let recorder = SleepRecorder()
        let engine = makeEngine(central: central) { recorder.record($0) }
        var iterator = await engine.eventStream().makeAsyncIterator()
        let peripheral = MockPeripheral(name: "DXCM8T")
        await driveToConnected(
            central: central, engine: engine, peripheral: peripheral, iterator: &iterator)

        central.emit(.disconnected(peripheral.identifier, isRemoteInitiated: true))
        #expect(await nextConnectionState(&iterator) == .waitingForReading)
        #expect(await nextConnectionState(&iterator) == .scanning)

        #expect(recorder.durations == [G7SessionEngine.rescanDelay])
        #expect(central.calls(matching: .scanForSensors) == 2)
    }

    @Test func stopDuringRescanWindowGoesIdle() async throws {
        let central = MockCentral()
        // A long sleep keeps the rescan pending while stop() runs.
        let engine = makeEngine(central: central) { try await Task.sleep(for: $0 * 100) }
        var iterator = await engine.eventStream().makeAsyncIterator()
        let peripheral = MockPeripheral(name: "DXCM8T")
        await driveToConnected(
            central: central, engine: engine, peripheral: peripheral, iterator: &iterator)

        central.emit(.disconnected(peripheral.identifier, isRemoteInitiated: true))
        #expect(await nextConnectionState(&iterator) == .waitingForReading)

        // stop() goes idle immediately, without awaiting the sleeping rescan
        // task (which it cancels; the isStarted guard is the backstop).
        await engine.stop()
        #expect(await nextConnectionState(&iterator) == .idle)

        try await Task.sleep(for: .milliseconds(50))
        #expect(central.calls(matching: .scanForSensors) == 1)
    }

    @Test func repeatedDisconnectsDuringAuthSuggestSessionEnd() async throws {
        let central = MockCentral()
        let peripheral = MockPeripheral(name: "DXCM8T")
        let engine = makeEngine(
            central: central, store: storeFollowing(peripheral)) { _ in }
        var iterator = await engine.eventStream().makeAsyncIterator()

        await engine.start()
        central.emit(.stateChanged(.poweredOn))
        #expect(await nextConnectionState(&iterator) == .scanning)

        for attempt in 1...G7SessionEngine.maxAuthStrikes {
            let outcome = await driveAuthPendingDisconnect(
                central: central, peripheral: peripheral, iterator: &iterator)

            if attempt < G7SessionEngine.maxAuthStrikes {
                #expect(outcome == .connectionStateChanged(.waitingForReading))
                #expect(await nextConnectionState(&iterator) == .scanning)
            } else {
                #expect(outcome == .sessionEnded(.suspectedEnd))
            }
        }
    }

    @Test func authenticatedConnectionResetsStrikes() async throws {
        let central = MockCentral()
        let peripheral = MockPeripheral(name: "DXCM8T")
        let engine = makeEngine(
            central: central, store: storeFollowing(peripheral)) { _ in }
        var iterator = await engine.eventStream().makeAsyncIterator()

        await engine.start()
        central.emit(.stateChanged(.poweredOn))
        #expect(await nextConnectionState(&iterator) == .scanning)

        // Two strikes…
        for _ in 1...2 {
            let outcome = await driveAuthPendingDisconnect(
                central: central, peripheral: peripheral, iterator: &iterator)
            #expect(outcome == .connectionStateChanged(.waitingForReading))
            #expect(await nextConnectionState(&iterator) == .scanning)
        }

        // …then a successful authentication resets the count…
        central.emit(.discovered(peripheral: peripheral, name: "DXCM8T", rssi: -60))
        #expect(await nextConnectionState(&iterator) == .connecting)
        central.emit(.connected(peripheral.identifier))
        central.emit(.servicesReady(peripheral.identifier, success: true))
        #expect(await nextConnectionState(&iterator) == .authenticating)
        central.emit(
            .value(peripheral.identifier, characteristic: .authentication, data: G7Fixtures.authOK))
        #expect(await nextConnectionState(&iterator) == .connected)
        central.emit(.disconnected(peripheral.identifier, isRemoteInitiated: true))
        #expect(await nextConnectionState(&iterator) == .waitingForReading)
        #expect(await nextConnectionState(&iterator) == .scanning)

        // …so the NEXT auth-pending disconnect is strike 1 of 3, not 3 of 3.
        let outcome = await driveAuthPendingDisconnect(
            central: central, peripheral: peripheral, iterator: &iterator)
        #expect(outcome == .connectionStateChanged(.waitingForReading))
    }

    @Test func locallyInitiatedDisconnectsDoNotCountStrikes() async throws {
        let central = MockCentral()
        let peripheral = MockPeripheral(name: "DXCM8T")
        let engine = makeEngine(
            central: central, store: storeFollowing(peripheral)) { _ in }
        var iterator = await engine.eventStream().makeAsyncIterator()

        await engine.start()
        central.emit(.stateChanged(.poweredOn))
        #expect(await nextConnectionState(&iterator) == .scanning)

        // Local cancels during authentication, one more than the strike
        // limit — none may end the session.
        for _ in 1...(G7SessionEngine.maxAuthStrikes + 1) {
            central.emit(.discovered(peripheral: peripheral, name: "DXCM8T", rssi: -60))
            #expect(await nextConnectionState(&iterator) == .connecting)
            central.emit(.connected(peripheral.identifier))
            central.emit(.servicesReady(peripheral.identifier, success: true))
            #expect(await nextConnectionState(&iterator) == .authenticating)
            central.emit(.disconnected(peripheral.identifier, isRemoteInitiated: false))
            let outcome = await nextEvent(&iterator) { event -> G7Event? in
                switch event {
                case .sessionEnded, .connectionStateChanged(.waitingForReading): event
                default: nil
                }
            }
            #expect(outcome == .connectionStateChanged(.waitingForReading))
            #expect(await nextConnectionState(&iterator) == .scanning)
        }
    }

    @Test func failedConnectSchedulesRescan() async throws {
        let central = MockCentral()
        let engine = makeEngine(central: central) { _ in }
        var iterator = await engine.eventStream().makeAsyncIterator()
        let peripheral = MockPeripheral(name: "DXCM8T")

        await engine.start()
        central.emit(.stateChanged(.poweredOn))
        #expect(await nextConnectionState(&iterator) == .scanning)
        central.emit(.discovered(peripheral: peripheral, name: "DXCM8T", rssi: -60))
        #expect(await nextConnectionState(&iterator) == .connecting)

        central.emit(.failedToConnect(peripheral.identifier))
        #expect(await nextConnectionState(&iterator) == .waitingForReading)
        #expect(await nextConnectionState(&iterator) == .scanning)
        #expect(central.calls(matching: .scanForSensors) == 2)
    }

    @Test func bluetoothOffMidSessionRecoversOnPowerOn() async throws {
        let central = MockCentral()
        let engine = makeEngine(central: central) { _ in }
        var iterator = await engine.eventStream().makeAsyncIterator()
        let peripheral = MockPeripheral(name: "DXCM8T")
        await driveToConnected(
            central: central, engine: engine, peripheral: peripheral, iterator: &iterator)

        central.emit(.stateChanged(.unavailable(.poweredOff)))
        #expect(await nextConnectionState(&iterator) == .bluetoothUnavailable(.poweredOff))

        central.emit(.stateChanged(.poweredOn))
        #expect(await nextConnectionState(&iterator) == .scanning)
    }

    @Test func engineRestartsCleanly() async throws {
        let central = MockCentral()
        let engine = makeEngine(central: central) { _ in }
        var iterator = await engine.eventStream().makeAsyncIterator()
        let peripheral = MockPeripheral(name: "DXCM8T")
        await driveToConnected(
            central: central, engine: engine, peripheral: peripheral, iterator: &iterator)

        await engine.stop()
        #expect(await nextConnectionState(&iterator) == .idle)

        await engine.start()
        central.emit(.stateChanged(.poweredOn))
        #expect(await nextConnectionState(&iterator) == .scanning)
        #expect(central.calls(matching: .start) == 2)
    }
}
