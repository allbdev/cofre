import Foundation
import Testing

@testable import CofreKit

struct InMemorySecretStoreTests {
    let store = InMemorySecretStore()

    @Test func addsWithoutUnlockingButListsOnlyUnlocked() async throws {
        #expect(try await store.list().isEmpty)  // empty lists as empty, locked or not
        let added = try await store.add(name: "Token", value: SecretValue("abc"))
        #expect(await !store.isUnlocked)
        await #expect(throws: VaultError.locked) { try await store.list() }
        try await store.unlock(reason: "test")
        #expect(try await store.list() == [added])
    }

    @Test func readingNeedsAnUnlock() async throws {
        let added = try await store.add(name: "Token", value: SecretValue("abc"))
        await #expect(throws: VaultError.locked) { try await store.value(for: added.id) }
        try await store.unlock(reason: "test")
        #expect(try await store.value(for: added.id) == SecretValue("abc"))
    }

    @Test func renameAndReplaceNeedAnUnlock() async throws {
        let added = try await store.add(name: "Token", value: SecretValue("abc"))
        await #expect(throws: VaultError.locked) { try await store.rename(added.id, to: "New") }
        await #expect(throws: VaultError.locked) {
            try await store.replaceValue(added.id, with: SecretValue("x"))
        }
        try await store.unlock(reason: "test")
        try await store.rename(added.id, to: "New")
        try await store.replaceValue(added.id, with: SecretValue("xyz"))
        #expect(try await store.list().map(\.name) == ["New"])
        #expect(try await store.value(for: added.id) == SecretValue("xyz"))
    }

    @Test func lockForgetsTheSession() async throws {
        let added = try await store.add(name: "Token", value: SecretValue("abc"))
        try await store.unlock(reason: "test")
        await store.lock()
        await #expect(throws: VaultError.locked) { try await store.value(for: added.id) }
    }

    @Test func deleteWorksLockedAndReportsMissingItems() async throws {
        let added = try await store.add(name: "Token", value: SecretValue("abc"))
        try await store.delete(added.id)
        #expect(try await store.list().isEmpty)
        await #expect(throws: VaultError.notFound) { try await store.delete(added.id) }
    }

    @Test func unlockFailuresAreReported() async {
        await store.setUnlockFailure(.authenticationCancelled)
        await #expect(throws: VaultError.authenticationCancelled) {
            try await store.unlock(reason: "test")
        }
        #expect(await !store.isUnlocked)
    }

    @Test func listsInCreationOrder() async throws {
        let clock = TestClock()
        let store = InMemorySecretStore(now: { clock.tick() })
        _ = try await store.add(name: "First", value: SecretValue("1"))
        _ = try await store.add(name: "Second", value: SecretValue("2"))
        try await store.unlock(reason: "test")
        #expect(try await store.list().map(\.name) == ["First", "Second"])
    }
}

/// A clock that moves one second per call.
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)

    func tick() -> Date {
        lock.withLock {
            current = current.addingTimeInterval(1)
            return current
        }
    }
}
