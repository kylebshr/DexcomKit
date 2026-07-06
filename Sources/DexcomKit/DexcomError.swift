import Foundation

/// Errors DexcomKit reports, either thrown from
/// ``G7SensorMonitor/start()`` or delivered as ``G7Event/error(_:)``.
public enum DexcomError: Error, Sendable, Hashable {
    /// The configuration is invalid; the associated value explains why.
    case invalidConfiguration(String)

    /// The sensor's CGM service or characteristics couldn't be discovered.
    case serviceDiscoveryFailed

    /// Enabling notifications on a required characteristic failed; the
    /// connection was abandoned and a rescan scheduled.
    case subscriptionFailed

    /// The sensor reported that no authenticated, bonded session exists.
    /// DexcomKit requires the official Dexcom app (or receiver) to have
    /// paired with the sensor first.
    case authenticationRejected
}

extension DexcomError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let reason):
            "Invalid configuration: \(reason)"
        case .serviceDiscoveryFailed:
            "The sensor's CGM service could not be discovered."
        case .subscriptionFailed:
            "Subscribing to a required sensor characteristic failed."
        case .authenticationRejected:
            "The sensor has no authenticated session. Pair it with the official Dexcom app first."
        }
    }
}
