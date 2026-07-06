import Foundation
import Testing

@testable import DexcomKit

@Suite struct MessageRouterTests {
    @Test func routesAuthStatus() throws {
        let routed = MessageRouter.route(G7Fixtures.authOK, from: .authentication)
        let expected = try #require(AuthStatusMessage(data: G7Fixtures.authOK))
        #expect(routed == .authStatus(expected))
    }

    @Test func unknownOpcodeOnAuthIsUnrecognized() {
        #expect(
            MessageRouter.route(Data([0x4E, 0x00, 0x00]), from: .authentication)
                == .unrecognized(opcode: 0x4E))
    }

    @Test func shortAuthMessageIsMalformed() {
        #expect(
            MessageRouter.route(Data([0x05, 0x01]), from: .authentication)
                == .malformed(opcode: 0x05))
    }

    @Test func routesGlucose() throws {
        let routed = MessageRouter.route(G7Fixtures.glucose, from: .control)
        let expected = try #require(GlucoseMessage(data: G7Fixtures.glucose))
        #expect(routed == .glucose(expected))
    }

    @Test func truncatedGlucoseIsMalformed() {
        #expect(
            MessageRouter.route(G7Fixtures.glucose.prefix(10), from: .control)
                == .malformed(opcode: 0x4E))
    }

    @Test func routesExtendedVersion() throws {
        let routed = MessageRouter.route(G7Fixtures.extendedVersion10Day, from: .control)
        let expected = try #require(
            ExtendedVersionMessage(data: G7Fixtures.extendedVersion10Day))
        #expect(routed == .extendedVersion(expected))
    }

    @Test func routesControlSignals() {
        #expect(MessageRouter.route(Data([0x59]), from: .control) == .backfillFinished)
        #expect(MessageRouter.route(Data([0x28]), from: .control) == .sessionStopped)
    }

    @Test func unknownControlOpcodeIsUnrecognized() {
        #expect(
            MessageRouter.route(Data([0xAB, 0x01]), from: .control)
                == .unrecognized(opcode: 0xAB))
    }

    @Test func emptyDataIsMalformed() {
        #expect(MessageRouter.route(Data(), from: .control) == .malformed(opcode: nil))
        #expect(MessageRouter.route(Data(), from: .authentication) == .malformed(opcode: nil))
    }

    @Test func backfillDataPassesThroughRaw() {
        // Backfill is a byte stream whose records may straddle notification
        // boundaries; the router passes it through untouched for the
        // assembler to reassemble.
        let chunk = backfillRecordBytes(timestamp: 299_700) + Data([0x01, 0x02])
        #expect(MessageRouter.route(chunk, from: .backfill) == .backfillData(chunk))
        #expect(MessageRouter.route(Data(), from: .backfill) == .backfillData(Data()))
    }
}
