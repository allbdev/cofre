import Foundation
import Testing

@testable import CofreKit

struct LockPolicyTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func locksAfterTheIdleTimeout() {
        let policy = LockPolicy(idleTimeout: 300)
        #expect(!policy.shouldLock(lastActivity: start, now: start.addingTimeInterval(299)))
        #expect(policy.shouldLock(lastActivity: start, now: start.addingTimeInterval(300)))
    }

    @Test(arguments: [
        LockPolicy.Event.systemWillSleep, .screenLocked, .screensaverStarted, .userSwitchedOut, .appWillQuit,
    ])
    func everySystemEventLocks(_ event: LockPolicy.Event) {
        #expect(LockPolicy(idleTimeout: 300).shouldLock(on: event))
    }
}

@MainActor
struct PreferencesTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "cofre.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func defaultsWhenNothingIsStored() {
        let preferences = UserDefaultsPreferences(defaults: makeDefaults())
        #expect(preferences.clipboardClearDelay == 30)
        #expect(preferences.autoLockTimeout == 300)
        #expect(preferences.lastExportAt == nil)
        #expect(preferences.lastChangeAt == nil)
    }

    @Test func remembersValues() {
        let defaults = makeDefaults()
        let preferences = UserDefaultsPreferences(defaults: defaults)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        preferences.clipboardClearDelay = 60
        preferences.autoLockTimeout = 900
        preferences.lastExportAt = date
        preferences.lastChangeAt = date
        let reloaded = UserDefaultsPreferences(defaults: defaults)
        #expect(reloaded.clipboardClearDelay == 60)
        #expect(reloaded.autoLockTimeout == 900)
        #expect(reloaded.lastExportAt == date)
        #expect(reloaded.lastChangeAt == date)
    }

    @Test func ignoresNonsenseDurations() {
        let defaults = makeDefaults()
        defaults.set(-4, forKey: "clipboardClearDelay")
        #expect(UserDefaultsPreferences(defaults: defaults).clipboardClearDelay == 30)
    }
}
