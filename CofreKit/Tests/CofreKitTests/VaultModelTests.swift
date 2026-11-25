import Foundation
import Testing

@testable import CofreKit

@MainActor
final class VaultModelHarness {
    var currentDate = Date(timeIntervalSince1970: 1_800_000_000)
    let store: InMemorySecretStore
    let pasteboard = FakePasteboard()
    let preferences = InMemoryPreferences()
    private(set) var model: VaultModel!

    init() {
        let clock = TestClock()
        store = InMemorySecretStore(now: { clock.tick() })
        let clipboard = ClipboardService(
            pasteboard: pasteboard,
            now: { [unowned self] in currentDate },
            sleep: { _ in try await Task.sleep(for: .seconds(3600)) }
        )
        model = VaultModel(
            store: store,
            clipboard: clipboard,
            preferences: preferences,
            exportCodec: ExportCodec(iterations: 1_000, acceptedIterations: 1_000...10_000_000),
            now: { [unowned self] in currentDate }
        )
    }

    func advance(_ seconds: TimeInterval) {
        currentDate = currentDate.addingTimeInterval(seconds)
    }

    @discardableResult
    func add(_ name: String, _ value: String) async -> SecretSummary {
        let ok = await model.add(name: name, value: SecretValue(value))
        precondition(ok, "add failed: \(String(describing: model.error))")
        return model.secrets.first { $0.name == SecretName.trimmed(name) }!
    }
}

@MainActor
struct VaultModelTests {
    let harness = VaultModelHarness()
    var model: VaultModel { harness.model }

    // MARK: - Add, rename, replace, delete

    @Test func addsWithoutUnlocking() async {
        await harness.add("  GitHub token ", "ghp_123")
        #expect(model.secrets.map(\.name) == ["GitHub token"])
        #expect(!model.isUnlocked)
        #expect(await harness.store.unlockCount == 0)
    }

    @Test func refusesBadInputWithAMessage() async {
        await harness.add("Token", "x")
        #expect(await !model.add(name: "", value: SecretValue("x")))
        #expect(model.error == .nameEmpty)
        #expect(await !model.add(name: "TOKEN", value: SecretValue("x")))
        #expect(model.error == .nameTaken("Token"))
        #expect(await !model.add(name: "Other", value: SecretValue("")))
        #expect(model.error == .valueEmpty)
        let huge = SecretValue(data: Data(count: SecretValue.maximumByteCount + 1))
        #expect(await !model.add(name: "Other", value: huge))
        #expect(model.error == .valueTooLarge)
        #expect(model.secrets.count == 1)
    }

    @Test func renameUnlocksAndChecksClashes() async {
        let token = await harness.add("Token", "x")
        await harness.add("Other", "y")
        #expect(await !model.rename(token.id, to: "other"))
        #expect(model.error == .nameTaken("Other"))
        #expect(await model.rename(token.id, to: "Renamed"))
        #expect(model.secrets.map(\.name).sorted() == ["Other", "Renamed"])
        #expect(model.isUnlocked)
    }

    @Test func renamingToTheSameNameDoesNothing() async {
        let token = await harness.add("Token", "x")
        #expect(await model.rename(token.id, to: " Token "))
        #expect(await harness.store.unlockCount == 0)
    }

    @Test func replaceValueChangesWhatGetsCopied() async {
        let token = await harness.add("Token", "old")
        #expect(await model.replaceValue(token.id, with: SecretValue("new")))
        #expect(await model.copy(token.id))
        #expect(harness.pasteboard.contents == "new")
    }

    @Test func deleteRemovesAndForgetsTheReceipt() async {
        let token = await harness.add("Token", "x")
        await model.copy(token.id)
        #expect(await model.delete(token.id))
        #expect(model.secrets.isEmpty)
        #expect(model.lastCopy == nil)
    }

    // MARK: - Copy and unlock

    @Test func copyUnlocksOnceThenReuses() async {
        let first = await harness.add("First", "1")
        let second = await harness.add("Second", "2")
        #expect(await model.copy(first.id))
        #expect(harness.pasteboard.contents == "1")
        #expect(await model.copy(second.id))
        #expect(harness.pasteboard.contents == "2")
        #expect(await harness.store.unlockCount == 1)
        #expect(harness.pasteboard.concealedWrites == 2)
    }

    @Test func copyReceiptSaysWhenItClears() async {
        harness.preferences.clipboardClearDelay = 60
        let token = await harness.add("Token", "x")
        await model.copy(token.id)
        #expect(model.lastCopy?.name == "Token")
        #expect(model.lastCopy?.clearsAt == harness.currentDate.addingTimeInterval(60))
    }

    @Test func cancelledUnlockIsQuiet() async {
        let token = await harness.add("Token", "x")
        await harness.store.setUnlockFailure(.authenticationCancelled)
        #expect(await !model.copy(token.id))
        #expect(model.error == nil)
        #expect(harness.pasteboard.contents == nil)
    }

    @Test func failedUnlockIsReported() async {
        let token = await harness.add("Token", "x")
        await harness.store.setUnlockFailure(.authenticationFailed)
        #expect(await !model.copy(token.id))
        #expect(model.error == .authenticationFailed)
    }

    @Test func expiredSessionUnlocksAgain() async {
        let token = await harness.add("Token", "x")
        await model.unlock()
        await harness.store.lock()  // e.g. the system invalidated the context
        #expect(await model.copy(token.id))
        #expect(await harness.store.unlockCount == 2)
    }

    @Test func copyingAMissingSecretFails() async {
        #expect(await !model.copy(UUID()))
        #expect(model.error == .notFound)
    }

    // MARK: - Lock

    @Test func lockClearsOurClipboardAndTheSession() async {
        let token = await harness.add("Token", "x")
        await model.copy(token.id)
        await model.lock()
        #expect(!model.isUnlocked)
        #expect(await !harness.store.isUnlocked)
        #expect(harness.pasteboard.contents == nil)
        #expect(model.lastCopy == nil)
    }

    @Test func idleTimeoutLocks() async {
        harness.preferences.autoLockTimeout = 60
        await model.unlock()
        harness.advance(59)
        await model.lockIfIdle()
        #expect(model.isUnlocked)
        model.noteActivity()
        harness.advance(59)
        await model.lockIfIdle()
        #expect(model.isUnlocked)
        harness.advance(1)
        await model.lockIfIdle()
        #expect(!model.isUnlocked)
    }

    @Test func quittingClearsOurClipboard() async {
        let token = await harness.add("Token", "x")
        await model.copy(token.id)
        model.prepareForQuit()
        #expect(harness.pasteboard.contents == nil)
    }

    @Test func unsignedKeychainIsReportedAsUnavailableNotAsAnAlert() async {
        await harness.store.setListFailure(.keychainUnavailable)
        await model.reload()
        #expect(model.isStoreUnavailable)
        #expect(model.error == nil)
        #expect(model.isLoaded)
        await harness.store.setListFailure(nil)
        await model.reload()
        #expect(!model.isStoreUnavailable)
    }

    @Test func otherListFailuresAreAlerts() async {
        await harness.store.setListFailure(.keychain(status: -1))
        await model.reload()
        #expect(model.error == .keychain(status: -1))
        #expect(!model.isStoreUnavailable)
    }

    @Test func systemEventsLock() async {
        await model.unlock()
        await model.handle(.screenLocked)
        #expect(!model.isUnlocked)
    }

    // MARK: - Search

    @Test func resultsFollowTheQuery() async {
        await harness.add("Stripe key", "1")
        await harness.add("AWS", "2")
        model.query = "str"
        #expect(model.results.map(\.name) == ["Stripe key"])
        model.query = ""
        #expect(model.results.map(\.name) == ["AWS", "Stripe key"])
    }

    // MARK: - Clipboard input

    @Test func valueFromClipboard() {
        harness.pasteboard.simulateOtherCopy("-----BEGIN KEY-----\nabc")
        #expect(model.valueFromClipboard() == SecretValue("-----BEGIN KEY-----\nabc"))
        model.clearClipboard()
        #expect(model.valueFromClipboard() == nil)
    }

    // MARK: - Backup status

    @Test func backupStatusFollowsChangesAndExports() async {
        await model.reload()
        #expect(model.backupStatus == .nothingToBackUp)
        await harness.add("Token", "x")
        #expect(model.backupStatus == .neverExported)
        harness.advance(10)
        model.recordExport()
        let exported = harness.currentDate
        #expect(model.backupStatus == .upToDate(lastExport: exported))
        harness.advance(10)
        await harness.add("Other", "y")
        #expect(model.backupStatus == .changedSinceExport(lastExport: exported))
        #expect(model.backupStatus.needsAttention)
    }

    // MARK: - Export and import

    @Test func exportChecksThePassphrases() async {
        await harness.add("Token", "x")
        #expect(await model.makeExport(passphrase: "short", confirmation: "short") == nil)
        #expect(model.error == .passphraseTooShort)
        #expect(await model.makeExport(passphrase: "long enough pass", confirmation: "long enough typo") == nil)
        #expect(model.error == .passphrasesDontMatch)
    }

    @Test func exportThenImportIntoAnEmptyVault() async throws {
        await harness.add("Token", "abc")
        await harness.add("PEM", "-----BEGIN-----\nxyz")
        let data = try #require(
            await model.makeExport(passphrase: "long enough pass", confirmation: "long enough pass"))

        let other = VaultModelHarness()
        let preview = try #require(await other.model.prepareImport(data: data, passphrase: "long enough pass"))
        #expect(preview.conflictCount == 0)
        let summary = await other.model.applyImport(preview, strategy: .skip)
        #expect(summary == ImportSummary(added: 2, replaced: 0, skipped: 0))
        #expect(other.model.secrets.map(\.name).sorted() == ["PEM", "Token"])
        let pem = try #require(other.model.secrets.first { $0.name == "PEM" })
        await other.model.copy(pem.id)
        #expect(other.pasteboard.contents == "-----BEGIN-----\nxyz")
    }

    @Test func importWithConflicts() async throws {
        let token = await harness.add("Token", "old")
        let source = VaultModelHarness()
        await source.add("token", "new")
        await source.add("Fresh", "f")
        let data = try #require(
            await source.model.makeExport(passphrase: "long enough pass", confirmation: "long enough pass"))

        let preview = try #require(await model.prepareImport(data: data, passphrase: "long enough pass"))
        #expect(preview.conflictCount == 1)
        let summary = await model.applyImport(preview, strategy: .replace)
        #expect(summary == ImportSummary(added: 1, replaced: 1, skipped: 0))
        await model.copy(token.id)
        #expect(harness.pasteboard.contents == "new")
    }

    @Test func importWithKeepBoth() async throws {
        await harness.add("Token", "old")
        let source = VaultModelHarness()
        await source.add("Token", "new")
        let data = try #require(
            await source.model.makeExport(passphrase: "long enough pass", confirmation: "long enough pass"))
        let preview = try #require(await model.prepareImport(data: data, passphrase: "long enough pass"))
        _ = await model.applyImport(preview, strategy: .keepBoth)
        #expect(model.secrets.map(\.name).sorted() == ["Token", "Token (2)"])
    }

    @Test func importWithTheWrongPassphrase() async throws {
        await harness.add("Token", "x")
        let data = try #require(
            await model.makeExport(passphrase: "long enough pass", confirmation: "long enough pass"))
        #expect(await model.prepareImport(data: data, passphrase: "wrong passphrase!") == nil)
        #expect(model.error == .exportDecryptionFailed)
    }

    @Test func skippedOnlyImportChangesNothing() async throws {
        await harness.add("Token", "x")
        let data = try #require(
            await model.makeExport(passphrase: "long enough pass", confirmation: "long enough pass"))
        model.recordExport()
        let preview = try #require(await model.prepareImport(data: data, passphrase: "long enough pass"))
        let summary = await model.applyImport(preview, strategy: .skip)
        #expect(summary == ImportSummary(added: 0, replaced: 0, skipped: 1))
        #expect(!model.backupStatus.needsAttention)
    }

    @Test func suggestedFileNameUsesTheExtension() {
        #expect(VaultModel.suggestedExportFileName.hasPrefix("Cofre "))
        #expect(VaultModel.suggestedExportFileName.hasSuffix(".cofre"))
    }
}
