import Foundation
import Testing

@testable import DexcomKit

@Suite struct DataParsingTests {
    let data = Data([0x01, 0x02, 0x03, 0x04, 0x05])

    @Test func readsBytes() {
        #expect(data.byte(at: 0) == 0x01)
        #expect(data.byte(at: 4) == 0x05)
    }

    @Test func readsLittleEndianIntegers() {
        #expect(data.uint16(at: 0) == 0x0201)
        #expect(data.uint24(at: 0) == 0x030201)
        #expect(data.uint32(at: 0) == 0x04030201)
        #expect(data.uint32(at: 1) == 0x05040302)
    }

    @Test func readsAtExactEnd() {
        #expect(data.uint16(at: 3) == 0x0504)
        #expect(data.uint32(at: 1) != nil)
    }

    @Test func rejectsReadsPastEnd() {
        #expect(data.byte(at: 5) == nil)
        #expect(data.uint16(at: 4) == nil)
        #expect(data.uint24(at: 3) == nil)
        #expect(data.uint32(at: 2) == nil)
    }

    @Test func rejectsNegativeOffsets() {
        #expect(data.byte(at: -1) == nil)
        #expect(data.uint32(at: -1) == nil)
    }

    @Test func emptyDataIsSafe() {
        let empty = Data()
        #expect(empty.byte(at: 0) == nil)
        #expect(empty.uint32(at: 0) == nil)
    }

    @Test func offsetsAreRelativeToSliceStart() {
        let sliced = data.resliced
        #expect(sliced.startIndex != 0)
        #expect(sliced.byte(at: 0) == 0x01)
        #expect(sliced.uint32(at: 1) == 0x05040302)
        #expect(sliced.byte(at: 5) == nil)
    }
}
