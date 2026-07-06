/// How the monitor decides which sensor to follow.
public enum SensorSelection: Sendable, Hashable {
    /// Adopt the first G7-family sensor that reports an authenticated,
    /// bonded session.
    ///
    /// This is safe as the default because a sensor paired to someone else's
    /// phone never reports an authenticated session to this one, so it is
    /// never adopted.
    case automatic

    /// Only adopt a sensor whose advertised name ends with the given
    /// characters — the last two characters of the pairing code printed on
    /// the sensor applicator (e.g. `"8T"`). Matching is case-insensitive.
    case nameSuffix(String)
}
