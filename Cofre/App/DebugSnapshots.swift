#if DEBUG
    import AppKit
    import CofreKit

    /// Debug-only helpers for screenshots, with the in-memory store:
    ///
    ///     Cofre.app/Contents/MacOS/Cofre -CofreStore memory -CofreDemoData YES \
    ///         -CofreSnapshotDir /path/to/dir [-AppleLanguages '(pt-BR)']
    ///
    /// `-CofreDemoData` fills the vault with made-up secrets; `-CofreSnapshotDir` draws the main
    /// window, the add sheet and the quick panel to PNGs, then quits. Windows draw themselves,
    /// so no Screen Recording permission is needed (used to check layouts and translations).
    @MainActor
    enum DebugSnapshots {
        static let demoNames = [
            "Stripe secret key (prod)",
            "Stripe secret key (test)",
            "GitHub token — CI",
            "AWS access key",
            "Postgres URL (staging)",
            "OpenAI API key",
            "Sentry DSN",
            "Wi-Fi do escritório",
        ]

        static func run(state: AppState, quickPanel: QuickPanelController) async {
            let defaults = UserDefaults.standard
            guard state.usesMemoryStore else { return }
            if defaults.bool(forKey: "CofreDemoData") {
                for name in demoNames {
                    await state.model.add(name: name, value: SecretValue("demo-\(UUID().uuidString)"))
                }
            }
            guard let path = defaults.string(forKey: "CofreSnapshotDir") else { return }
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            try? await Task.sleep(for: .seconds(1.5))
            if let main = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) {
                capture(main, to: directory.appending(path: "01-main.png"))

                if let first = state.model.secrets.first {
                    await state.model.copy(first.id)
                    try? await Task.sleep(for: .seconds(0.6))
                    capture(main, to: directory.appending(path: "02-copied.png"))
                }

                state.sheet = .add
                try? await Task.sleep(for: .seconds(1))
                if let sheet = main.attachedSheet {
                    capture(sheet, to: directory.appending(path: "03-add-sheet.png"))
                }
                state.sheet = nil
                try? await Task.sleep(for: .seconds(0.6))
            }

            quickPanel.show()
            try? await Task.sleep(for: .seconds(1))
            if let panel = NSApp.windows.first(where: { $0 is QuickPanel && $0.isVisible }) {
                capture(panel, to: directory.appending(path: "04-quick-panel.png"))
            }
            quickPanel.close()

            await state.model.lock()
            try? await Task.sleep(for: .seconds(0.6))
            if let main = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) {
                capture(main, to: directory.appending(path: "05-locked.png"))
            }
            NSApp.terminate(nil)
        }

        /// Draws the window into a PNG. Limitation: the main window's `List` rows don't draw this
        /// way (they're layer-hosted), so for README screenshots of the list use ⇧⌘5 instead.
        private static func capture(_ window: NSWindow, to url: URL) {
            guard let view = window.contentView?.superview ?? window.contentView,
                let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)
            else { return }
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: url)
        }
    }
#endif
