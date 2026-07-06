import Foundation

/// A characteristic notification, parsed and classified. Pure data.
enum RoutedMessage: Sendable, Equatable {
    case authStatus(AuthStatusMessage)
    case glucose(GlucoseMessage)
    case extendedVersion(ExtendedVersionMessage)
    case backfillFinished
    case sessionStopped
    /// Bytes from the backfill stream, delivered raw: records may straddle
    /// notification boundaries, so ``BackfillAssembler`` reassembles and
    /// parses the stream.
    case backfillData(Data)
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
            return .backfillData(data)
        }
    }
}
