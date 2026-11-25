import CofreKit
import SwiftUI

/// The main window: search, the list of names, and every sheet and panel for managing them.
struct VaultWindow: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state
        @Bindable var model = state.model

        content
            .frame(minWidth: 420, minHeight: 360)
            .searchable(text: $model.query, placement: .toolbar, prompt: Text("Search"))
            .toolbar { toolbar }
            .safeAreaInset(edge: .top, spacing: 0) {
                if model.backupStatus.needsAttention, !model.isStoreUnavailable {
                    BackupBanner(status: model.backupStatus) { state.sheet = .export }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                CopyToast(receipt: model.lastCopy)
            }
            .sheet(item: $state.sheet, onDismiss: presentPendingExport) { sheet in
                sheetView(for: sheet)
                    .environment(state)
            }
            .confirmationDialog(
                deleteTitle,
                isPresented: isDeleteDialogPresented,
                titleVisibility: .visible,
                presenting: state.pendingDelete
            ) { summary in
                Button("Delete", role: .destructive) {
                    Task { await model.delete(summary.id) }
                }
            } message: { _ in
                Text("The value is removed from the Keychain. This can't be undone.")
            }
            .alert(
                Text("Something went wrong"),
                isPresented: isErrorAlertPresented,
                presenting: model.error
            ) { _ in
                Button("OK") { model.error = nil }
            } message: { error in
                Text(error.message)
            }
            .fileExporter(
                isPresented: $state.isExporterPresented,
                document: state.pendingExport,
                contentType: .cofreExport,
                defaultFilename: VaultModel.suggestedExportFileName
            ) { result in
                if case .success = result {
                    model.recordExport()
                }
                state.pendingExport = nil
            }
            .fileImporter(
                isPresented: $state.isImporterPresented,
                allowedContentTypes: [.cofreExport, .data]
            ) { result in
                guard case .success(let url) = result else { return }
                do {
                    let data = try ImportFileReader.read(url)
                    state.sheet = .importFile(data: data, fileName: url.lastPathComponent)
                } catch let error as VaultError {
                    model.error = error
                } catch {
                    model.error = .exportNotACofreFile
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        let model = state.model
        if !model.isLoaded {
            ProgressView()
        } else if model.isStoreUnavailable {
            KeychainUnavailableView()
        } else if model.namesAreLocked {
            LockedVaultView { Task { await model.unlock() } }
        } else if model.secrets.isEmpty {
            EmptyVaultView { state.sheet = .add }
        } else if model.results.isEmpty {
            ContentUnavailableView.search(text: model.query)
        } else {
            SecretList()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        let model = state.model
        #if DEBUG
            if state.usesMemoryStore {
                ToolbarItem(placement: .navigation) {
                    Text("In-memory store")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .help("Debug run with -CofreStore memory: secrets are forgotten when Cofre quits.")
                }
            }
        #endif
        ToolbarItem {
            if model.isUnlocked {
                Button {
                    Task { await model.lock() }
                } label: {
                    Label("Lock", systemImage: "lock.open")
                }
                .help("Unlocked. Click to lock now.")
            } else {
                Button {
                    Task { await model.unlock() }
                } label: {
                    Label("Unlock", systemImage: "lock")
                }
                .help("Locked. Unlock with Touch ID or your password to see and copy your secrets.")
                .disabled(model.isStoreUnavailable)
            }
        }
        ToolbarItem {
            Button {
                state.sheet = .add
            } label: {
                Label("New Secret", systemImage: "plus")
            }
            .help("New Secret (⌘N)")
            .disabled(model.isStoreUnavailable)
        }
    }

    @ViewBuilder
    private func sheetView(for sheet: AppState.Sheet) -> some View {
        switch sheet {
        case .add:
            SecretEditorSheet(mode: .add)
        case .rename(let summary):
            SecretEditorSheet(mode: .rename(summary))
        case .replace(let summary):
            SecretEditorSheet(mode: .replace(summary))
        case .export:
            ExportSheet()
        case .importFile(let data, let fileName):
            ImportSheet(data: data, fileName: fileName)
        }
    }

    private var deleteTitle: Text {
        if let name = state.pendingDelete?.name {
            Text("Delete “\(name)”?")
        } else {
            Text("Delete")
        }
    }

    private var isDeleteDialogPresented: Binding<Bool> {
        Binding(
            get: { state.pendingDelete != nil },
            set: { if !$0 { state.pendingDelete = nil } }
        )
    }

    /// Sheets show their own errors; the window alert is for everything else.
    private var isErrorAlertPresented: Binding<Bool> {
        Binding(
            get: { state.model.error != nil && state.sheet == nil },
            set: { if !$0 { state.model.error = nil } }
        )
    }

    /// The export sheet encrypts, closes, and then the save panel opens.
    private func presentPendingExport() {
        if state.pendingExport != nil {
            state.isExporterPresented = true
        }
    }
}

/// The list of names, with copy on double-click / Return and a context menu.
struct SecretList: View {
    @Environment(AppState.self) private var state
    @State private var selection: UUID?

    var body: some View {
        let model = state.model
        List(model.results, selection: $selection) { summary in
            SecretRow(summary: summary) {
                Task { await model.copy(summary.id) }
            }
            .tag(summary.id)
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            if let id = ids.first, let summary = model.secrets.first(where: { $0.id == id }) {
                Button("Copy Value") { Task { await model.copy(id) } }
                Divider()
                Button("Rename…") { state.sheet = .rename(summary) }
                Button("Replace Value…") { state.sheet = .replace(summary) }
                Divider()
                Button("Delete…", role: .destructive) { state.pendingDelete = summary }
            }
        } primaryAction: { ids in
            if let id = ids.first {
                Task { await model.copy(id) }
            }
        }
        .onDeleteCommand {
            if let id = selection, let summary = model.secrets.first(where: { $0.id == id }) {
                state.pendingDelete = summary
            }
        }
    }
}

struct SecretRow: View {
    let summary: SecretSummary
    let copy: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "key.horizontal")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Updated \(summary.updatedAt, format: .relative(presentation: .named))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: copy) {
                Label("Copy Value", systemImage: "doc.on.doc")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .help("Copy Value")
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: Text("Copy Value"), copy)
    }
}
