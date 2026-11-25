import AppKit
import CofreKit
import SwiftUI

@main
struct CofreApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Cofre", id: WindowID.main) {
            VaultWindow()
                .environment(appDelegate.state)
        }
        .defaultSize(width: 560, height: 600)
        .commands {
            CofreCommands(state: appDelegate.state)
        }

        MenuBarExtra("Cofre", systemImage: "key.fill") {
            MenuBarContent()
                .environment(appDelegate.state)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appDelegate.state)
        }
    }
}

enum WindowID {
    static let main = "main"
}

/// Owns what lives outside SwiftUI scenes: the global hotkey, the quick panel and the lock triggers.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = AppState.live()
    private lazy var quickPanel = QuickPanelController(state: state)
    private lazy var lockTriggers = LockTriggers(model: state.model)
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        hotKey = GlobalHotKey(shortcut: .defaultQuickAccess) { [weak self] in
            self?.quickPanel.toggle()
        }
        lockTriggers.start()
        Task {
            await state.model.reload()
            #if DEBUG
                await DebugSnapshots.run(state: state, quickPanel: quickPanel)
            #endif
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        state.model.prepareForQuit()
    }

    /// The menu bar item keeps Cofre useful with no window open.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
