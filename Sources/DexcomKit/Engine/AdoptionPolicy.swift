/// Decides whether a discovered peripheral should be connected, given the
/// configured selection and the currently followed sensor. Pure logic.
enum AdoptionPolicy {
    /// - Parameters:
    ///   - advertisedName: The peripheral's advertised local name.
    ///   - selection: The configured sensor selection.
    ///   - followedSensorName: The persisted sensor being followed, if any.
    ///   - sessionHasEnded: Whether the followed sensor's session has ended,
    ///     which reopens adoption so a replacement sensor rolls over
    ///     automatically.
    static func shouldConnect(
        advertisedName: String?,
        selection: SensorSelection,
        followedSensorName: String?,
        sessionHasEnded: Bool
    ) -> Bool {
        guard let name = advertisedName, isG7Family(name) else { return false }

        // While following a healthy session, only that sensor is connected.
        if let followedSensorName, !sessionHasEnded {
            return name == followedSensorName
        }

        switch selection {
        case .automatic:
            return true
        case .nameSuffix(let suffix):
            return !suffix.isEmpty && name.lowercased().hasSuffix(suffix.lowercased())
        }
    }

    /// Whether an advertised name belongs to the G7 sensor family
    /// (G7, Dexcom One, Dexcom One+).
    static func isG7Family(_ name: String) -> Bool {
        G7UUID.namePrefixes.contains { name.hasPrefix($0) }
    }
}
