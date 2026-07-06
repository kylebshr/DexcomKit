import Foundation

@testable import DexcomKit

/// A `DexcomKitStore` backed by a dictionary, for tests.
final class InMemoryStore: DexcomKitStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: Data] = [:]

    func data(forKey key: String) -> Data? {
        lock.withLock { storage[key] }
    }

    func set(_ data: Data?, forKey key: String) {
        lock.withLock { storage[key] = data }
    }

    var isEmpty: Bool {
        lock.withLock { storage.isEmpty }
    }
}
