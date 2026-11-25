import AppKit
import CofreKit
import SwiftUI

/// The floating search panel the global hotkey opens (`PLAN.md` D7). Type, ↑/↓, Enter copies
/// and closes, Esc closes. When it closes and no Cofre window is open, focus goes back to the
/// app you were in, so ⌘V works right away.
@MainActor
final class QuickPanelController {
    private let state: AppState
    private var panel: QuickPanel?
    /// True while a copy waits for Touch ID: the system prompt takes focus, and the panel must
    /// not close because of that.
    private var isCopying = false

    init(state: AppState) {
        self.state = state
    }

    func toggle() {
        if panel?.isVisible == true {
            close()
        } else {
            show()
        }
    }

    func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        let content = QuickSearchView(
            onCopyStarted: { [weak self] in self?.isCopying = true },
            onDone: { [weak self] in
                self?.isCopying = false
                self?.close()
            }
        )
        .environment(state)
        panel.contentView = NSHostingView(rootView: content)
        position(panel)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        let otherWindowsVisible = NSApp.windows.contains { $0 !== panel && $0.isVisible && $0.canBecomeMain }
        if !otherWindowsVisible {
            NSApp.hide(nil)
        }
    }

    private func makePanel() -> QuickPanel {
        let panel = QuickPanel(
            contentRect: NSRect(x: 0, y: 0, width: QuickSearchView.width, height: QuickSearchView.height),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.onResignKey = { [weak self] in
            guard let self, !self.isCopying else { return }
            self.close()
        }
        panel.onCancel = { [weak self] in self?.close() }
        return panel
    }

    /// Centered horizontally, in the upper third of the screen with the mouse (like Spotlight).
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let frame = screen?.visibleFrame else {
            panel.center()
            return
        }
        let size = panel.frame.size
        let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.minY + frame.height * 0.66 - size.height / 2)
        panel.setFrameOrigin(origin)
    }
}

final class QuickPanel: NSPanel {
    var onResignKey: (() -> Void)?
    var onCancel: (() -> Void)?

    override var canBecomeKey: Bool { true }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}
