/// Configuration for a ``G7SensorMonitor``.
public struct G7Configuration: Sendable {
    /// How the monitor decides which sensor to follow.
    public var selection: SensorSelection

    /// Where the followed sensor's identity is persisted across launches.
    public var store: any DexcomKitStore

    /// The CoreBluetooth state-restoration identifier.
    ///
    /// Pass a stable, app-unique string and iOS will relaunch the app in the
    /// background for sensor events after it's been terminated — essential
    /// for uninterrupted monitoring. Requires the `bluetooth-central`
    /// background mode. `nil` disables restoration.
    public var restoreIdentifier: String?

    /// Whether to request and deliver readings from the sensor's backfill
    /// buffer after gaps (out of range, app not running).
    public var backfillEnabled: Bool

    public init(
        selection: SensorSelection = .automatic,
        store: any DexcomKitStore = UserDefaultsStore(),
        restoreIdentifier: String? = nil,
        backfillEnabled: Bool = true
    ) {
        self.selection = selection
        self.store = store
        self.restoreIdentifier = restoreIdentifier
        self.backfillEnabled = backfillEnabled
    }
}
