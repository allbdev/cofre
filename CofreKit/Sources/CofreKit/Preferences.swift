import Foundation

/// Settings and small facts the app remembers between launches. Never holds secrets.
@MainActor
public protocol Preferences: AnyObject {
    var clipboardClearDelay: TimeInterval { get set }
    var autoLockTimeout: TimeInterval { get set }
    var lastExportAt: Date? { get set }
    var lastChangeAt: Date? { get set }
}

public enum PreferenceDefaults {
    public static let clipboardClearDelay: TimeInterval = 30
    public static let autoLockTimeout: TimeInterval = 5 * 60
    public static let clipboardClearDelayChoices: [TimeInterval] = [10, 30, 60, 120]
    public static let autoLockTimeoutChoices: [TimeInterval] = [60, 5 * 60, 15 * 60, 60 * 60]
}

@MainActor
public final class UserDefaultsPreferences: Preferences {
    private enum Key {
        static let clipboardClearDelay = "clipboardClearDelay"
        static let autoLockTimeout = "autoLockTimeout"
        static let lastExportAt = "lastExportAt"
        static let lastChangeAt = "lastChangeAt"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var clipboardClearDelay: TimeInterval {
        get { positive(Key.clipboardClearDelay) ?? PreferenceDefaults.clipboardClearDelay }
        set { defaults.set(newValue, forKey: Key.clipboardClearDelay) }
    }

    public var autoLockTimeout: TimeInterval {
        get { positive(Key.autoLockTimeout) ?? PreferenceDefaults.autoLockTimeout }
        set { defaults.set(newValue, forKey: Key.autoLockTimeout) }
    }

    public var lastExportAt: Date? {
        get { defaults.object(forKey: Key.lastExportAt) as? Date }
        set { defaults.set(newValue, forKey: Key.lastExportAt) }
    }

    public var lastChangeAt: Date? {
        get { defaults.object(forKey: Key.lastChangeAt) as? Date }
        set { defaults.set(newValue, forKey: Key.lastChangeAt) }
    }

    private func positive(_ key: String) -> TimeInterval? {
        let value = defaults.double(forKey: key)
        return value > 0 ? value : nil
    }
}

@MainActor
public final class InMemoryPreferences: Preferences {
    public var clipboardClearDelay = PreferenceDefaults.clipboardClearDelay
    public var autoLockTimeout = PreferenceDefaults.autoLockTimeout
    public var lastExportAt: Date?
    public var lastChangeAt: Date?

    public init() {}
}
