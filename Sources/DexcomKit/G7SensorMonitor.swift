import Foundation
import Observation

/// The public entry point: follows a Dexcom G7 sensor and delivers its
/// readings.
///
/// The monitor exposes two complementary surfaces:
///
/// - **Snapshot state** (`connectionState`, `latestReading`, `session`) —
///   observable properties for SwiftUI views and Live Activity content.
/// - **Event streams** (``events()``, ``readings()``) — push delivery of
///   every discrete event; each call returns an independent stream, so any
///   number of consumers can listen concurrently.
///
/// ```swift
/// let monitor = G7SensorMonitor()
/// try monitor.start()
///
/// Task {
///     for await reading in monitor.readings() {
///         print(reading.glucose ?? 0, reading.trendArrow ?? .steady)
///     }
/// }
/// ```
///
/// > Important: DexcomKit runs as a *follower*: the sensor must already be
/// > paired with the official Dexcom app (or a Dexcom receiver). DexcomKit
/// > never pairs or bonds; it listens alongside the existing session.
///
/// The consuming app must declare `NSBluetoothAlwaysUsageDescription` and,
/// for background delivery, the `bluetooth-central` background mode.
@Observable @MainActor
public final class G7SensorMonitor {
    /// The current connection to the sensor.
    ///
    /// ``G7ConnectionState/waitingForReading`` is the normal resting state
    /// of a healthy session — the sensor only connects for a few seconds
    /// around each ~5-minute reading.
    public private(set) var connectionState: G7ConnectionState = .idle

    /// The most recent reading, real-time or backfilled.
    public private(set) var latestReading: GlucoseReading?

    /// The lifecycle of the sensor session being followed.
    public private(set) var session: SensorSession?

    @ObservationIgnored private let configuration: G7Configuration
    @ObservationIgnored private let engine: G7SessionEngine
    @ObservationIgnored private var mirrorTask: Task<Void, Never>?
    @ObservationIgnored private var isStarted = false

    /// Creates a monitor backed by CoreBluetooth.
    public convenience init(configuration: G7Configuration = G7Configuration()) {
        self.init(
            configuration: configuration,
            central: CoreBluetoothCentral(restoreIdentifier: configuration.restoreIdentifier)
        )
    }

    /// Testable entry point: injects the Bluetooth implementation.
    init(
        configuration: G7Configuration,
        central: any CentralManaging,
        sleep: @escaping G7SessionEngine.SleepFunction = { try await Task.sleep(for: $0) },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.configuration = configuration
        self.engine = G7SessionEngine(
            configuration: configuration, central: central, sleep: sleep, now: now)
    }

    deinit {
        mirrorTask?.cancel()
    }

    /// Starts scanning for and following the sensor.
    ///
    /// - Throws: ``DexcomError/invalidConfiguration(_:)`` if the
    ///   configuration can't be used; nothing else.
    public func start() throws {
        if case .nameSuffix(let suffix) = configuration.selection,
            suffix.trimmingCharacters(in: .whitespaces).isEmpty
        {
            throw DexcomError.invalidConfiguration("nameSuffix must not be empty")
        }
        guard !isStarted else { return }
        isStarted = true

        if mirrorTask == nil {
            // Subscribe before starting the engine so the initial events
            // (like a resumed session) aren't missed. Self is only held
            // strongly per event, so an abandoned monitor can deinit.
            let engine = engine
            mirrorTask = Task { [weak self] in
                let events = await engine.eventStream()
                await engine.start()
                for await event in events {
                    guard let self else { return }
                    self.apply(event)
                }
            }
        } else {
            let engine = engine
            Task { await engine.start() }
        }
    }

    /// Stops scanning and disconnects. The followed sensor stays persisted;
    /// ``start()`` resumes it.
    public func stop() {
        guard isStarted else { return }
        isStarted = false
        let engine = engine
        Task { await engine.stop() }
    }

    /// Forgets the followed sensor so the next scan adopts fresh — for
    /// example when replacing a sensor early.
    public func forgetSensor() {
        latestReading = nil
        session = nil
        let engine = engine
        Task { await engine.forgetSensor() }
    }

    /// A new independent stream of everything the monitor reports, in order.
    ///
    /// Streams deliver only future events; read the snapshot properties for
    /// current state. Iteration ends when the consumer's task is cancelled.
    public func events() -> AsyncStream<G7Event> {
        let engine = engine
        let (stream, continuation) = AsyncStream<G7Event>.makeStream()
        let pump = Task {
            for await event in await engine.eventStream() {
                continuation.yield(event)
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in pump.cancel() }
        return stream
    }

    /// A new independent stream of just the readings — real-time and
    /// backfilled, with backfill batches flattened in timestamp order.
    public func readings() -> AsyncStream<GlucoseReading> {
        let engine = engine
        let (stream, continuation) = AsyncStream<GlucoseReading>.makeStream()
        let pump = Task {
            for await event in await engine.eventStream() {
                switch event {
                case .reading(let reading):
                    continuation.yield(reading)
                case .backfill(let readings):
                    for reading in readings {
                        continuation.yield(reading)
                    }
                default:
                    break
                }
            }
            continuation.finish()
        }
        continuation.onTermination = { _ in pump.cancel() }
        return stream
    }

    private func apply(_ event: G7Event) {
        switch event {
        case .connectionStateChanged(let state):
            connectionState = state
        case .reading(let reading):
            if reading.date >= (latestReading?.date ?? .distantPast) {
                latestReading = reading
            }
        case .backfill(let readings):
            if let last = readings.last, last.date >= (latestReading?.date ?? .distantPast) {
                latestReading = last
            }
        case .sessionEstablished(let session):
            self.session = session
        case .sessionEnded, .error:
            break
        }
    }
}
