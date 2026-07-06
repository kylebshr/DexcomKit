import Foundation

/// Where DexcomKit persists the identity of the sensor it follows, so it can
/// reconnect to the same sensor across app launches.
///
/// The default is ``UserDefaultsStore``. Provide a custom conformance to
/// store the data elsewhere (keychain, a file, an in-memory store in tests).
public protocol DexcomKitStore: Sendable {
    /// Returns the data stored for a key, or `nil` if none.
    func data(forKey key: String) -> Data?

    /// Stores data for a key; passing `nil` removes the value.
    func set(_ data: Data?, forKey key: String)
}

/// A ``DexcomKitStore`` backed by `UserDefaults`.
public struct UserDefaultsStore: DexcomKitStore {
    private let suiteName: String?

    /// Creates a store backed by `UserDefaults`.
    ///
    /// - Parameter suiteName: Pass an App Group suite name so app extensions
    ///   (widgets, Live Activities) can read the same state; `nil` uses the
    ///   standard defaults.
    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    public func data(forKey key: String) -> Data? {
        defaults.data(forKey: key)
    }

    public func set(_ data: Data?, forKey key: String) {
        if let data {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
