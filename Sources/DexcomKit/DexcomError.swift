import Foundation

/// Errors DexcomKit reports, either thrown from
/// ``G7SensorMonitor/start()`` or delivered as ``G7Event/error(_:)``.
public enum DexcomError: Error, Sendable, Hashable {
    /// The configuration is invalid; the associated value explains why.
    case invalidConfiguration(String)

    /// A connection attempt didn't complete before the sensor's connection
    /// window closed.
    case connectionTimeout

    /// The sensor's CGM service or characteristics couldn't be discovered.
    case serviceDiscoveryFailed

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
        case .connectionTimeout:
            "The connection attempt timed out before the sensor's connection window closed."
        case .serviceDiscoveryFailed:
            "The sensor's CGM service could not be discovered."
        case .authenticationRejected:
            "The sensor has no authenticated session. Pair it with the official Dexcom app first."
        }
    }
}
