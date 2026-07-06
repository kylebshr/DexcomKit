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
