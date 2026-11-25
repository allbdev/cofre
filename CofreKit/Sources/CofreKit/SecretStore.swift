import Foundation

/// What the list shows about a secret. Never holds the value.
public struct SecretSummary: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(id: UUID, name: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Where secrets live. Stores don't validate names; `VaultModel` does that before calling them.
///
/// Adding and deleting never need an unlock. Listing, reading a value, renaming and replacing a
/// value need `unlock(reason:)` first and throw `VaultError.locked` otherwise: the Keychain won't
/// even return the names of `.userPresence` items without authentication. An empty store lists
/// as empty, locked or not. Stores never show an authentication prompt of their own outside
/// `unlock(reason:)`.
public protocol SecretStore: Sendable {
    func list() async throws(VaultError) -> [SecretSummary]
    func add(name: String, value: SecretValue) async throws(VaultError) -> SecretSummary
    func rename(_ id: UUID, to name: String) async throws(VaultError)
    func replaceValue(_ id: UUID, with value: SecretValue) async throws(VaultError)
    func delete(_ id: UUID) async throws(VaultError)
    func value(for id: UUID) async throws(VaultError) -> SecretValue

    /// Asks for Touch ID or the Mac password. `reason` completes "Cofre is trying to …".
    func unlock(reason: String) async throws(VaultError)
    func lock() async
    var isUnlocked: Bool { get async }
}
