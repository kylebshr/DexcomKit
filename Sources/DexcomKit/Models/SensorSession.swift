import Foundation

/// The lifecycle of the sensor session being followed.
///
/// Dates are computed from the activation date plus the parameters the sensor
/// reports in its extended version message. Until that message arrives,
/// G7 defaults are used: ~27-minute warmup, 10-day session, 12-hour grace
/// period.
public struct SensorSession: Sendable, Hashable, Codable {
    /// The default warmup duration when the sensor hasn't reported one.
    public static let defaultWarmupDuration: TimeInterval = 27 * 60
    /// The default session length when the sensor hasn't reported one.
    public static let defaultSessionLength: TimeInterval = 10 * 24 * 60 * 60
    /// The default grace period after expiration.
    public static let defaultGracePeriod: TimeInterval = 12 * 60 * 60

    /// The advertised name of the sensor (e.g. `DXCM8T`).
    public let sensorName: String

    /// When the sensor was activated, derived from the activation-relative
    /// timestamps the sensor reports.
    public let activationDate: Date

    /// When warmup completes and readings become reliable.
    public let warmupEndDate: Date

    /// When the session expires.
    public let expirationDate: Date

    /// When the post-expiration grace period ends and the sensor stops
    /// producing readings entirely.
    public let gracePeriodEndDate: Date

    /// The sensor's algorithm version, once its extended version message has
    /// been received.
    public let algorithmVersion: UInt32?

    public init(
        sensorName: String,
        activationDate: Date,
        warmupEndDate: Date,
        expirationDate: Date,
        gracePeriodEndDate: Date,
        algorithmVersion: UInt32?
    ) {
        self.sensorName = sensorName
        self.activationDate = activationDate
        self.warmupEndDate = warmupEndDate
        self.expirationDate = expirationDate
        self.gracePeriodEndDate = gracePeriodEndDate
        self.algorithmVersion = algorithmVersion
    }

    /// Whether the sensor is still warming up at the given date.
    public func isInWarmup(at date: Date = Date()) -> Bool {
        date < warmupEndDate
    }

    /// Whether the session has expired at the given date (grace period may
    /// still be running).
    public func isExpired(at date: Date = Date()) -> Bool {
        date >= expirationDate
    }
}

extension SensorSession {
    /// Builds a session from an activation date and, when available, the
    /// sensor's own reported parameters.
    ///
    /// The sensor's reported session length *includes* the grace period:
    /// a real 10-day sensor reports 907 200 s (10.5 days). Expiration is
    /// therefore the reported length minus the 12-hour grace period, and
    /// the grace period ends when the reported length elapses — matching
    /// how G7SensorKit derives these dates.
    init(
        sensorName: String,
        activationDate: Date,
        sessionLength: TimeInterval?,
        warmupLength: TimeInterval?,
        algorithmVersion: UInt32?
    ) {
        let warmup = warmupLength ?? Self.defaultWarmupDuration
        let totalLength = sessionLength ?? (Self.defaultSessionLength + Self.defaultGracePeriod)
        let expiration = activationDate.addingTimeInterval(
            max(totalLength - Self.defaultGracePeriod, 0))

        self.init(
            sensorName: sensorName,
            activationDate: activationDate,
            warmupEndDate: activationDate.addingTimeInterval(warmup),
            expirationDate: expiration,
            gracePeriodEndDate: activationDate.addingTimeInterval(totalLength),
            algorithmVersion: algorithmVersion
        )
    }

    init(sensorName: String, activationDate: Date, extendedVersion: ExtendedVersionMessage?) {
        self.init(
            sensorName: sensorName,
            activationDate: activationDate,
            sessionLength: extendedVersion.map { TimeInterval($0.sessionLength) },
            warmupLength: extendedVersion.map { TimeInterval($0.warmupLength) },
            algorithmVersion: extendedVersion?.algorithmVersion
        )
    }
}
