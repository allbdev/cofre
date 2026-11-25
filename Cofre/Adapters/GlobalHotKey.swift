import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut through Carbon's `RegisterEventHotKey`, which works in the
/// sandbox and needs no Accessibility permission.
@MainActor
final class GlobalHotKey {
    struct Shortcut: Equatable {
        var keyCode: UInt32
        var carbonModifiers: UInt32
        /// What the Settings window shows, e.g. "⌃⌥K".
        var display: String

        /// ⌃⌥K ("K" for key). Not used by macOS itself.
        static let defaultQuickAccess = Shortcut(
            keyCode: UInt32(kVK_ANSI_K),
            carbonModifiers: UInt32(controlKey | optionKey),
            display: "⌃⌥K"
        )
    }

    private static let signature: OSType = 0x436F_6652  // "CofR"
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: @MainActor () -> Void

    /// Registers right away; `isRegistered` is false if another app already owns the shortcut.
    init(shortcut: Shortcut, action: @escaping @MainActor () -> Void) {
        self.action = action
        register(shortcut)
    }

    var isRegistered: Bool { hotKeyRef != nil }

    private func register(_ shortcut: Shortcut) {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                MainActor.assumeIsolated { hotKey.action() }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: 1)
        let status = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            hotKeyRef = nil
        }
    }
}
