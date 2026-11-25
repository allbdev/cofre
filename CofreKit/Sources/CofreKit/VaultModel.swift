import Foundation
import Observation

/// Shown after a copy: "Copied “Stripe key”, clears in 30 s".
public struct CopyReceipt: Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var copiedAt: Date
    public var clearsAt: Date
}

/// Whether the user should be nudged to export (`PLAN.md` D8).
public enum BackupStatus: Equatable, Sendable {
    case nothingToBackUp
    case neverExported
    case changedSinceExport(lastExport: Date)
    case upToDate(lastExport: Date)

    public var needsAttention: Bool {
        switch self {
        case .neverExported, .changedSinceExport: true
        case .nothingToBackUp, .upToDate: false
        }
    }
}

/// A decrypted export, waiting for the user to pick a conflict strategy.
public struct ImportPreview: Sendable, Equatable {
    public var payload: ExportPayload
    public var conflictCount: Int
}

public struct ImportSummary: Sendable, Equatable {
    public var added: Int
    public var replaced: Int
    public var skipped: Int
}

/// Everything the views need: the list, search, changes, copy, lock state, backup.
/// Validation happens here, before the store is called. Failures land in `error`.
@MainActor
@Observable
public final class VaultModel {
    public private(set) var secrets: [SecretSummary] = []
    public var query = ""
    public private(set) var isLoaded = false
    public private(set) var isUnlocked = false
    public private(set) var lastCopy: CopyReceipt?
    public private(set) var backupStatus: BackupStatus = .nothingToBackUp
    /// The last failure, for an alert. Set to `nil` to dismiss.
    public var error: VaultError?

    public var results: [SecretSummary] {
        SearchRanker.rank(secrets, query: query, name: \.name)
    }

    @ObservationIgnored public let preferences: any Preferences
    @ObservationIgnored private let store: any SecretStore
    @ObservationIgnored private let clipboard: ClipboardService
    @ObservationIgnored private let exportCodec: ExportCodec
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var lastActivity: Date

    public init(
        store: any SecretStore,
        clipboard: ClipboardService,
        preferences: any Preferences,
        exportCodec: ExportCodec = ExportCodec(),
        now: @escaping () -> Date = { Date() }
    ) {
        self.store = store
        self.clipboard = clipboard
        self.preferences = preferences
        self.exportCodec = exportCodec
        self.now = now
        lastActivity = now()
    }

    // MARK: - Loading

    public func reload() async {
        do {
            secrets = try await store.list()
            isUnlocked = await store.isUnlocked
        } catch {
            self.error = error
        }
        isLoaded = true
        refreshBackupStatus()
    }

    // MARK: - Changes

    @discardableResult
    public func add(name: String, value: SecretValue) async -> Bool {
        await perform {
            let name = try SecretName.validate(name, against: secrets)
            try Self.validate(value)
            _ = try await store.add(name: name, value: value)
            await afterChange()
        }
    }

    @discardableResult
    public func rename(_ id: UUID, to newName: String) async -> Bool {
        await perform {
            let name = try SecretName.validate(newName, against: secrets, excluding: id)
            guard secrets.first(where: { $0.id == id })?.name != name else { return }
            try await withUnlock { try await store.rename(id, to: name) }
            await afterChange()
        }
    }

    @discardableResult
    public func replaceValue(_ id: UUID, with value: SecretValue) async -> Bool {
        await perform {
            try Self.validate(value)
            try await withUnlock { try await store.replaceValue(id, with: value) }
            await afterChange()
        }
    }

    @discardableResult
    public func delete(_ id: UUID) async -> Bool {
        await perform {
            try await store.delete(id)
            if lastCopy?.id == id { lastCopy = nil }
            await afterChange()
        }
    }

    // MARK: - Copy

    @discardableResult
    public func copy(_ id: UUID) async -> Bool {
        guard let summary = secrets.first(where: { $0.id == id }) else {
            error = .notFound
            return false
        }
        return await perform {
            let value = try await withUnlock { try await store.value(for: id) }
            let delay = preferences.clipboardClearDelay
            clipboard.copy(value, clearAfter: delay)
            let date = now()
            lastCopy = CopyReceipt(
                id: id,
                name: summary.name,
                copiedAt: date,
                clearsAt: date.addingTimeInterval(delay)
            )
        }
    }

    /// The clipboard's text as a value, for "Paste from clipboard". `nil` when there's no text.
    public func valueFromClipboard() -> SecretValue? {
        guard let text = clipboard.readString(), !text.isEmpty else { return nil }
        return SecretValue(text)
    }

    public func clearClipboard() {
        clipboard.clearAll()
    }

    // MARK: - Lock

    @discardableResult
    public func unlock() async -> Bool {
        await perform { try await ensureUnlocked() }
    }

    public func lock() async {
        await store.lock()
        isUnlocked = false
        clipboard.clearIfStillOurs()
        lastCopy = nil
    }

    public func noteActivity() {
        lastActivity = now()
    }

    public func lockIfIdle() async {
        let policy = LockPolicy(idleTimeout: preferences.autoLockTimeout)
        if isUnlocked, policy.shouldLock(lastActivity: lastActivity, now: now()) {
            await lock()
        }
    }

    public func handle(_ event: LockPolicy.Event) async {
        let policy = LockPolicy(idleTimeout: preferences.autoLockTimeout)
        if policy.shouldLock(on: event) {
            await lock()
        }
    }

    // MARK: - Export

    /// Encrypts every secret with `passphrase`. Call `recordExport()` once the file is saved.
    public func makeExport(passphrase: String, confirmation: String) async -> Data? {
        var result: Data?
        _ = await perform {
            guard passphrase.count >= ExportCodec.minimumPassphraseLength else {
                throw VaultError.passphraseTooShort
            }
            guard passphrase == confirmation else { throw VaultError.passphrasesDontMatch }
            try await ensureUnlocked()
            var items: [ExportItem] = []
            for summary in secrets {
                let value = try await store.value(for: summary.id)
                items.append(
                    ExportItem(
                        name: summary.name,
                        value: value,
                        createdAt: summary.createdAt,
                        updatedAt: summary.updatedAt
                    )
                )
            }
            let payload = ExportPayload(exportedAt: now(), items: items)
            result = try await Self.offMain { [exportCodec] in
                try exportCodec.encode(payload, passphrase: passphrase)
            }
        }
        return result
    }

    public func recordExport() {
        preferences.lastExportAt = now()
        refreshBackupStatus()
    }

    public static var suggestedExportFileName: String {
        let day = Date().formatted(.iso8601.year().month().day())
        return "Cofre \(day).\(ExportCodec.fileExtension)"
    }

    // MARK: - Import

    public func prepareImport(data: Data, passphrase: String) async -> ImportPreview? {
        var preview: ImportPreview?
        _ = await perform {
            let payload = try await Self.offMain { [exportCodec] in
                try exportCodec.decode(data, passphrase: passphrase)
            }
            preview = ImportPreview(
                payload: payload,
                conflictCount: ImportPlanner.conflictCount(
                    incoming: payload.items.map(\.name),
                    existing: secrets
                )
            )
        }
        return preview
    }

    public func applyImport(
        _ preview: ImportPreview,
        strategy: ImportConflictStrategy
    ) async -> ImportSummary? {
        var summary: ImportSummary?
        _ = await perform {
            let items = preview.payload.items
            let plan = ImportPlanner.plan(
                incoming: items.map(\.name),
                existing: secrets,
                strategy: strategy
            )
            if plan.replacedCount > 0 { try await ensureUnlocked() }
            var addedIDs: [Int: UUID] = [:]
            for (stepIndex, step) in plan.steps.enumerated() {
                switch step {
                case .add(let index, let name):
                    addedIDs[stepIndex] = try await store.add(name: name, value: items[index].value).id
                case .replace(let index, let id):
                    try await store.replaceValue(id, with: items[index].value)
                case .replacePending(let index, let pendingStep):
                    guard let id = addedIDs[pendingStep] else { throw VaultError.notFound }
                    try await store.replaceValue(id, with: items[index].value)
                case .skip:
                    break
                }
            }
            if plan.addedCount + plan.replacedCount > 0 {
                await afterChange()
            }
            summary = ImportSummary(
                added: plan.addedCount,
                replaced: plan.replacedCount,
                skipped: plan.skippedCount
            )
        }
        return summary
    }

    // MARK: - Helpers

    private static func validate(_ value: SecretValue) throws(VaultError) {
        guard !value.isEmpty else { throw .valueEmpty }
        guard value.byteCount <= SecretValue.maximumByteCount else { throw .valueTooLarge }
    }

    private func ensureUnlocked() async throws(VaultError) {
        noteActivity()
        if await store.isUnlocked {
            isUnlocked = true
            return
        }
        try await store.unlock(reason: String(localized: "unlock your secrets"))
        isUnlocked = true
    }

    /// Unlocks if needed, runs `operation`, and unlocks once more if the session expired meanwhile.
    private func withUnlock<T>(
        _ operation: () async throws -> T
    ) async throws -> T {
        try await ensureUnlocked()
        do {
            return try await operation()
        } catch VaultError.locked {
            isUnlocked = false
            try await ensureUnlocked()
            return try await operation()
        }
    }

    private func afterChange() async {
        preferences.lastChangeAt = now()
        do {
            secrets = try await store.list()
        } catch {
            self.error = error
        }
        refreshBackupStatus()
    }

    private func refreshBackupStatus() {
        guard !secrets.isEmpty else {
            backupStatus = .nothingToBackUp
            return
        }
        guard let lastExport = preferences.lastExportAt else {
            backupStatus = .neverExported
            return
        }
        if let lastChange = preferences.lastChangeAt, lastChange > lastExport {
            backupStatus = .changedSinceExport(lastExport: lastExport)
        } else {
            backupStatus = .upToDate(lastExport: lastExport)
        }
    }

    /// Runs `body`, storing a failure in `error`. Returns whether it succeeded.
    private func perform(_ body: () async throws -> Void) async -> Bool {
        noteActivity()
        do {
            try await body()
            return true
        } catch {
            let failure = (error as? VaultError) ?? .keychain(status: -1)
            if failure != .authenticationCancelled {
                self.error = failure
            }
            return false
        }
    }

    /// PBKDF2 with 600 000 iterations takes a moment; keep it off the main actor.
    private static func offMain<T: Sendable>(
        _ work: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await Task.detached(priority: .userInitiated) { try work() }.value
    }
}
