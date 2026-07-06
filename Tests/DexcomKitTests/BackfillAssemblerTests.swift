import Foundation
import Testing

@testable import DexcomKit

@Suite struct BackfillAssemblerTests {
    private func record(timestamp: UInt32) throws -> BackfillRecord {
        try #require(BackfillRecord(data: backfillRecordBytes(timestamp: timestamp)))
    }

    @Test func flushSortsByTimestamp() throws {
        var assembler = BackfillAssembler()
        assembler.append([try record(timestamp: 300), try record(timestamp: 100)])
        assembler.append([try record(timestamp: 200)])

        #expect(assembler.flush().map(\.timestamp) == [100, 200, 300])
    }

    @Test func flushRemovesDuplicates() throws {
        var assembler = BackfillAssembler()
        assembler.append([
            try record(timestamp: 100), try record(timestamp: 100), try record(timestamp: 200),
        ])

        #expect(assembler.flush().map(\.timestamp) == [100, 200])
    }

    @Test func flushClearsTheBuffer() throws {
        var assembler = BackfillAssembler()
        assembler.append([try record(timestamp: 100)])
        #expect(!assembler.isEmpty)
        #expect(assembler.count == 1)

        _ = assembler.flush()
        #expect(assembler.isEmpty)
        #expect(assembler.flush().isEmpty)
    }
}
