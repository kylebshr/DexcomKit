import Foundation

/// Byte-exact protocol fixtures. Layouts mirror the tables in the
/// message-type documentation, so a failing test reads like a protocol diff.
enum G7Fixtures {
    /// A realistic real-time glucose message:
    /// opcode 0x4E, status 0x00, messageTimestamp 300 000 s,
    /// sequence 1000, age 6 s, glucose 113 mg/dL, state ok (6),
    /// trend −0.2 mg/dL/min, predicted 110 mg/dL, no flags.
    static let glucose = Data(hex: "4E 00 E0930400 E803 0000 0600 7100 06 FE 6E00 00")

    /// A backfill record: timestamp 299 700 s, glucose 120 mg/dL,
    /// state ok (6), no flags, trend +0.1 mg/dL/min.
    static let backfillRecord = Data(hex: "B49204 00 7800 06 00 01")

    /// Extended version response for a 10-day sensor. The reported session
    /// length includes the grace period: 907 200 s = 10.5 days, matching
    /// real device captures. Warmup 1620 s, algorithm version 0x00010203,
    /// hardware version 1, max lifetime 12 days.
    static let extendedVersion10Day = Data(hex: "52 00 C0D70D00 5406 03020100 01 0C00")

    /// Extended version response for a 15-day sensor: session 1 339 200 s
    /// (15.5 days including grace), max lifetime 17 days.
    static let extendedVersion15Day = Data(hex: "52 00 406F1400 5406 03020100 01 1100")

    /// Auth status: authenticated and bonded.
    static let authOK = Data(hex: "050101")
}

extension Data {
    /// Builds Data from a hex string, ignoring whitespace.
    init(hex: String) {
        let cleaned = hex.filter { !$0.isWhitespace }
        precondition(cleaned.count.isMultiple(of: 2), "hex string must have an even number of digits")
        var bytes: [UInt8] = []
        bytes.reserveCapacity(cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard let byte = UInt8(cleaned[index..<next], radix: 16) else {
                preconditionFailure("invalid hex byte: \(cleaned[index..<next])")
            }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }

    /// Returns this data embedded in a larger buffer and re-sliced, so the
    /// result has a non-zero `startIndex` — mimicking payload slices from
    /// CoreBluetooth and exercising offset-relative parsing.
    var resliced: Data {
        let padded = Data([0xAA, 0xBB, 0xCC]) + self
        return padded.dropFirst(3)
    }
}
