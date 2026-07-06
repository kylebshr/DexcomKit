import Foundation
import Testing

@testable import DexcomKit

@Suite struct BackfillAssemblerTests {
    @Test func flushSortsByTimestamp() {
        var assembler = BackfillAssembler()
        assembler.append(
            backfillRecordBytes(timestamp: 300) + backfillRecordBytes(timestamp: 100))
        assembler.append(backfillRecordBytes(timestamp: 200))

        #expect(assembler.flush().map(\.timestamp) == [100, 200, 300])
    }

    @Test func flushRemovesDuplicates() {
        var assembler = BackfillAssembler()
        assembler.append(
            backfillRecordBytes(timestamp: 100)
                + backfillRecordBytes(timestamp: 100)
                + backfillRecordBytes(timestamp: 200))

        #expect(assembler.flush().map(\.timestamp) == [100, 200])
    }

    @Test func flushClearsTheBuffer() {
        var assembler = BackfillAssembler()
        assembler.append(backfillRecordBytes(timestamp: 100))
        #expect(!assembler.isEmpty)
        #expect(assembler.count == 1)

        _ = assembler.flush()
        #expect(assembler.isEmpty)
        #expect(assembler.flush().isEmpty)
    }

    @Test func recordsStraddlingChunkBoundariesAreReassembled() {
        // Three records MTU-packed into 20 + 7 byte chunks: the third record
        // straddles the boundary.
        let stream =
            backfillRecordBytes(timestamp: 100)
            + backfillRecordBytes(timestamp: 200)
            + backfillRecordBytes(timestamp: 300)

        var assembler = BackfillAssembler()
        assembler.append(stream.prefix(20))
        #expect(assembler.count == 2)
        #expect(assembler.pendingByteCount == 2)

        assembler.append(stream.suffix(7))
        #expect(assembler.count == 3)
        #expect(assembler.pendingByteCount == 0)

        #expect(assembler.flush().map(\.timestamp) == [100, 200, 300])
    }

    @Test func byteByByteDeliveryReassembles() {
        var assembler = BackfillAssembler()
        for byte in backfillRecordBytes(timestamp: 100) {
            assembler.append(Data([byte]))
        }

        #expect(assembler.flush().map(\.timestamp) == [100])
    }

    @Test func danglingBytesAreReportedAndClearedOnFlush() {
        var assembler = BackfillAssembler()
        assembler.append(backfillRecordBytes(timestamp: 100) + Data([0x01, 0x02]))
        #expect(assembler.pendingByteCount == 2)

        #expect(assembler.flush().map(\.timestamp) == [100])
        #expect(assembler.pendingByteCount == 0)
        #expect(assembler.isEmpty)
    }

    @Test func pendingBytesAloneAreNotEmpty() {
        // A partial record still counts as buffered state, so a flush-on-
        // disconnect clears it rather than leaking it into the next stream.
        var assembler = BackfillAssembler()
        assembler.append(Data([0x01, 0x02, 0x03]))
        #expect(assembler.isEmpty == false)
        #expect(assembler.count == 0)
    }
}
