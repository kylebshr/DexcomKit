import Foundation

/// Fans events out to any number of independent `AsyncStream` consumers.
///
/// A raw `AsyncStream` supports only a single consumer; this actor hands each
/// caller its own stream and yields every event to all of them. Streams
/// created after ``finish()`` complete immediately; consumers that stop
/// iterating are cleaned up via their stream's termination handler.
actor EventBroadcaster<Element: Sendable> {
    private var continuations: [UUID: AsyncStream<Element>.Continuation] = [:]
    private var isFinished = false

    /// The number of active consumers. For tests and diagnostics.
    var subscriberCount: Int { continuations.count }

    /// Returns a new independent stream of all future events.
    func stream() -> AsyncStream<Element> {
        let (stream, continuation) = AsyncStream<Element>.makeStream()
        guard !isFinished else {
            continuation.finish()
            return stream
        }

        let id = UUID()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id) }
        }
        return stream
    }

    /// Delivers an event to every active consumer.
    func yield(_ element: Element) {
        for continuation in continuations.values {
            continuation.yield(element)
        }
    }

    /// Ends all active streams; subsequent ``yield(_:)`` calls are no-ops.
    func finish() {
        isFinished = true
        for continuation in continuations.values {
            continuation.finish()
        }
        continuations.removeAll()
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }
}
