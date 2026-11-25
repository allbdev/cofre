import AppKit
import CofreKit

/// Feeds system events and an idle check to `VaultModel` so an unlocked session locks again
/// (`PLAN.md` D5): sleep, screen lock, screensaver, fast user switching, and inactivity.
@MainActor
final class LockTriggers {
    private let model: VaultModel
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var idleTimer: Timer?

    init(model: VaultModel) {
        self.model = model
    }

    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification, .systemWillSleep)
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification, .userSwitchedOut)

        let distributed = DistributedNotificationCenter.default()
        observe(distributed, Notification.Name("com.apple.screenIsLocked"), .screenLocked)
        observe(distributed, Notification.Name("com.apple.screensaver.didstart"), .screensaverStarted)

        idleTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let model = self?.model else { return }
                Task { await model.lockIfIdle() }
            }
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ event: LockPolicy.Event) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let model = self?.model else { return }
                Task { await model.handle(event) }
            }
        }
        observers.append((center, token))
    }
}
