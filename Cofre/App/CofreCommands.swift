import CofreKit
import SwiftUI

/// The menu bar commands: File → New Secret / Import / Export, and a Secrets menu for locking.
struct CofreCommands: Commands {
    let state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Secret…") {
                showMainWindow()
                state.sheet = .add
            }
            .keyboardShortcut("n")
        }

        CommandGroup(after: .newItem) {
            Divider()
            Button("Import…") {
                showMainWindow()
                state.isImporterPresented = true
            }
            .keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Export…") {
                showMainWindow()
                state.sheet = .export
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(state.model.secrets.isEmpty)
        }

        CommandMenu("Secrets") {
            if state.model.isUnlocked {
                Button("Lock") {
                    Task { await state.model.lock() }
                }
                .keyboardShortcut("l", modifiers: [.command, .control])
            } else {
                Button("Unlock") {
                    Task { await state.model.unlock() }
                }
                .keyboardShortcut("l", modifiers: [.command, .control])
            }
        }
    }

    private func showMainWindow() {
        openWindow(id: WindowID.main)
        NSApp.activate()
    }
}
