import Foundation

/// A characteristic notification, parsed and classified. Pure data.
enum RoutedMessage: Sendable, Equatable {
    case authStatus(AuthStatusMessage)
    case glucose(GlucoseMessage)
    case extendedVersion(ExtendedVersionMessage)
    case backfillFinished
    case sessionStopped
    case backfillRecords([BackfillRecord])
    /// An opcode this package doesn't handle.
    case unrecognized(opcode: UInt8?)
    /// A known opcode whose payload failed to parse.
    case malformed(opcode: UInt8?)
}

/// Classifies characteristic notifications by opcode. Pure logic.
enum MessageRouter {
    static func route(_ data: Data, from characteristic: G7Characteristic) -> RoutedMessage {
        switch characteristic {
        case .authentication:
            guard let opcode = data.byte(at: 0) else { return .malformed(opcode: nil) }
            guard opcode == G7Opcode.authStatus else { return .unrecognized(opcode: opcode) }
            guard let message = AuthStatusMessage(data: data) else {
                return .malformed(opcode: opcode)
            }
            return .authStatus(message)

        case .control:
            guard let opcode = data.byte(at: 0) else { return .malformed(opcode: nil) }
            switch opcode {
            case G7Opcode.glucose:
                guard let message = GlucoseMessage(data: data) else {
                    return .malformed(opcode: opcode)
                }
                return .glucose(message)
            case G7Opcode.extendedVersion:
                guard let message = ExtendedVersionMessage(data: data) else {
                    return .malformed(opcode: opcode)
                }
                return .extendedVersion(message)
            case G7Opcode.backfillFinished:
                return .backfillFinished
            case G7Opcode.sessionStop:
                return .sessionStopped
            default:
                return .unrecognized(opcode: opcode)
            }

        case .backfill:
            // Backfill notifications carry one or more consecutive 9-byte
            // records; trailing bytes that don't form a full record are
            // dropped.
            var records: [BackfillRecord] = []
            var remaining = data[...]
            while remaining.count >= BackfillRecord.byteCount {
                if let record = BackfillRecord(data: remaining.prefix(BackfillRecord.byteCount)) {
                    records.append(record)
                }
                remaining = remaining.dropFirst(BackfillRecord.byteCount)
            }
            return .backfillRecords(records)
        }
    }
}
