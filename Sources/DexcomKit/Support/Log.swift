import os

/// Unified-logging categories for the package.
///
/// Inspect live behavior with:
/// ```
/// log stream --predicate 'subsystem == "com.kylebshr.DexcomKit"'
/// ```
/// Privacy policy: operational data (states, opcodes, byte counts, timings)
/// is public; glucose values, trend rates, sensor names, and peripheral
/// identifiers are private, because sensor names embed the pairing code and
/// readings are health data.
enum Log {
    static let subsystem = "com.kylebshr.DexcomKit"

    /// Central state, connects, disconnects, rescan scheduling.
    static let connection = Logger(subsystem: subsystem, category: "connection")
    /// Scanning and adoption decisions.
    static let discovery = Logger(subsystem: subsystem, category: "discovery")
    /// Message routing and parsing.
    static let messages = Logger(subsystem: subsystem, category: "messages")
    /// Backfill buffering and delivery.
    static let backfill = Logger(subsystem: subsystem, category: "backfill")
    /// Session lifecycle: adoption, establishment, end.
    static let session = Logger(subsystem: subsystem, category: "session")
    /// Store reads and writes.
    static let persistence = Logger(subsystem: subsystem, category: "persistence")

    /// Signposts for timing connection windows in Instruments.
    static let signposter = OSSignposter(subsystem: subsystem, category: "connection")
}
