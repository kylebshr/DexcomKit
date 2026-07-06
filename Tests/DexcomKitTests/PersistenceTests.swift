import Foundation
import Testing

@testable import DexcomKit

@Suite struct PersistenceTests {
    @Test func followedSensorRoundTrips() {
        let store = InMemoryStore()
        let sensor = FollowedSensor(
            name: "DXCM8T",
            peripheralIdentifier: UUID(),
            activationDate: Date(timeIntervalSince1970: 1_750_000_000)
        )

        store.saveFollowedSensor(sensor)
        #expect(store.loadFollowedSensor() == sensor)
    }

    @Test func savingNilClears() {
        let store = InMemoryStore()
        store.saveFollowedSensor(
            FollowedSensor(name: "DXCM8T", peripheralIdentifier: UUID(), activationDate: .now))

        store.saveFollowedSensor(nil)
        #expect(store.loadFollowedSensor() == nil)
        #expect(store.isEmpty)
    }

    @Test func missingDataLoadsAsNone() {
        #expect(InMemoryStore().loadFollowedSensor() == nil)
    }

    @Test func corruptDataLoadsAsNone() {
        let store = InMemoryStore()
        store.set(Data("not json".utf8), forKey: FollowedSensor.storageKey)
        #expect(store.loadFollowedSensor() == nil)
    }
}
