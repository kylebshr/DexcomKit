/// Everything the monitor reports, delivered in order on each consumer's
/// event stream.
public enum G7Event: Sendable {
    /// The connection state changed.
    case connectionStateChanged(G7ConnectionState)

    /// A real-time reading arrived.
    case reading(GlucoseReading)

    /// Readings recovered from the sensor's backfill buffer, sorted by
    /// timestamp and deduplicated against already-delivered readings.
    case backfill([GlucoseReading])

    /// A sensor session was established or its lifecycle dates were refined
    /// by the sensor's extended version message.
    case sessionEstablished(SensorSession)

    /// The sensor session is over.
    case sessionEnded(SessionEndReason)

    /// A notable, non-fatal error occurred; the monitor keeps running.
    case error(DexcomError)
}

/// Why a sensor session ended.
public enum SessionEndReason: Sendable, Hashable {
    /// The sensor reported its session expired.
    case expired
    /// The sensor reported a hardware or algorithm failure.
    case failed
    /// The sensor reported its session was stopped.
    case stopped
    /// The sensor repeatedly disconnected before reporting an authenticated
    /// session, which usually means the session ended.
    case suspectedEnd
}
