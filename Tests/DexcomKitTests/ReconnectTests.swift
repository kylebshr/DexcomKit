import Foundation
import Testing

@testable import DexcomKit

@Suite struct ReconnectTests {
    let fixedNow = Date(timeIntervalSince1970: 1_750_300_000)

    func makeEngine(
        central: MockCentral,
        sleep: @escaping G7SessionEngine.SleepFunction
    ) -> G7SessionEngine {
        let now = fixedNow
        return G7SessionEngine(
            configuration: G7Configuration(store: InMemoryStore()),
            central: central,
            sleep: sleep,
            now: { now }
        )
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

    @Test func stopCancelsPendingRescan() async throws {
        let central = MockCentral()
        // A long real sleep: the rescan only fires if cancellation is broken.
        let engine = makeEngine(central: central) { try await Task.sleep(for: $0 * 100) }
        var iterator = await engine.eventStream().makeAsyncIterator()
        let peripheral = MockPeripheral(name: "DXCM8T")
        await driveToConnected(
            central: central, engine: engine, peripheral: peripheral, iterator: &iterator)

        central.emit(.disconnected(peripheral.identifier, isRemoteInitiated: true))
        #expect(await nextConnectionState(&iterator) == .waitingForReading)

        await engine.stop()
        #expect(await nextConnectionState(&iterator) == .idle)

        // Give a cancelled-but-leaky rescan a chance to run, then confirm it
        // didn't.
        try await Task.sleep(for: .milliseconds(50))
        #expect(central.calls(matching: .scanForSensors) == 1)
    }

    @Test func repeatedDisconnectsDuringAuthSuggestSessionEnd() async throws {
        let central = MockCentral()
        let engine = makeEngine(central: central) { _ in }
        var iterator = await engine.eventStream().makeAsyncIterator()
        let peripheral = MockPeripheral(name: "DXCM8T")

        await engine.start()
        central.emit(.stateChanged(.poweredOn))
        #expect(await nextConnectionState(&iterator) == .scanning)

        for attempt in 1...G7SessionEngine.maxAuthStrikes {
            central.emit(.discovered(peripheral: peripheral, name: "DXCM8T", rssi: -60))
            #expect(await nextConnectionState(&iterator) == .connecting)
            central.emit(.connected(peripheral.identifier))
            central.emit(.servicesReady(peripheral.identifier, success: true))
            #expect(await nextConnectionState(&iterator) == .authenticating)
            central.emit(.disconnected(peripheral.identifier, isRemoteInitiated: true))
            #expect(await nextConnectionState(&iterator) == .waitingForReading)

            if attempt < G7SessionEngine.maxAuthStrikes {
                #expect(await nextConnectionState(&iterator) == .scanning)
            }
        }

        let end = await nextEvent(&iterator) {
            if case .sessionEnded(let reason) = $0 { reason } else { nil }
        }
        #expect(end == .suspectedEnd)
    }

    @Test func authenticatedConnectionResetsStrikes() async throws {
        let central = MockCentral()
        let engine = makeEngine(central: central) { _ in }
        var iterator = await engine.eventStream().makeAsyncIterator()
        let peripheral = MockPeripheral(name: "DXCM8T")

        await engine.start()
        central.emit(.stateChanged(.poweredOn))
        #expect(await nextConnectionState(&iterator) == .scanning)

        // Two strikes…
        for _ in 1...2 {
            central.emit(.discovered(peripheral: peripheral, name: "DXCM8T", rssi: -60))
            #expect(await nextConnectionState(&iterator) == .connecting)
            central.emit(.connected(peripheral.identifier))
            central.emit(.servicesReady(peripheral.identifier, success: true))
            #expect(await nextConnectionState(&iterator) == .authenticating)
            central.emit(.disconnected(peripheral.identifier, isRemoteInitiated: true))
            #expect(await nextConnectionState(&iterator) == .waitingForReading)
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

        // …so one more auth-pending disconnect must NOT end the session.
        central.emit(.disconnected(peripheral.identifier, isRemoteInitiated: true))
        #expect(await nextConnectionState(&iterator) == .waitingForReading)
        central.emit(.discovered(peripheral: peripheral, name: "DXCM8T", rssi: -60))

        let next = await nextEvent(&iterator) { event -> G7Event? in
            switch event {
            case .sessionEnded, .connectionStateChanged(.connecting): event
            default: nil
            }
        }
        #expect(next == .connectionStateChanged(.connecting))
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
}
