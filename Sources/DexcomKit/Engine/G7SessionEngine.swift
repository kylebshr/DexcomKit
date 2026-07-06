import Foundation

/// The session state machine: consumes ``BluetoothEvent``s from a
/// ``CentralManaging``, drives discovery → connection → authentication →
/// subscription, and emits ``G7Event``s to consumers.
///
/// Everything is serialized by actor isolation — the engine processes one
/// Bluetooth event at a time, so there are no locks and no partially applied
/// state transitions.
///
/// The connection loop mirrors LoopKit/G7SensorKit's field-proven flow: the
/// sensor advertises about every 5 minutes, holds the connection for a few
/// seconds while it delivers data, then disconnects itself; after every
/// disconnect the engine waits ~2 seconds and rescans so it's listening
/// before the next advertisement.
actor G7SessionEngine {
    typealias SleepFunction = @Sendable (Duration) async throws -> Void

    /// How long to wait after a disconnect before rescanning, giving the
    /// sensor time to finish shutting down its connection.
    static let rescanDelay: Duration = .seconds(2)

    /// Remote disconnects while authentication is still pending before the
    /// engine concludes the followed session has probably ended.
    static let maxAuthStrikes = 3

    private let configuration: G7Configuration
    private let central: any CentralManaging
    private let broadcaster = EventBroadcaster<G7Event>()
    private let sleep: SleepFunction
    private let now: @Sendable () -> Date

    private var isStarted = false
    private var centralReady = false
    private var connectionState: G7ConnectionState = .idle

    private var followedSensor: FollowedSensor?
    private var session: SensorSession?
    private var sessionEndReported = false

    private var currentPeripheral: (any PeripheralLink)?
    private var currentSensorName: String?
    private var isAuthenticating = false
    private var authStrikes = 0
    private var seenOffsets: Set<UInt32> = []
    private var backfill = BackfillAssembler()

    // Per-connection flags, reset when a connection is established.
    private var authRejectionReported = false
    private var requestedExtendedVersion = false
    private var subscribedBackfill = false

    /// Peripherals restored by iOS before the central reported powered-on;
    /// acting on them earlier would silently drop the commands.
    private var pendingRestoredPeripherals: [any PeripheralLink] = []

    private var eventLoopTask: Task<Void, Never>?
    private var rescanTask: Task<Void, Never>?

    init(
        configuration: G7Configuration,
        central: any CentralManaging,
        sleep: @escaping SleepFunction = { try await Task.sleep(for: $0) },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.configuration = configuration
        self.central = central
        self.sleep = sleep
        self.now = now
    }

    // MARK: - Public surface (used by G7SensorMonitor)

    var currentConnectionState: G7ConnectionState { connectionState }
    var currentSession: SensorSession? { session }

    /// A new independent stream of all future events.
    func eventStream() async -> AsyncStream<G7Event> {
        await broadcaster.stream()
    }

    /// The number of active event-stream consumers. For tests.
    func eventSubscriberCount() async -> Int {
        await broadcaster.subscriberCount
    }

    func start() async {
        guard !isStarted else { return }
        isStarted = true
        Log.connection.info("Engine starting")

        // Commit all state and side effects before the first suspension so
        // a concurrent stop() can't interleave with a half-started engine.
        followedSensor = configuration.store.loadFollowedSensor()
        sessionEndReported = followedSensor?.sessionEnded ?? false
        var resumedSession: SensorSession?
        if let followed = followedSensor {
            Log.session.info(
                "Resuming followed sensor \(followed.name, privacy: .private)")
            currentSensorName = followed.name
            resumedSession = SensorSession(followed: followed)
            session = resumedSession
        }

        let events = central.events()
        eventLoopTask = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                await self.handle(event)
            }
        }
        central.start()

        if let resumedSession {
            await emit(.sessionEstablished(resumedSession))
        }
    }

    func stop() async {
        guard isStarted else { return }
        isStarted = false
        Log.connection.info("Engine stopping")

        rescanTask?.cancel()
        rescanTask = nil
        eventLoopTask?.cancel()
        eventLoopTask = nil
        central.stopScan()
        if let peripheral = currentPeripheral {
            central.cancelConnection(peripheral)
        }
        currentPeripheral = nil
        isAuthenticating = false
        pendingRestoredPeripherals = []
        await setState(.idle)
    }

    /// Clears the followed sensor so the next scan adopts fresh.
    func forgetSensor() async {
        Log.session.info("Forgetting followed sensor")
        followedSensor = nil
        session = nil
        currentSensorName = nil
        seenOffsets.removeAll()
        backfill = BackfillAssembler()
        authStrikes = 0
        sessionEndReported = false
        configuration.store.saveFollowedSensor(nil)

        if let peripheral = currentPeripheral {
            central.cancelConnection(peripheral)
            currentPeripheral = nil
            isAuthenticating = false
        }
        if isStarted, centralReady {
            await beginScanning()
        }
    }

    // MARK: - Event loop

    private func handle(_ event: BluetoothEvent) async {
        switch event {
        case .stateChanged(let state):
            await handleStateChange(state)
        case .discovered(let peripheral, let name, let rssi):
            await handleDiscovery(peripheral, advertisedName: name, rssi: rssi)
        case .connected(let id):
            await handleConnected(id)
        case .failedToConnect(let id):
            await handleFailedToConnect(id)
        case .disconnected(let id, let isRemoteInitiated):
            await handleDisconnected(id, isRemoteInitiated: isRemoteInitiated)
        case .servicesReady(let id, let success):
            await handleServicesReady(id, success: success)
        case .notificationState(let id, let characteristic, let enabled, let success):
            await handleNotificationState(
                id, characteristic: characteristic, enabled: enabled, success: success)
        case .value(let id, let characteristic, let data):
            await handleValue(id, characteristic: characteristic, data: data)
        case .willRestore(let peripherals):
            await handleRestore(peripherals)
        }
    }

    private func handleStateChange(_ state: CentralState) async {
        switch state {
        case .poweredOn:
            Log.connection.info("Bluetooth powered on")
            centralReady = true
            guard isStarted else { return }
            if !pendingRestoredPeripherals.isEmpty {
                await adoptRestoredPeripherals()
            }
            if currentPeripheral == nil {
                await beginScanning()
            }
        case .unavailable(let reason):
            Log.connection.error(
                "Bluetooth unavailable: \(String(describing: reason), privacy: .public)")
            centralReady = false
            rescanTask?.cancel()
            rescanTask = nil
            currentPeripheral = nil
            isAuthenticating = false
            await setState(.bluetoothUnavailable(reason))
        }
    }

    private func beginScanning() async {
        guard isStarted, centralReady else { return }

        // Fast path: ask for the known peripheral and issue a pending
        // connect, which completes whenever the sensor next advertises —
        // no scan latency, and it works from background wakes. Skipped once
        // the session has ended so a replacement sensor's advertisement can
        // win instead of pinning the dead sensor forever.
        if currentPeripheral == nil,
            !sessionEndReported,
            let followed = followedSensor,
            let known = central.retrieveKnownPeripheral(
                withIdentifier: followed.peripheralIdentifier)
        {
            Log.connection.info("Issuing pending connect to known peripheral")
            currentPeripheral = known
            currentSensorName = followed.name
            central.connect(known)
        }

        Log.discovery.info("Scanning for sensors")
        central.scanForSensors()
        await setState(.scanning)
    }

    private func handleDiscovery(
        _ peripheral: any PeripheralLink, advertisedName: String?, rssi: Int
    ) async {
        guard isStarted else { return }
        let name = advertisedName ?? peripheral.name

        if let current = currentPeripheral {
            // Normally advertisements are ignored while connecting or
            // connected. The exception: the followed session has ended and
            // a different, adoptable sensor appears — a replacement must be
            // able to take over from a pending connect to the dead sensor.
            guard
                sessionEndReported,
                peripheral.identifier != current.identifier,
                AdoptionPolicy.shouldConnect(
                    advertisedName: name,
                    selection: configuration.selection,
                    followedSensorName: followedSensor?.name,
                    sessionHasEnded: true)
            else { return }
            Log.discovery.info("Replacement sensor found; abandoning ended session's connection")
            central.cancelConnection(current)
        } else {
            let shouldConnect = AdoptionPolicy.shouldConnect(
                advertisedName: name,
                selection: configuration.selection,
                followedSensorName: followedSensor?.name,
                sessionHasEnded: sessionEndReported
            )
            guard shouldConnect else {
                Log.discovery.debug(
                    "Ignoring peripheral \(name ?? "<unnamed>", privacy: .private) rssi \(rssi, privacy: .public)"
                )
                return
            }
        }

        Log.discovery.info(
            "Connecting to \(name ?? "<unnamed>", privacy: .private) rssi \(rssi, privacy: .public)"
        )
        central.stopScan()
        currentPeripheral = peripheral
        currentSensorName = name
        central.connect(peripheral)
        await setState(.connecting)
    }

    private func handleConnected(_ id: UUID) async {
        guard let peripheral = currentPeripheral, peripheral.identifier == id else { return }
        Log.connection.info("Connected; discovering services")
        central.stopScan()
        // Fresh connection: per-connection reporting and request flags reset.
        authRejectionReported = false
        requestedExtendedVersion = false
        subscribedBackfill = false
        await setState(.connecting)
        peripheral.discoverG7Services()
    }

    private func handleServicesReady(_ id: UUID, success: Bool) async {
        guard let peripheral = currentPeripheral, peripheral.identifier == id else { return }
        guard success else {
            Log.connection.error("Service discovery failed")
            await emit(.error(.serviceDiscoveryFailed))
            await disconnectAndRescan()
            return
        }
        Log.connection.info("Services ready; awaiting authentication status")
        isAuthenticating = true
        peripheral.setNotify(true, for: .authentication)
        await setState(.authenticating)
    }

    private func handleNotificationState(
        _ id: UUID, characteristic: G7Characteristic, enabled: Bool, success: Bool
    ) async {
        guard currentPeripheral?.identifier == id else { return }
        guard success else {
            Log.connection.error(
                "Notify \(enabled, privacy: .public) failed for \(String(describing: characteristic), privacy: .public)"
            )
            // A required subscription failing means no data will arrive on
            // this connection; surface it and try again.
            if enabled {
                await emit(.error(.subscriptionFailed))
                await disconnectAndRescan()
            }
            return
        }
        Log.connection.debug(
            "Notify \(enabled, privacy: .public) confirmed for \(String(describing: characteristic), privacy: .public)"
        )
    }

    private func handleValue(_ id: UUID, characteristic: G7Characteristic, data: Data) async {
        guard currentPeripheral?.identifier == id else { return }

        switch MessageRouter.route(data, from: characteristic) {
        case .authStatus(let message):
            await handleAuthStatus(message)
        case .glucose(let message):
            await handleGlucose(message)
        case .extendedVersion(let message):
            await handleExtendedVersion(message)
        case .backfillFinished:
            Log.backfill.info(
                "Backfill stream finished with \(self.backfill.count, privacy: .public) records")
            await flushBackfill()
        case .sessionStopped:
            Log.session.info("Sensor reported session stop")
            await reportSessionEnd(.stopped)
        case .backfillRecords(let records):
            guard configuration.backfillEnabled else { return }
            Log.backfill.debug("Buffered \(records.count, privacy: .public) backfill records")
            backfill.append(records)
        case .unrecognized(let opcode):
            Log.messages.debug(
                "Unrecognized opcode \(opcode.map(String.init) ?? "none", privacy: .public) on \(String(describing: characteristic), privacy: .public)"
            )
        case .malformed(let opcode):
            Log.messages.error(
                "Malformed message, opcode \(opcode.map(String.init) ?? "none", privacy: .public) on \(String(describing: characteristic), privacy: .public), \(data.count, privacy: .public) bytes"
            )
        }
    }

    private func handleAuthStatus(_ message: AuthStatusMessage) async {
        guard let peripheral = currentPeripheral else { return }

        guard message.isAuthenticated, message.isBonded else {
            Log.connection.error(
                "Sensor has no authenticated session (authenticated: \(message.isAuthenticated, privacy: .public), bonded: \(message.isBonded, privacy: .public))"
            )
            // Stay connected — the status can update within this connection
            // window. Report once per connection attempt.
            if !authRejectionReported {
                authRejectionReported = true
                await emit(.error(.authenticationRejected))
            }
            return
        }

        Log.connection.info("Sensor session authenticated; subscribing to glucose")
        isAuthenticating = false
        authStrikes = 0
        // Control only; backfill is subscribed during glucose handling,
        // matching the G7SensorKit reference order.
        peripheral.setNotify(true, for: .control)
        await setState(.connected)
    }

    private func handleGlucose(_ message: GlucoseMessage) async {
        guard let peripheral = currentPeripheral else { return }
        guard let name = currentSensorName ?? peripheral.name else {
            Log.messages.error("Glucose from a nameless peripheral; ignoring")
            return
        }

        // Adopt (or roll over to) this sensor on its first authenticated
        // glucose message. The activation date anchors all readings:
        // activation = now − seconds-since-activation.
        if followedSensor?.name != name {
            let activation = now().addingTimeInterval(-TimeInterval(message.messageTimestamp))
            let adopted = FollowedSensor(
                name: name,
                peripheralIdentifier: peripheral.identifier,
                activationDate: activation
            )
            Log.session.info(
                "Adopting sensor \(name, privacy: .private), activated \(activation, privacy: .private)"
            )
            followedSensor = adopted
            configuration.store.saveFollowedSensor(adopted)
            seenOffsets.removeAll()
            backfill = BackfillAssembler()
            authStrikes = 0
            sessionEndReported = false
            let session = SensorSession(followed: adopted)
            self.session = session
            await emit(.sessionEstablished(session))
        } else if var followed = followedSensor,
            followed.peripheralIdentifier != peripheral.identifier
        {
            // Same sensor, new peripheral identifier — keep the fast
            // reconnect path working.
            followed.peripheralIdentifier = peripheral.identifier
            followedSensor = followed
            configuration.store.saveFollowedSensor(followed)
        }

        guard let followed = followedSensor else { return }

        let reading = GlucoseReading(
            message: message, sensorName: followed.name, activationDate: followed.activationDate)
        if seenOffsets.insert(reading.timestampOffset).inserted {
            Log.messages.info(
                "Reading at offset \(reading.timestampOffset, privacy: .public): \(reading.glucose.map(String.init) ?? "none", privacy: .private) mg/dL, state \(message.algorithmState.rawValue, privacy: .public)"
            )
            await emit(.reading(reading))
        } else {
            Log.messages.debug(
                "Duplicate reading at offset \(reading.timestampOffset, privacy: .public)")
        }

        // Backfill is subscribed here, after the first reading of the
        // connection, matching the reference implementation.
        if configuration.backfillEnabled, !subscribedBackfill {
            subscribedBackfill = true
            peripheral.setNotify(true, for: .backfill)
        }

        // Request session parameters until the sensor has answered once;
        // the response is persisted, so this stops across launches too.
        if followed.sessionLength == nil, !requestedExtendedVersion {
            requestedExtendedVersion = true
            Log.session.debug("Requesting extended version")
            peripheral.write(ExtendedVersionMessage.request, to: .control)
        }

        if message.algorithmState.indicatesSensorFailure {
            await reportSessionEnd(.failed)
        } else if message.algorithmState.indicatesSessionEnd {
            await reportSessionEnd(
                message.algorithmState == .known(.stopped) ? .stopped : .expired)
        }
    }

    private func handleExtendedVersion(_ message: ExtendedVersionMessage) async {
        guard var followed = followedSensor else { return }
        Log.session.info(
            "Extended version: session \(message.sessionLength, privacy: .public)s, warmup \(message.warmupLength, privacy: .public)s, max lifetime \(message.maxLifetimeDays, privacy: .public)d"
        )
        followed.sessionLength = message.sessionLength
        followed.warmupLength = message.warmupLength
        followed.algorithmVersion = message.algorithmVersion
        followedSensor = followed
        configuration.store.saveFollowedSensor(followed)

        let session = SensorSession(followed: followed)
        self.session = session
        await emit(.sessionEstablished(session))
    }

    private func flushBackfill() async {
        guard let followed = followedSensor else {
            // Records without a session can't be attributed to anything.
            backfill = BackfillAssembler()
            return
        }
        guard !backfill.isEmpty else { return }
        let readings = backfill.flush()
            .map {
                GlucoseReading(
                    record: $0, sensorName: followed.name,
                    activationDate: followed.activationDate)
            }
            .filter { seenOffsets.insert($0.timestampOffset).inserted }
        guard !readings.isEmpty else { return }
        Log.backfill.info("Delivering \(readings.count, privacy: .public) backfilled readings")
        await emit(.backfill(readings))
    }

    private func handleFailedToConnect(_ id: UUID) async {
        guard currentPeripheral?.identifier == id else { return }
        Log.connection.error("Failed to connect")
        currentPeripheral = nil
        isAuthenticating = false
        guard isStarted, centralReady else { return }
        await scheduleRescan()
    }

    private func handleDisconnected(_ id: UUID, isRemoteInitiated: Bool) async {
        guard currentPeripheral?.identifier == id else { return }
        Log.connection.info(
            "Disconnected (remote: \(isRemoteInitiated, privacy: .public))")
        currentPeripheral = nil

        if isAuthenticating, isRemoteInitiated {
            authStrikes += 1
            Log.connection.info(
                "Disconnected before authentication (\(self.authStrikes, privacy: .public)/\(Self.maxAuthStrikes, privacy: .public))"
            )
            if authStrikes >= Self.maxAuthStrikes {
                authStrikes = 0
                await reportSessionEnd(.suspectedEnd)
            }
        }
        isAuthenticating = false

        // If the sensor disconnected mid-backfill, deliver what we have.
        await flushBackfill()

        guard isStarted, centralReady else { return }
        await scheduleRescan()
    }

    private func handleRestore(_ peripherals: [any PeripheralLink]) async {
        Log.connection.info("Restoring \(peripherals.count, privacy: .public) peripherals")
        pendingRestoredPeripherals = peripherals
        // CoreBluetooth delivers willRestoreState before poweredOn; commands
        // issued before the central is ready are silently dropped, so defer
        // until the powered-on state arrives.
        if centralReady {
            await adoptRestoredPeripherals()
        }
    }

    private func adoptRestoredPeripherals() async {
        let peripherals = pendingRestoredPeripherals
        pendingRestoredPeripherals = []

        for peripheral in peripherals {
            let name = peripheral.name
            let shouldAdopt =
                currentPeripheral == nil
                && AdoptionPolicy.shouldConnect(
                    advertisedName: name,
                    selection: configuration.selection,
                    followedSensorName: followedSensor?.name,
                    sessionHasEnded: sessionEndReported
                )
            guard shouldAdopt else {
                // Leave nothing dangling: an unadopted restored connection
                // would hold the sensor's connection slot.
                if peripheral.isConnected {
                    central.cancelConnection(peripheral)
                }
                continue
            }

            currentPeripheral = peripheral
            currentSensorName = name
            authRejectionReported = false
            requestedExtendedVersion = false
            subscribedBackfill = false
            if peripheral.isConnected {
                Log.connection.info("Restored a connected peripheral; discovering services")
                peripheral.discoverG7Services()
            } else {
                Log.connection.info("Restored a disconnected peripheral; reconnecting")
                central.connect(peripheral)
            }
            await setState(.connecting)
        }
    }

    // MARK: - Rescan loop

    private func disconnectAndRescan() async {
        if let peripheral = currentPeripheral {
            central.cancelConnection(peripheral)
        }
        currentPeripheral = nil
        isAuthenticating = false
        guard isStarted, centralReady else { return }
        await scheduleRescan()
    }

    private func scheduleRescan() async {
        rescanTask?.cancel()
        await setState(.waitingForReading)
        Log.connection.debug(
            "Rescanning in \(String(describing: Self.rescanDelay), privacy: .public)")
        rescanTask = Task { [weak self, sleep] in
            guard (try? await sleep(Self.rescanDelay)) != nil else { return }
            await self?.rescanNow()
        }
    }

    private func rescanNow() async {
        guard isStarted, centralReady, currentPeripheral == nil else { return }
        await beginScanning()
    }

    // MARK: - Emission

    private func setState(_ state: G7ConnectionState) async {
        guard state != connectionState else { return }
        Log.connection.info(
            "State: \(self.connectionState, privacy: .public) → \(state, privacy: .public)")
        connectionState = state
        await emit(.connectionStateChanged(state))
    }

    private func reportSessionEnd(_ reason: SessionEndReason) async {
        // A session end is only meaningful for a followed sensor; strikes
        // against never-adopted sensors (e.g. a neighbor's) say nothing.
        guard !sessionEndReported, var followed = followedSensor else { return }
        sessionEndReported = true
        followed.sessionEnded = true
        followedSensor = followed
        configuration.store.saveFollowedSensor(followed)
        Log.session.info(
            "Session ended: \(String(describing: reason), privacy: .public)")
        await emit(.sessionEnded(reason))
    }

    private func emit(_ event: G7Event) async {
        await broadcaster.yield(event)
    }
}

extension SensorSession {
    /// Rebuilds session lifecycle dates from persisted sensor state.
    init(followed: FollowedSensor) {
        self.init(
            sensorName: followed.name,
            activationDate: followed.activationDate,
            sessionLength: followed.sessionLength.map(TimeInterval.init),
            warmupLength: followed.warmupLength.map(TimeInterval.init),
            algorithmVersion: followed.algorithmVersion
        )
    }
}
