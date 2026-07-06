/// The monitor's connection to the sensor.
///
/// The G7 only accepts connections for a few seconds around each ~5-minute
/// reading, then disconnects itself — so ``waitingForReading`` is the normal
/// resting state of a healthy session, not an error.
public enum G7ConnectionState: Sendable, Hashable {
    /// The monitor hasn't been started.
    case idle

    /// Bluetooth can't be used right now.
    case bluetoothUnavailable(BluetoothUnavailableReason)

    /// Scanning for the sensor's next advertisement.
    case scanning

    /// A connection to the sensor is being established.
    case connecting

    /// Connected and waiting for the sensor to report an authenticated,
    /// bonded session (established by the official Dexcom app).
    case authenticating

    /// Connected and subscribed; readings arrive on this connection.
    case connected

    /// The sensor delivered its data and disconnected itself; a rescan is
    /// scheduled for the next reading.
    case waitingForReading
}

/// Why Bluetooth is unavailable.
public enum BluetoothUnavailableReason: Sendable, Hashable {
    /// Bluetooth is switched off.
    case poweredOff
    /// The app isn't authorized to use Bluetooth.
    case unauthorized
    /// This device doesn't support Bluetooth LE.
    case unsupported
    /// The Bluetooth stack is resetting; usually transient.
    case resetting
    /// The state isn't known yet.
    case unknown
}

extension G7ConnectionState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .idle: "idle"
        case .bluetoothUnavailable(let reason): "bluetoothUnavailable(\(reason))"
        case .scanning: "scanning"
        case .connecting: "connecting"
        case .authenticating: "authenticating"
        case .connected: "connected"
        case .waitingForReading: "waitingForReading"
        }
    }
}
