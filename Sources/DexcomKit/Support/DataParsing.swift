import Foundation

/// Bounds-checked little-endian reads used by all message parsers.
///
/// Offsets are zero-based relative to the start of the value, regardless of
/// the slice's `startIndex` — `Data` subscripts use absolute indices, which
/// is a classic source of crashes when parsing CoreBluetooth payload slices.
extension Data {
    func byte(at offset: Int) -> UInt8? {
        guard offset >= 0, offset < count else { return nil }
        return self[startIndex + offset]
    }

    func uint16(at offset: Int) -> UInt16? {
        guard let low = byte(at: offset), let high = byte(at: offset + 1) else { return nil }
        return UInt16(low) | UInt16(high) << 8
    }

    func uint24(at offset: Int) -> UInt32? {
        guard
            let low = byte(at: offset),
            let mid = byte(at: offset + 1),
            let high = byte(at: offset + 2)
        else { return nil }
        return UInt32(low) | UInt32(mid) << 8 | UInt32(high) << 16
    }

    func uint32(at offset: Int) -> UInt32? {
        guard let low = uint16(at: offset), let high = uint16(at: offset + 2) else { return nil }
        return UInt32(low) | UInt32(high) << 16
    }
}
