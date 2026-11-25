import Foundation

/// The system clipboard, as far as Cofre needs it. The app adapts `NSPasteboard` to this.
@MainActor
public protocol Pasteboard: AnyObject {
    /// Increases every time anyone writes to the clipboard.
    var changeCount: Int { get }
    /// Writes the value marked as concealed and transient; returns the new change count.
    func writeConcealed(_ value: SecretValue) -> Int
    /// The current clipboard text, for "Paste from clipboard".
    func readString() -> String?
    func clear()
}

/// Copies secrets and clears them later. Sleeping is injected so tests don't wait.
@MainActor
public final class ClipboardService {
    public typealias Sleeper = @Sendable (TimeInterval) async throws -> Void

    private let pasteboard: any Pasteboard
    private let now: () -> Date
    private let sleep: Sleeper
    private(set) var guardState = ClipboardGuard()
    private(set) var pendingClear: Task<Void, Never>?

    public init(
        pasteboard: any Pasteboard,
        now: @escaping () -> Date = { Date() },
        sleep: @escaping Sleeper = { try await Task.sleep(for: .seconds($0)) }
    ) {
        self.pasteboard = pasteboard
        self.now = now
        self.sleep = sleep
    }

    public func copy(_ value: SecretValue, clearAfter delay: TimeInterval) {
        let changeCount = pasteboard.writeConcealed(value)
        guardState.didCopy(changeCount: changeCount, at: now(), delay: delay)
        pendingClear?.cancel()
        let sleep = self.sleep
        pendingClear = Task { [weak self] in
            do {
                try await sleep(delay)
            } catch {
                return
            }
            self?.clearIfDue()
        }
    }

    /// Clears now if the clipboard still holds our value (used on lock and quit).
    public func clearIfStillOurs() {
        if guardState.isStillOurs(currentChangeCount: pasteboard.changeCount) {
            pasteboard.clear()
        }
        guardState.reset()
        pendingClear?.cancel()
        pendingClear = nil
    }

    public func readString() -> String? {
        pasteboard.readString()
    }

    /// Clears the clipboard right away, whatever it holds (after "Paste from clipboard").
    public func clearAll() {
        pasteboard.clear()
        guardState.reset()
    }

    /// Runs when the delay has passed. The sleep already measured the time, so only ownership
    /// is checked here (re-checking the wall clock could come out a few milliseconds short).
    func clearIfDue() {
        if guardState.isStillOurs(currentChangeCount: pasteboard.changeCount) {
            pasteboard.clear()
        }
        guardState.reset()
    }
}
