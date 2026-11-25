import AppKit
import CofreKit
import SwiftUI

/// Search + list + Enter to copy. Used by the hotkey panel and the menu bar item.
struct QuickSearchView: View {
    static let width: CGFloat = 460
    static let height: CGFloat = 340

    /// The hotkey panel asks for Touch ID as soon as it opens; the menu bar window doesn't,
    /// because it closes when the system prompt takes focus.
    var unlocksOnAppear = false
    /// True while a system authentication prompt is up, so the panel doesn't take the focus it
    /// loses for a click elsewhere.
    var onAuthenticating: (Bool) -> Void = { _ in }
    var onDone: () -> Void

    @Environment(AppState.self) private var state
    @State private var query = ""
    @State private var selectedIndex = 0
    @FocusState private var searchFocused: Bool

    private var results: [SecretSummary] {
        SearchRanker.rank(state.model.secrets, query: query, name: \.name)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("Search secrets", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searchFocused)
                    .onSubmit(copySelected)
                    .onKeyPress(.downArrow) {
                        move(1)
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        move(-1)
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        onDone()
                        return .handled
                    }
            }
            .padding(14)

            Divider()

            resultList

            Divider()

            footer
        }
        // At least this tall, and filling whatever the hotkey panel has (its hidden title bar
        // adds height that would otherwise sit empty under the footer).
        .frame(width: Self.width)
        .frame(minHeight: Self.height, maxHeight: .infinity)
        .background(.regularMaterial)
        .onAppear {
            searchFocused = true
            Task { await loadNames() }
        }
        .onChange(of: query) { selectedIndex = 0 }
        // Touch ID takes the key window away; SwiftUI drops a focus request made while the panel
        // isn't key, so every keystroke afterwards only beeps. Focus again whenever it's key.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            guard note.object is QuickPanel else { return }
            Task { @MainActor in searchFocused = true }
        }
    }

    @ViewBuilder
    private var resultList: some View {
        if state.model.isStoreUnavailable {
            ContentUnavailableView("Keychain not available", systemImage: "lock.trianglebadge.exclamationmark")
                .frame(maxHeight: .infinity)
        } else if state.model.namesAreLocked {
            ContentUnavailableView {
                Label("Cofre is locked", systemImage: "lock")
            } description: {
                Text("Unlock to see your secrets.")
            } actions: {
                Button("Unlock") { Task { await unlock() } }
            }
            .frame(maxHeight: .infinity)
        } else if state.model.secrets.isEmpty {
            ContentUnavailableView("No secrets yet", systemImage: "key.horizontal")
                .frame(maxHeight: .infinity)
        } else if results.isEmpty {
            ContentUnavailableView.search(text: query)
                .frame(maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, summary in
                            QuickResultRow(name: summary.name, isSelected: index == selectedIndex)
                                .id(summary.id)
                                .onTapGesture {
                                    selectedIndex = index
                                    copySelected()
                                }
                        }
                    }
                    .padding(6)
                }
                .onChange(of: selectedIndex) {
                    if results.indices.contains(selectedIndex) {
                        proxy.scrollTo(results[selectedIndex].id)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if state.model.isUnlocked {
                Label("Unlocked", systemImage: "lock.open")
            } else {
                Label("Locked", systemImage: "lock")
            }
            Spacer()
            Text("↩ copy · ↑↓ choose · esc close")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), results.count - 1)
    }

    /// Names need an unlock (`PLAN.md` D5). From the hotkey, ask right away: the user is about
    /// to copy, which needs it anyway, so it's the same single prompt, just earlier.
    private func loadNames() async {
        await state.model.reload()
        if unlocksOnAppear, state.model.namesAreLocked {
            await unlock()
        }
    }

    private func unlock() async {
        onAuthenticating(true)
        let unlocked = await state.model.unlock()
        onAuthenticating(false)
        if unlocked {
            searchFocused = true
        } else if unlocksOnAppear {
            // Cancelled from the hotkey: the user changed their mind.
            onDone()
        }
    }

    private func copySelected() {
        guard results.indices.contains(selectedIndex) else { return }
        let id = results[selectedIndex].id
        onAuthenticating(true)
        Task {
            let copied = await state.model.copy(id)
            if copied {
                // Closing hands focus back to the app you were in; don't grab it first.
                onDone()
            } else {
                // Cancelled or failed: stay open so the user can try again.
                onAuthenticating(false)
                searchFocused = true
            }
        }
    }
}

struct QuickResultRow: View {
    let name: String
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "key.horizontal")
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .accessibilityHidden(true)
            Text(name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            if isSelected {
                Image(systemName: "return")
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

/// The menu bar item's window: the same quick search, plus app actions.
struct MenuBarContent: View {
    @Environment(AppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(spacing: 0) {
            QuickSearchView(onDone: closeMenu)
            Divider()
            HStack {
                Button("Open Cofre") {
                    closeMenu()
                    openWindow(id: WindowID.main)
                    NSApp.activate()
                }
                Button("Settings…") {
                    closeMenu()
                    openSettings()
                    NSApp.activate()
                }
                Spacer()
                if state.model.isUnlocked {
                    Button("Lock") {
                        Task { await state.model.lock() }
                    }
                }
                Button("Quit") { NSApp.terminate(nil) }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
    }

    private func closeMenu() {
        NSApp.keyWindow?.close()
    }
}
