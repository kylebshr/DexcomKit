/// Buffers backfill records until the sensor signals the stream is complete
/// (opcode 0x59 on the control characteristic), then flushes them sorted and
/// deduplicated.
struct BackfillAssembler: Sendable {
    private var records: [BackfillRecord] = []

    var isEmpty: Bool { records.isEmpty }

    var count: Int { records.count }

    mutating func append(_ newRecords: [BackfillRecord]) {
        records.append(contentsOf: newRecords)
    }

    /// Returns the buffered records sorted by timestamp with duplicates
    /// removed, and clears the buffer.
    mutating func flush() -> [BackfillRecord] {
        defer { records.removeAll() }
        var seen = Set<UInt32>()
        return
            records
            .sorted { $0.timestamp < $1.timestamp }
            .filter { seen.insert($0.timestamp).inserted }
    }
}
