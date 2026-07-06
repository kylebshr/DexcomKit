import Foundation
import Testing

@testable import DexcomKit

/// Awaits the next engine event the transform matches, skipping others.
/// Returns `nil` if the stream ends first.
func nextEvent<T>(
    _ iterator: inout AsyncStream<G7Event>.AsyncIterator,
    matching transform: (G7Event) -> T?
) async -> T? {
    while let event = await iterator.next() {
        if let value = transform(event) { return value }
    }
    return nil
}

func nextConnectionState(
    _ iterator: inout AsyncStream<G7Event>.AsyncIterator
) async -> G7ConnectionState? {
    await nextEvent(&iterator) {
        if case .connectionStateChanged(let state) = $0 { state } else { nil }
    }
}

func nextReading(
    _ iterator: inout AsyncStream<G7Event>.AsyncIterator
) async -> GlucoseReading? {
    await nextEvent(&iterator) {
        if case .reading(let reading) = $0 { reading } else { nil }
    }
}

/// Records the durations the engine sleeps, returning immediately.
final class SleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var _durations: [Duration] = []

    var durations: [Duration] {
        lock.withLock { _durations }
    }

    func record(_ duration: Duration) {
        lock.withLock { _durations.append(duration) }
    }
}

/// Backfill record fixture bytes with a custom 24-bit timestamp.
func backfillRecordBytes(timestamp: UInt32) -> Data {
    var bytes = Data(G7Fixtures.backfillRecord)
    bytes[0] = UInt8(timestamp & 0xFF)
    bytes[1] = UInt8((timestamp >> 8) & 0xFF)
    bytes[2] = UInt8((timestamp >> 16) & 0xFF)
    return bytes
}
