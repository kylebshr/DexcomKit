import Foundation

/// The identity of the sensor being followed, persisted through the
/// configured ``DexcomKitStore`` once a sensor is adopted.
struct FollowedSensor: Sendable, Hashable, Codable {
    static let storageKey = "com.dexcomkit.followedSensor"

    /// The advertised name (e.g. `DXCM8T`).
    var name: String

    /// The CoreBluetooth peripheral identifier on this device, used for the
    /// fast reconnect path via `retrievePeripherals(withIdentifiers:)`.
    var peripheralIdentifier: UUID

    /// When the sensor was activated.
    var activationDate: Date

    /// Whether this sensor's session has ended. Persisted so that after a
    /// relaunch a replacement sensor can be adopted and the session end
    /// isn't re-announced.
    var sessionEnded: Bool = false

    /// Session length in seconds (includes the grace period) from the
    /// sensor's extended version message, once received.
    var sessionLength: UInt32?

    /// Warmup length in seconds from the extended version message.
    var warmupLength: UInt16?

    /// Algorithm version from the extended version message.
    var algorithmVersion: UInt32?
}

extension DexcomKitStore {
    /// Loads the followed sensor, treating missing or corrupt data as none.
    func loadFollowedSensor() -> FollowedSensor? {
        guard let data = data(forKey: FollowedSensor.storageKey) else { return nil }
        return try? JSONDecoder().decode(FollowedSensor.self, from: data)
    }

    /// Persists the followed sensor, or clears it when `nil`.
    func saveFollowedSensor(_ sensor: FollowedSensor?) {
        set(sensor.flatMap { try? JSONEncoder().encode($0) }, forKey: FollowedSensor.storageKey)
    }
}
