import Foundation
import Testing

@testable import DexcomKit

/// Regression tests for the findings of the multi-agent code review.
///
/// Each test pins the CORRECT behavior, so it fails against the code as
/// reviewed and passes once the finding is fixed. Tests are written to fail
/// fast — bounded polls and either/or event matchers — never to hang.
@Suite(.timeLimit(.minutes(1))) struct ReviewFindingsTests {
    let fixedNow = Date(timeIntervalSince1970: 1_750_300_000)

    // MARK: - Support

    func makeHarness(
        store: InMemoryStore = InMemoryStore()
    ) -> (central: MockCentral, store: InMemoryStore, engine: G7SessionEngine) {
        let central = MockCentral()
        let configuration = G7Configuration(store: store)
        let now = fixedNow
        let engine = G7SessionEngine(
            configuration: configuration, central: central, sleep: { _ in }, now: { now })
        return (central, store, engine)
    }

    /// Polls a condition, returning false instead of hanging.
    func poll(
        for duration: Duration = .seconds(2), _ condition: () -> Bool
    ) async throws -> Bool {
        let iterations = Int(duration / .milliseconds(2))
        for _ in 0..<iterations {
            if condition() { return true }
            try await Task.sleep(for: .milliseconds(2))
        }
        return condition()
    }

    /// Drives a fresh connection through authentication.
    func connect(
        central: MockCentral,
        peripheral: MockPeripheral,
        iterator: inout AsyncStream<G7Event>.AsyncIterator,
        discover: Bool = true
    ) async {
        if discover {
            central.emit(.discovered(peripheral: peripheral, name: peripheral.name, rssi: -60))
            #expect(await nextConnectionState(&iterator) == .connecting)
        }
        central.emit(.connected(peripheral.identifier))
        central.emit(.servicesReady(peripheral.identifier, success: true))
        #expect(await nextConnectionState(&iterator) == .authenticating)
        central.emit(
            .value(peripheral.identifier, characteristic: .authentication, data: G7Fixtures.authOK))
        #expect(await nextConnectionState(&iterator) == .connected)
    }

    /// A glucose message with a custom message timestamp and algorithm state.
    func glucoseBytes(timestamp: UInt32, state: UInt8 = 6) -> Data {
        var bytes = Data(G7Fixtures.glucose)
        bytes[2] = UInt8(timestamp & 0xFF)
        bytes[3] = UInt8((timestamp >> 8) & 0xFF)
        bytes[4] = UInt8((timestamp >> 16) & 0xFF)
        bytes[5] = UInt8((timestamp >> 24) & 0xFF)
        bytes[14] = state
        return bytes
    }

    // MARK: - Finding: falling trend-arrow boundaries must be inclusive

    /// Dexcom semantics (per G7SensorKit trendType): rate ≤ −3 is falling
    /// quickly, ≤ −2 falling, ≤ −1 falling slightly. A patient falling at
    /// exactly 3 mg/dL/min must see a double-down arrow.
    @Test func fallingTrendBoundariesAreInclusive() {
        #expect(TrendArrow(rate: -3.0) == .fallingQuickly)
        #expect(TrendArrow(rate: -2.0) == .falling)
        #expect(TrendArrow(rate: -1.0) == .fallingSlightly)
    }

    // MARK: - Finding: sensor sessionLength includes the grace period

    /// Real sensors report a session length that already contains the
    /// 12-hour grace period (a 10-day sensor reports 907 200 s = 10.5 d,
    /// per G7SensorKit's captured device bytes). Expiration is the reported
    /// length minus grace; the grace period ends when the reported length
    /// elapses.
    @Test func extendedVersionSessionLengthIncludesGracePeriod() throws {
        // Realistic 10-day sensor: sessionLength 907 200 s (0x0DD7C0).
        let realistic = Data(hex: "52 00 C0D70D00 5406 03020100 01 0C00")
        let message = try #require(ExtendedVersionMessage(data: realistic))
        #expect(message.sessionLength == 907_200)

        let activation = fixedNow
        let session = SensorSession(
            sensorName: "DXCM8T", activationDate: activation, extendedVersion: message)
        #expect(session.expirationDate == activation.addingTimeInterval(864_000))  // 10 days
        #expect(session.gracePeriodEndDate == activation.addingTimeInterval(907_200))  // 10.5 days
    }

    // MARK: - Finding: DX01 is not a G7-protocol device

    /// The original Dexcom ONE speaks the G6 protocol; adopting a DX01
    /// device would loop on service-discovery failures forever. G7SensorKit
    /// matches only DXCM and DX02.
    @Test func dx01IsNotAdoptable() {
        #expect(
            !AdoptionPolicy.shouldConnect(
                advertisedName: "DX01AB", selection: .automatic,
                followedSensorName: nil, sessionHasEnded: false))
    }

    // MARK: - Finding: backfill subscription order deviates from reference

    /// G7SensorKit subscribes to control immediately after authentication
    /// but to backfill only during glucose handling; matching the
    /// field-proven order keeps the short connection window predictable.
    @Test func backfillIsSubscribedAfterFirstGlucoseNotAtAuth() async throws {
        let (central, _, engine) = makeHarness()
        var iterator = await engine.eventStream().makeAsyncIterator()
        let peripheral = MockPeripheral(name: "DXCM8T")
        await engine.start()
        central.emit(.stateChanged(.poweredOn))
        #expect(await nextConnectionState(&iterator) == .scanning)
        await connect(central: central, peripheral: peripheral, iterator: &iterator)

        #expect(peripheral.calls(matching: .setNotify(true, .backfill)) == 0)

        central.emit(
            .value(peripheral.identifier, characteristic: .control, data: G7Fixtures.glucose))
        #expect(await nextReading(&iterator) != nil)
        let subscribed = try await poll {
            peripheral.calls(matching: .setNotify(true, .backfill)) == 1
        }
        #expect(subscribed)
    }

    // MARK: - Finding: session rollover deadlocks on the pending-connect
    // fast path

    /// After a session ends, the engine must not pin the dead sensor via
    /// retrievePeripherals: a replacement sensor's advertisement has to win.
    @Test func replacementSensorIsAdoptedAfterSessionEnd() async throws {
        let (central, _, engine) = makeHarness()
        var iterator = await engine.eventStream().makeAsyncIterator()
        let old = MockPeripheral(name: "DXCM8T")
        central.knownPeripherals[old.identifier] = old

        await engine.start()
        central.emit(.stateChanged(.poweredOn))
        #expect(await nextConnectionState(&iterator) == .scanning)
        await connect(central: central, peripheral: old, iterator: &iterator)

        // Adopt, then expire the session.
        central.emit(
            .value(
                peripheral: old, characteristic: .control,
                data: glucoseBytes(timestamp: 300_000, state: AlgorithmState.State.expired.rawValue)
            ))
        let end = await nextEvent(&iterator) {
            if case .sessionEnded(let reason) = $0 { reason } else { nil }
        }
        #expect(end == .expired)

        // The dead sensor hangs up; the engine rescans.
        central.emit(.disconnected(old.identifier, isRemoteInitiated: true))
        #expect(await nextConnectionState(&iterator) == .waitingForReading)
        #expect(await nextConnectionState(&iterator) == .scanning)

        // The replacement advertises. It must be connected even though the
        // old sensor is retrievable.
        let replacement = MockPeripheral(name: "DXCM9Q")
        central.emit(
            .discovered(peripheral: replacement, name: "DXCM9Q", rssi: -55))
        let connected = try await poll {
            central.calls(matching: .connect(replacement.identifier)) == 1
        }
        #expect(connected, "replacement sensor was never connected — rollover is wedged")
    }

    // MARK: - Finding: restoration acts before the central is powered on

    /// CoreBluetooth delivers willRestoreState before poweredOn; issuing
    /// connect/discover commands in that window silently drops them. The
    /// engine must defer restored-peripheral handling until poweredOn.
    @Test func restoredPeripheralIsHandledAfterPowerOn() async throws {
        let store = InMemoryStore()
        let peripheral = MockPeripheral(name: "DXCM8T")
        peripheral.isConnected = true
        store.saveFollowedSensor(
            FollowedSensor(
                name: "DXCM8T", peripheralIdentifier: peripheral.identifier,
                activationDate: fixedNow.addingTimeInterval(-300_000)))
        let (central, _, engine) = makeHarness(store: store)
        await engine.start()

        // Restoration arrives first, as it does in production.
        central.emit(.willRestore(peripherals: [peripheral]))
        try await Task.sleep(for: .milliseconds(100))
        #expect(
            peripheral.calls(matching: .discoverG7Services) == 0,
            "acted on a restored peripheral before the central was powered on")

        central.emit(.stateChanged(.poweredOn))
        let discovered = try await poll {
            peripheral.calls(matching: .discoverG7Services) == 1
        }
        #expect(discovered, "restored peripheral was never resumed after power-on")
    }

    // MARK: - Finding: suspected session end reported with no session

    /// Three auth-pending disconnects from a sensor that was never adopted
    /// (e.g. a neighbor's sensor under .automatic) must not emit
    /// sessionEnded — there is no session to end.
    @Test func suspectedEndRequiresAFollowedSensor() async throws {
        let (central, _, engine) = makeHarness()
        var iterator = await engine.eventStream().makeAsyncIterator()
        let stranger = MockPeripheral(name: "DXCM3Z")

        await engine.start()
        central.emit(.stateChanged(.poweredOn))
        #expect(await nextConnectionState(&iterator) == .scanning)

        for _ in 1...G7SessionEngine.maxAuthStrikes {
            central.emit(.discovered(peripheral: stranger, name: "DXCM3Z", rssi: -80))
            #expect(await nextConnectionState(&iterator) == .connecting)
            central.emit(.connected(stranger.identifier))
            central.emit(.servicesReady(stranger.identifier, success: true))
            #expect(await nextConnectionState(&iterator) == .authenticating)
            central.emit(.disconnected(stranger.identifier, isRemoteInitiated: true))

            // The next event must be the state change, not a sessionEnded.
            let next = await nextEvent(&iterator) { event -> G7Event? in
                switch event {
                case .sessionEnded, .connectionStateChanged(.waitingForReading): event
                default: nil
                }
            }
            #expect(next == .connectionStateChanged(.waitingForReading))
            if case .sessionEnded = next { break }
            #expect(await nextConnectionState(&iterator) == .scanning)
        }
    }

    // MARK: - Finding: auth rejection reported once per process, not per
    // connection

    /// On the known-peripheral fast path (the normal reconnect path once a
    /// sensor is followed), authenticationRejected must be re-reported on
    /// each connection, or an app can never surface a persistent
    /// "re-pair with the Dexcom app" prompt.
    @Test func authRejectionIsReportedOnEveryConnection() async throws {
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

        let rejection = Data([0x05, 0x00, 0x00])
        for connection in 1...2 {
            central.emit(.connected(peripheral.identifier))
            central.emit(.servicesReady(peripheral.identifier, success: true))
            #expect(await nextConnectionState(&iterator) == .authenticating)
            central.emit(
                .value(peripheral.identifier, characteristic: .authentication, data: rejection))
            central.emit(.disconnected(peripheral.identifier, isRemoteInitiated: true))

            // Either the rejection error (correct) or the disconnect's state
            // change (meaning the error was swallowed) arrives next.
            let next = await nextEvent(&iterator) { event -> G7Event? in
                switch event {
                case .error, .connectionStateChanged(.waitingForReading): event
                default: nil
                }
            }
            #expect(
                next == .error(.authenticationRejected),
                "rejection on connection \(connection) was not reported")
            if next != .error(.authenticationRejected) { break }
            #expect(await nextConnectionState(&iterator) == .waitingForReading)
            #expect(await nextConnectionState(&iterator) == .scanning)
        }
    }

    // MARK: - Finding: extended version is never re-requested after a lost
    // response

    /// The sensor can hang up before answering the extended-version request
    /// (its window is seconds long); the engine must retry on the next
    /// connection until a response arrives.
    @Test func extendedVersionIsRerequestedUntilAResponseArrives() async throws {
        let (central, _, engine) = makeHarness()
        var iterator = await engine.eventStream().makeAsyncIterator()
        let peripheral = MockPeripheral(name: "DXCM8T")
        await engine.start()
        central.emit(.stateChanged(.poweredOn))
        #expect(await nextConnectionState(&iterator) == .scanning)
        await connect(central: central, peripheral: peripheral, iterator: &iterator)

        central.emit(
            .value(
                peripheral: peripheral, characteristic: .control,
                data: glucoseBytes(timestamp: 300_000)))
        #expect(await nextReading(&iterator) != nil)
        #expect(peripheral.calls(matching: .write(ExtendedVersionMessage.request, .control)) == 1)

        // Sensor hangs up without answering; next connection, next reading.
        central.emit(.disconnected(peripheral.identifier, isRemoteInitiated: true))
        #expect(await nextConnectionState(&iterator) == .waitingForReading)
        #expect(await nextConnectionState(&iterator) == .scanning)
        await connect(central: central, peripheral: peripheral, iterator: &iterator)
        central.emit(
            .value(
                peripheral: peripheral, characteristic: .control,
                data: glucoseBytes(timestamp: 300_300)))
        #expect(await nextReading(&iterator) != nil)

        let retried = try await poll {
            peripheral.calls(matching: .write(ExtendedVersionMessage.request, .control)) == 2
        }
        #expect(retried, "extended version was never re-requested after the lost response")
    }

    // MARK: - Finding: stale backfill survives forgetSensor and is
    // attributed to the next sensor

    /// Backfill buffered from a forgotten sensor must not be delivered as
    /// the replacement sensor's readings (wrong activation anchor, and it
    /// poisons the dedupe set).
    @Test func staleBackfillDoesNotLeakAcrossForget() async throws {
        let (central, _, engine) = makeHarness()
        var iterator = await engine.eventStream().makeAsyncIterator()
        let old = MockPeripheral(name: "DXCM8T")
        await engine.start()
        central.emit(.stateChanged(.poweredOn))
        #expect(await nextConnectionState(&iterator) == .scanning)
        await connect(central: central, peripheral: old, iterator: &iterator)

        // Adopt and buffer a backfill record, then forget mid-stream.
        central.emit(
            .value(peripheral: old, characteristic: .control, data: glucoseBytes(timestamp: 300_000))
        )
        #expect(await nextReading(&iterator) != nil)
        central.emit(
            .value(
                peripheral: old, characteristic: .backfill,
                data: backfillRecordBytes(timestamp: 299_400)))
        await engine.forgetSensor()
        #expect(await nextConnectionState(&iterator) == .scanning)

        // Adopt the replacement, then complete a backfill stream that sent
        // no records of its own.
        let replacement = MockPeripheral(name: "DXCM9Q")
        await connect(central: central, peripheral: replacement, iterator: &iterator)
        central.emit(
            .value(
                peripheral: replacement, characteristic: .control,
                data: glucoseBytes(timestamp: 10_000)))
        #expect(await nextReading(&iterator) != nil)
        central.emit(
            .value(peripheral: replacement, characteristic: .control, data: Data([0x59])))
        central.emit(
            .value(peripheral: replacement, characteristic: .control, data: Data([0x28])))

        let next = await nextEvent(&iterator) { event -> G7Event? in
            switch event {
            case .backfill, .sessionEnded: event
            default: nil
            }
        }
        #expect(
            next == .sessionEnded(.stopped),
            "the forgotten sensor's backfill leaked into the new session")
    }

    // MARK: - Finding: failed notify subscription leaves a silent dead
    // connection

    /// A failed control-characteristic subscription means no readings will
    /// ever arrive; the engine must surface an error and reconnect rather
    /// than sit in `.connected`.
    @Test func failedSubscriptionSurfacesAnErrorAndReconnects() async throws {
        let (central, _, engine) = makeHarness()
        var iterator = await engine.eventStream().makeAsyncIterator()
        let peripheral = MockPeripheral(name: "DXCM8T")
        await engine.start()
        central.emit(.stateChanged(.poweredOn))
        #expect(await nextConnectionState(&iterator) == .scanning)
        await connect(central: central, peripheral: peripheral, iterator: &iterator)

        central.emit(
            .notificationState(
                peripheral.identifier, characteristic: .control, enabled: true, success: false))
        // A glucose message afterwards acts as the sync marker: if the
        // failure was swallowed, the session establishes as if all is well.
        central.emit(
            .value(
                peripheral: peripheral, characteristic: .control,
                data: glucoseBytes(timestamp: 300_000)))

        let next = await nextEvent(&iterator) { event -> G7Event? in
            switch event {
            case .error, .sessionEstablished: event
            default: nil
            }
        }
        guard case .error = next else {
            Issue.record("subscription failure was swallowed; got \(String(describing: next))")
            return
        }
    }
}

extension BluetoothEvent {
    /// Convenience initializer used by the review-findings tests.
    static func value(
        peripheral: MockPeripheral, characteristic: G7Characteristic, data: Data
    ) -> BluetoothEvent {
        .value(peripheral.identifier, characteristic: characteristic, data: data)
    }
}
