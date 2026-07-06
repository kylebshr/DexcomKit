/// A display bucket for the glucose rate of change, matching the arrows the
/// Dexcom app shows.
public enum TrendArrow: String, Sendable, Hashable, Codable, CaseIterable {
    /// Falling more than 3 mg/dL per minute.
    case fallingQuickly
    /// Falling 2–3 mg/dL per minute.
    case falling
    /// Falling 1–2 mg/dL per minute.
    case fallingSlightly
    /// Changing less than 1 mg/dL per minute.
    case steady
    /// Rising 1–2 mg/dL per minute.
    case risingSlightly
    /// Rising 2–3 mg/dL per minute.
    case rising
    /// Rising more than 3 mg/dL per minute.
    case risingQuickly

    /// Buckets a rate of change in mg/dL per minute; `nil` when the sensor
    /// reported no trend.
    ///
    /// Boundaries match the Dexcom/G7SensorKit semantics: the falling
    /// buckets are inclusive (a rate of exactly −3.0 is falling quickly),
    /// the rising side is exclusive.
    public init?(rate: Double?) {
        guard let rate else { return nil }
        switch rate {
        case ...(-3): self = .fallingQuickly
        case ...(-2): self = .falling
        case ...(-1): self = .fallingSlightly
        case ..<1: self = .steady
        case ..<2: self = .risingSlightly
        case ..<3: self = .rising
        default: self = .risingQuickly
        }
    }
}
