import CofreKit
import Foundation
import LocalAuthentication
import Security

/// Secrets in the macOS data protection Keychain (`PLAN.md` D3):
/// one generic-password item per secret, this device only, never synchronized, readable only
/// with user presence (Touch ID or the Mac password). The name is the item's label and the id
/// its account; the Keychain keeps the creation and modification dates.
///
/// An unlock evaluates one `LAContext`; reads pass it along so they don't prompt again until
/// `lock()` invalidates it.
public actor KeychainSecretStore: SecretStore {
    public static let defaultService = "cofre.secret"

    private let service: String
    private var context: LAContext?

    /// `service` separates items; tests use a unique one and delete it afterwards.
    public init(service: String = KeychainSecretStore.defaultService) {
        self.service = service
    }

    // MARK: - SecretStore

    /// Names and dates only. The Keychain wants authentication even for these on `.userPresence`
    /// items, and without a context it runs its own generic prompt, which steals focus from the
    /// quick panel. So: unlocked, the session's context is reused; locked, a context that refuses
    /// interaction makes the Keychain fail with `.locked` instead (`PLAN.md` D5).
    public func list() throws(VaultError) -> [SecretSummary] {
        var query = baseQuery
        query[kSecMatchLimit] = kSecMatchLimitAll
        query[kSecReturnAttributes] = true
        query[kSecUseAuthenticationContext] = context ?? Self.nonInteractiveContext()

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        try Self.check(status)
        let items = (result as? [[CFString: Any]]) ?? []
        return items.compactMap(Self.summary(from:)).sorted { $0.createdAt < $1.createdAt }
    }

    public func add(name: String, value: SecretValue) throws(VaultError) -> SecretSummary {
        var error: Unmanaged<CFError>?
        guard
            let access = SecAccessControlCreateWithFlags(
                nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                .userPresence,
                &error
            )
        else {
            error?.release()
            throw .keychain(status: errSecParam)
        }

        let id = UUID()
        var attributes = baseQuery
        attributes[kSecAttrAccount] = id.uuidString
        attributes[kSecAttrLabel] = name
        attributes[kSecValueData] = value.exposedData
        attributes[kSecAttrAccessControl] = access
        try Self.check(SecItemAdd(attributes as CFDictionary, nil))

        let now = Date()
        return SecretSummary(id: id, name: name, createdAt: now, updatedAt: now)
    }

    public func rename(_ id: UUID, to name: String) throws(VaultError) {
        try update(id, with: [kSecAttrLabel: name])
    }

    public func replaceValue(_ id: UUID, with value: SecretValue) throws(VaultError) {
        try update(id, with: [kSecValueData: value.exposedData])
    }

    public func delete(_ id: UUID) throws(VaultError) {
        try Self.check(SecItemDelete(itemQuery(id) as CFDictionary))
    }

    public func value(for id: UUID) throws(VaultError) -> SecretValue {
        guard let context else { throw .locked }
        var query = itemQuery(id)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        query[kSecUseAuthenticationContext] = context

        var result: CFTypeRef?
        try Self.check(SecItemCopyMatching(query as CFDictionary, &result))
        guard let data = result as? Data else { throw .notFound }
        return SecretValue(data: data)
    }

    public func unlock(reason: String) async throws(VaultError) {
        let context = LAContext()
        let outcome: Result<Void, VaultError> = await withCheckedContinuation { continuation in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, error in
                if success {
                    continuation.resume(returning: .success(()))
                } else {
                    continuation.resume(returning: .failure(Self.map(error)))
                }
            }
        }
        try outcome.get()
        self.context?.invalidate()
        self.context = context
    }

    public func lock() {
        context?.invalidate()
        context = nil
    }

    public var isUnlocked: Bool { context != nil }

    // MARK: - Test support

    /// Deletes every item of this store's service. Used by integration tests to clean up.
    public func deleteAll() throws(VaultError) {
        let status = SecItemDelete(baseQuery as CFDictionary)
        if status != errSecItemNotFound { try Self.check(status) }
    }

    // MARK: - Helpers

    private var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecUseDataProtectionKeychain: true,
            kSecAttrSynchronizable: false,
        ]
    }

    private static func nonInteractiveContext() -> LAContext {
        let context = LAContext()
        context.interactionNotAllowed = true
        return context
    }

    private func itemQuery(_ id: UUID) -> [CFString: Any] {
        var query = baseQuery
        query[kSecAttrAccount] = id.uuidString
        return query
    }

    private func update(_ id: UUID, with changes: [CFString: Any]) throws(VaultError) {
        guard let context else { throw .locked }
        var query = itemQuery(id)
        query[kSecUseAuthenticationContext] = context
        try Self.check(SecItemUpdate(query as CFDictionary, changes as CFDictionary))
    }

    static func summary(from attributes: [CFString: Any]) -> SecretSummary? {
        guard let account = attributes[kSecAttrAccount] as? String, let id = UUID(uuidString: account)
        else { return nil }
        let created = attributes[kSecAttrCreationDate] as? Date ?? .distantPast
        return SecretSummary(
            id: id,
            name: attributes[kSecAttrLabel] as? String ?? "",
            createdAt: created,
            updatedAt: attributes[kSecAttrModificationDate] as? Date ?? created
        )
    }

    static func check(_ status: OSStatus) throws(VaultError) {
        if let error = map(status) { throw error }
    }

    /// Keychain status → what the user sees. `nil` means success.
    static func map(_ status: OSStatus) -> VaultError? {
        switch status {
        case errSecSuccess: nil
        case errSecItemNotFound: .notFound
        case errSecMissingEntitlement: .keychainUnavailable
        case errSecUserCanceled: .authenticationCancelled
        case errSecAuthFailed: .authenticationFailed
        case errSecInteractionNotAllowed: .locked
        default: .keychain(status: status)
        }
    }

    /// LocalAuthentication error → what the user sees.
    static func map(_ error: (any Error)?) -> VaultError {
        guard let laError = error as? LAError else { return .authenticationFailed }
        switch laError.code {
        case .userCancel, .appCancel, .systemCancel, .userFallback:
            return .authenticationCancelled
        default:
            return .authenticationFailed
        }
    }
}
