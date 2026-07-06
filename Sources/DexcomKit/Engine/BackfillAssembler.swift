import Foundation

/// Reassembles the backfill byte stream and buffers its records until the
/// sensor signals the stream is complete (opcode 0x59 on the control
/// characteristic), then flushes them sorted and deduplicated.
///
/// Records are 9 bytes and may straddle notification boundaries when the
/// sensor packs the stream into MTU-sized chunks, so bytes are accumulated
/// across notifications and parsed in aligned strides — parsing each
/// notification in isolation would misalign every record after the first
/// straddle and produce garbage readings.
struct BackfillAssembler: Sendable {
    private var records: [BackfillRecord] = []
    private var pending = Data()

    var isEmpty: Bool { records.isEmpty && pending.isEmpty }

    /// The number of complete records parsed so far.
    var count: Int { records.count }

    /// Bytes received that don't yet form a complete record. Non-zero when
    /// the stream finishes means the sensor sent a corrupt or truncated tail.
    var pendingByteCount: Int { pending.count }

    /// Appends a notification's bytes to the stream, parsing every complete
    /// record and keeping the remainder for the next notification.
    mutating func append(_ data: Data) {
        pending += data
        var start = pending.startIndex
        while pending.distance(from: start, to: pending.endIndex) >= BackfillRecord.byteCount {
            let end = pending.index(start, offsetBy: BackfillRecord.byteCount)
            if let record = BackfillRecord(data: pending[start..<end]) {
                records.append(record)
            }
            start = end
        }
        pending = Data(pending[start...])
    }

    /// Returns the buffered records sorted by timestamp with duplicates
    /// removed, and clears the buffer — including any partial trailing bytes.
    mutating func flush() -> [BackfillRecord] {
        defer {
            records.removeAll()
            pending.removeAll()
        }
        var seen = Set<UInt32>()
        return
            records
            .sorted { $0.timestamp < $1.timestamp }
            .filter { seen.insert($0.timestamp).inserted }
    }
}
