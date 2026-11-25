import Foundation
import Testing

@testable import CofreKit

struct ClipboardGuardTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func clearsOnlyAfterTheDelay() {
        var clipboardGuard = ClipboardGuard()
        clipboardGuard.didCopy(changeCount: 5, at: start, delay: 30)
        #expect(!clipboardGuard.shouldClear(currentChangeCount: 5, now: start.addingTimeInterval(29)))
        #expect(clipboardGuard.shouldClear(currentChangeCount: 5, now: start.addingTimeInterval(30)))
    }

    @Test func neverClearsSomethingElse() {
        var clipboardGuard = ClipboardGuard()
        clipboardGuard.didCopy(changeCount: 5, at: start, delay: 30)
        #expect(!clipboardGuard.shouldClear(currentChangeCount: 6, now: start.addingTimeInterval(60)))
        #expect(!clipboardGuard.isStillOurs(currentChangeCount: 6))
    }

    @Test func nothingToClearBeforeAnyCopyOrAfterReset() {
        var clipboardGuard = ClipboardGuard()
        #expect(!clipboardGuard.shouldClear(currentChangeCount: 0, now: start))
        clipboardGuard.didCopy(changeCount: 1, at: start, delay: 0)
        clipboardGuard.reset()
        #expect(!clipboardGuard.shouldClear(currentChangeCount: 1, now: start.addingTimeInterval(100)))
    }
}

@MainActor
final class FakePasteboard: Pasteboard {
    private(set) var changeCount = 0
    private(set) var contents: String?
    private(set) var concealedWrites = 0

    func writeConcealed(_ value: SecretValue) -> Int {
        changeCount += 1
        concealedWrites += 1
        contents = value.exposedString()
        return changeCount
    }

    func readString() -> String? { contents }

    func clear() {
        changeCount += 1
        contents = nil
    }

    /// Another app copying something.
    func simulateOtherCopy(_ text: String) {
        changeCount += 1
        contents = text
    }
}

@MainActor
struct ClipboardServiceTests {
    let pasteboard = FakePasteboard()

    @Test func copiesConcealedAndClearsWhenTheDelayEnds() async {
        let service = ClipboardService(pasteboard: pasteboard, now: { Date.distantFuture }, sleep: { _ in })
        service.copy(SecretValue("secret"), clearAfter: 30)
        #expect(pasteboard.concealedWrites == 1)
        await service.pendingClear?.value
        #expect(pasteboard.contents == nil)
    }

    @Test func leavesALaterCopyAlone() async {
        let service = ClipboardService(
            pasteboard: pasteboard, now: { Date.distantFuture }, sleep: { _ in await Task.yield() })
        service.copy(SecretValue("secret"), clearAfter: 30)
        pasteboard.simulateOtherCopy("my own text")
        await service.pendingClear?.value
        #expect(pasteboard.contents == "my own text")
    }

    @Test func cancelledSleepDoesNotClear() async {
        let service = ClipboardService(pasteboard: pasteboard, sleep: { _ in throw CancellationError() })
        service.copy(SecretValue("secret"), clearAfter: 30)
        await service.pendingClear?.value
        #expect(pasteboard.contents == "secret")
    }

    @Test func clearIfStillOursOnLock() {
        let service = ClipboardService(pasteboard: pasteboard, sleep: { _ in try await Task.sleep(for: .seconds(60)) })
        service.copy(SecretValue("secret"), clearAfter: 30)
        service.clearIfStillOurs()
        #expect(pasteboard.contents == nil)

        service.copy(SecretValue("secret"), clearAfter: 30)
        pasteboard.simulateOtherCopy("mine")
        service.clearIfStillOurs()
        #expect(pasteboard.contents == "mine")
    }

    @Test func readsAndClearsForPasteFromClipboard() {
        let service = ClipboardService(pasteboard: pasteboard)
        pasteboard.simulateOtherCopy("pasted value")
        #expect(service.readString() == "pasted value")
        service.clearAll()
        #expect(pasteboard.contents == nil)
    }
}
