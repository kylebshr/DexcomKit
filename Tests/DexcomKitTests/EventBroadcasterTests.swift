import Foundation
import Testing

@testable import DexcomKit

@Suite struct EventBroadcasterTests {
    @Test func everyConsumerReceivesEveryEvent() async {
        let broadcaster = EventBroadcaster<Int>()
        let first = await broadcaster.stream()
        let second = await broadcaster.stream()

        for value in 1...3 {
            await broadcaster.yield(value)
        }
        await broadcaster.finish()

        var firstValues: [Int] = []
        for await value in first { firstValues.append(value) }
        var secondValues: [Int] = []
        for await value in second { secondValues.append(value) }

        #expect(firstValues == [1, 2, 3])
        #expect(secondValues == [1, 2, 3])
    }

    @Test func lateSubscriberOnlySeesSubsequentEvents() async {
        let broadcaster = EventBroadcaster<Int>()
        let early = await broadcaster.stream()

        await broadcaster.yield(1)
        let late = await broadcaster.stream()
        await broadcaster.yield(2)
        await broadcaster.finish()

        var earlyValues: [Int] = []
        for await value in early { earlyValues.append(value) }
        var lateValues: [Int] = []
        for await value in late { lateValues.append(value) }

        #expect(earlyValues == [1, 2])
        #expect(lateValues == [2])
    }

    @Test func cancelledConsumerIsRemoved() async throws {
        let broadcaster = EventBroadcaster<Int>()

        let consumer = Task {
            for await _ in await broadcaster.stream() {}
        }
        // Ensure the subscription is registered before cancelling.
        var registered = false
        for _ in 0..<1000 where !registered {
            registered = await broadcaster.subscriberCount == 1
            if !registered { try await Task.sleep(for: .milliseconds(1)) }
        }
        #expect(registered)

        consumer.cancel()
        await consumer.value

        var removed = false
        for _ in 0..<1000 where !removed {
            removed = await broadcaster.subscriberCount == 0
            if !removed { try await Task.sleep(for: .milliseconds(1)) }
        }
        #expect(removed)
    }

    @Test func streamAfterFinishCompletesImmediately() async {
        let broadcaster = EventBroadcaster<Int>()
        await broadcaster.finish()

        var values: [Int] = []
        for await value in await broadcaster.stream() { values.append(value) }
        #expect(values.isEmpty)
    }

    @Test func yieldAfterFinishIsNoOp() async {
        let broadcaster = EventBroadcaster<Int>()
        let stream = await broadcaster.stream()
        await broadcaster.finish()

        await broadcaster.yield(42)

        var values: [Int] = []
        for await value in stream { values.append(value) }
        #expect(values.isEmpty)
    }
}
