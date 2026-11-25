import Foundation

/// Remembers the last copy and decides when to clear it: after the delay, and only if nobody
/// has written to the clipboard since (`PLAN.md` D6).
public struct ClipboardGuard: Sendable, Equatable {
    public private(set) var ownedChangeCount: Int?
    public private(set) var clearAt: Date?

    public init() {}

    public mutating func didCopy(changeCount: Int, at date: Date, delay: TimeInterval) {
        ownedChangeCount = changeCount
        clearAt = date.addingTimeInterval(delay)
    }

    public func isStillOurs(currentChangeCount: Int) -> Bool {
        ownedChangeCount == currentChangeCount
    }

    public func shouldClear(currentChangeCount: Int, now: Date) -> Bool {
        guard let clearAt, isStillOurs(currentChangeCount: currentChangeCount) else { return false }
        return now >= clearAt
    }

    public mutating func reset() {
        ownedChangeCount = nil
        clearAt = nil
    }
}
