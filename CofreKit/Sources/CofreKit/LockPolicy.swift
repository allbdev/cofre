import Foundation

/// When an unlocked session should lock again (`PLAN.md` D5).
public struct LockPolicy: Sendable, Equatable {
    public enum Event: Sendable, Equatable {
        case systemWillSleep
        case screenLocked
        case screensaverStarted
        case userSwitchedOut
        case appWillQuit
    }

    public var idleTimeout: TimeInterval

    public init(idleTimeout: TimeInterval) {
        self.idleTimeout = idleTimeout
    }

    public func shouldLock(lastActivity: Date, now: Date) -> Bool {
        now.timeIntervalSince(lastActivity) >= idleTimeout
    }

    /// Every system event in `Event` locks; kept as a function so the rule is tested and visible.
    public func shouldLock(on event: Event) -> Bool {
        switch event {
        case .systemWillSleep, .screenLocked, .screensaverStarted, .userSwitchedOut, .appWillQuit:
            true
        }
    }
}
