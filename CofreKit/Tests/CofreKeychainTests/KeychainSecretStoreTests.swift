import CofreKit
import Foundation
import LocalAuthentication
import Security
import Testing

@testable import CofreKeychain

/// Mapping rules: pure, always run.
struct KeychainErrorMappingTests {
    @Test(
        arguments: [
            (errSecSuccess, nil),
            (errSecItemNotFound, VaultError.notFound),
            (errSecMissingEntitlement, .keychainUnavailable),
            (errSecUserCanceled, .authenticationCancelled),
            (errSecAuthFailed, .authenticationFailed),
            (errSecInteractionNotAllowed, .locked),
            (errSecDuplicateItem, .keychain(status: errSecDuplicateItem)),
        ] as [(OSStatus, VaultError?)])
    func statusCodes(_ status: OSStatus, _ expected: VaultError?) {
        #expect(KeychainSecretStore.map(status) == expected)
    }

    @Test(arguments: [
        (LAError.Code.userCancel, VaultError.authenticationCancelled),
        (.systemCancel, .authenticationCancelled),
        (.appCancel, .authenticationCancelled),
        (.userFallback, .authenticationCancelled),
        (.authenticationFailed, .authenticationFailed),
        (.biometryLockout, .authenticationFailed),
    ])
    func authenticationErrors(_ code: LAError.Code, _ expected: VaultError) {
        #expect(KeychainSecretStore.map(LAError(code)) == expected)
    }

    @Test func unknownErrorsAreFailures() {
        #expect(KeychainSecretStore.map(nil as (any Error)?) == .authenticationFailed)
    }

    @Test func summaryFromAttributes() throws {
        let id = UUID()
        let created = Date(timeIntervalSince1970: 1_800_000_000)
        let summary = try #require(
            KeychainSecretStore.summary(from: [
                kSecAttrAccount: id.uuidString,
                kSecAttrLabel: "Token",
                kSecAttrCreationDate: created,
            ])
        )
        #expect(summary == SecretSummary(id: id, name: "Token", createdAt: created, updatedAt: created))
        #expect(KeychainSecretStore.summary(from: [kSecAttrAccount: "not-a-uuid"]) == nil)
    }
}

/// Real Keychain round trips. They need a signed binary allowed to use the data protection
/// Keychain, so they're skipped under a plain `swift test`.
@Suite(.enabled(if: KeychainAvailability.isAvailable, KeychainAvailability.skipReason))
struct KeychainSecretStoreIntegrationTests {
    let store = KeychainSecretStore(service: "cofre.tests.\(UUID().uuidString)")

    @Test func addAndDeleteWithoutUnlocking() async throws {
        defer { Task { [store] in try? await store.deleteAll() } }
        #expect(try await store.list().isEmpty)
        let added = try await store.add(name: "Integration token", value: SecretValue("value"))
        try await store.delete(added.id)
        #expect(try await store.list().isEmpty)
    }

    /// The Keychain wants authentication even for the names of `.userPresence` items. Locked,
    /// listing must fail with `.locked`, never fall back to the system's own prompt (which
    /// stole focus from the quick panel).
    @Test func listingWhileLockedFailsInsteadOfPrompting() async throws {
        defer { Task { [store] in try? await store.deleteAll() } }
        _ = try await store.add(name: "Listed while locked", value: SecretValue("value"))
        await store.lock()
        await #expect(throws: VaultError.locked) { try await store.list() }
    }

    @Test func readingWithoutUnlockIsRefused() async throws {
        defer { Task { [store] in try? await store.deleteAll() } }
        let added = try await store.add(name: "Locked", value: SecretValue("value"))
        await #expect(throws: VaultError.locked) { try await store.value(for: added.id) }
    }
}

enum KeychainAvailability {
    static let skipReason: Comment =
        "Keychain integration tests need a signed test host (data protection Keychain unavailable)"

    /// Tries to add and delete a throwaway item.
    static let isAvailable: Bool = {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "cofre.tests.probe",
            kSecAttrAccount: UUID().uuidString,
            kSecUseDataProtectionKeychain: true,
            kSecValueData: Data("probe".utf8),
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess {
            SecItemDelete(query as CFDictionary)
            return true
        }
        print("Skipping Keychain integration tests: SecItemAdd returned \(status)")
        return false
    }()
}
