import Foundation
import Testing

@testable import DexcomKit

@Suite struct AuthStatusMessageTests {
    @Test(arguments: [
        (bytes: (UInt8(1), UInt8(1)), authenticated: true, bonded: true),
        (bytes: (UInt8(1), UInt8(0)), authenticated: true, bonded: false),
        (bytes: (UInt8(0), UInt8(1)), authenticated: false, bonded: true),
        (bytes: (UInt8(0), UInt8(0)), authenticated: false, bonded: false),
    ])
    func parsesFlagCombinations(
        _ testCase: (bytes: (UInt8, UInt8), authenticated: Bool, bonded: Bool)
    ) throws {
        let data = Data([0x05, testCase.bytes.0, testCase.bytes.1])
        let message = try #require(AuthStatusMessage(data: data))
        #expect(message.isAuthenticated == testCase.authenticated)
        #expect(message.isBonded == testCase.bonded)
    }

    @Test func parsesFixture() throws {
        let message = try #require(AuthStatusMessage(data: G7Fixtures.authOK))
        #expect(message.isAuthenticated && message.isBonded)
    }

    @Test func rejectsShortData() {
        #expect(AuthStatusMessage(data: Data([0x05, 0x01])) == nil)
        #expect(AuthStatusMessage(data: Data()) == nil)
    }

    @Test func rejectsWrongOpcode() {
        #expect(AuthStatusMessage(data: Data([0x06, 0x01, 0x01])) == nil)
    }
}
