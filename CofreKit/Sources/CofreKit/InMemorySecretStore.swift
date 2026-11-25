import Foundation

/// A store that forgets everything when the app quits. Used by tests and by unsigned debug runs
/// (`-CofreStore memory`). It follows the same lock rules as the Keychain store.
public actor InMemorySecretStore: SecretStore {
    private struct Entry {
        var summary: SecretSummary
        var value: SecretValue
    }

    private var entries: [UUID: Entry] = [:]
    private var unlocked = false
    private let now: @Sendable () -> Date

    /// What `unlock` does: `nil` succeeds, an error makes it fail (to test cancel and failure).
    public var unlockFailure: VaultError?
    public private(set) var unlockCount = 0
    /// When set, `list()` fails with it (to test an unusable store).
    public var listFailure: VaultError?

    public init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    public func setUnlockFailure(_ failure: VaultError?) {
        unlockFailure = failure
    }

    public func setListFailure(_ failure: VaultError?) {
        listFailure = failure
    }

    public func list() throws(VaultError) -> [SecretSummary] {
        if let listFailure { throw listFailure }
        guard unlocked || entries.isEmpty else { throw .locked }
        return entries.values.map(\.summary).sorted { $0.createdAt < $1.createdAt }
    }

    public func add(name: String, value: SecretValue) throws(VaultError) -> SecretSummary {
        let date = now()
        let summary = SecretSummary(id: UUID(), name: name, createdAt: date, updatedAt: date)
        entries[summary.id] = Entry(summary: summary, value: value)
        return summary
    }

    public func rename(_ id: UUID, to name: String) throws(VaultError) {
        guard unlocked else { throw .locked }
        guard entries[id] != nil else { throw .notFound }
        entries[id]?.summary.name = name
        entries[id]?.summary.updatedAt = now()
    }

    public func replaceValue(_ id: UUID, with value: SecretValue) throws(VaultError) {
        guard unlocked else { throw .locked }
        guard entries[id] != nil else { throw .notFound }
        entries[id]?.value = value
        entries[id]?.summary.updatedAt = now()
    }

    public func delete(_ id: UUID) throws(VaultError) {
        guard entries.removeValue(forKey: id) != nil else { throw .notFound }
    }

    public func value(for id: UUID) throws(VaultError) -> SecretValue {
        guard unlocked else { throw .locked }
        guard let entry = entries[id] else { throw .notFound }
        return entry.value
    }

    public func unlock(reason: String) throws(VaultError) {
        unlockCount += 1
        if let unlockFailure { throw unlockFailure }
        unlocked = true
    }

    public func lock() {
        unlocked = false
    }

    public var isUnlocked: Bool { unlocked }
}
