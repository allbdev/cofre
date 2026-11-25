import CofreKit
import SwiftUI

/// Asks for the export passphrase twice, encrypts every secret, then hands the bytes to the
/// window's save panel (`PLAN.md` D8).
struct ExportSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var passphrase = ""
    @State private var confirmation = ""
    @State private var isWorking = false

    var body: some View {
        let model = state.model
        VStack(alignment: .leading, spacing: 16) {
            Text("Export a Backup")
                .font(.headline)
            Text(
                "Every secret is encrypted into one file with a passphrase you choose. Keep the file anywhere; without the passphrase it's useless, and nobody can recover a forgotten passphrase."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Form {
                SecureField("Passphrase", text: $passphrase)
                SecureField("Confirm", text: $confirmation)
            }
            .formStyle(.columns)

            Text("At least \(ExportCodec.minimumPassphraseLength) characters. A few unrelated words work well.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ErrorLine(error: model.error)

            HStack {
                if isWorking {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Export…", action: export)
                    .keyboardShortcut(.defaultAction)
                    .disabled(passphrase.isEmpty || confirmation.isEmpty || isWorking)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear { model.error = nil }
        .onChange(of: passphrase) { model.error = nil }
        .onChange(of: confirmation) { model.error = nil }
    }

    private func export() {
        isWorking = true
        Task {
            defer { isWorking = false }
            guard let data = await state.model.makeExport(passphrase: passphrase, confirmation: confirmation)
            else { return }
            state.pendingExport = ExportFile(data: data)
            dismiss()
        }
    }
}

/// Decrypts a picked `.cofre` file, asks what to do with clashing names, imports, reports.
struct ImportSheet: View {
    let data: Data
    let fileName: String

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var passphrase = ""
    @State private var preview: ImportPreview?
    @State private var strategy = ImportConflictStrategy.skip
    @State private var summary: ImportSummary?
    @State private var isWorking = false

    var body: some View {
        let model = state.model
        VStack(alignment: .leading, spacing: 16) {
            Text("Import “\(fileName)”")
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)

            if let summary {
                Text("Added: \(summary.added) · Replaced: \(summary.replaced) · Skipped: \(summary.skipped)")
            } else if let preview {
                Text("Secrets in this backup: \(preview.payload.items.count)")
                if preview.conflictCount > 0 {
                    Text("With a name you already use: \(preview.conflictCount)")
                        .foregroundStyle(.secondary)
                    Picker("For those:", selection: $strategy) {
                        Text("Keep mine (skip)").tag(ImportConflictStrategy.skip)
                        Text("Use the backup's value").tag(ImportConflictStrategy.replace)
                        Text("Keep both").tag(ImportConflictStrategy.keepBoth)
                    }
                    .pickerStyle(.radioGroup)
                }
            } else {
                Form {
                    SecureField("Passphrase", text: $passphrase)
                }
                .formStyle(.columns)
            }

            ErrorLine(error: model.error)

            HStack {
                if isWorking {
                    ProgressView().controlSize(.small)
                }
                Spacer()
                if summary != nil {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button("Cancel", role: .cancel) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    if preview != nil {
                        Button("Import", action: apply)
                            .keyboardShortcut(.defaultAction)
                            .disabled(isWorking)
                    } else {
                        Button("Decrypt", action: decrypt)
                            .keyboardShortcut(.defaultAction)
                            .disabled(passphrase.isEmpty || isWorking)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear { model.error = nil }
        .onChange(of: passphrase) { model.error = nil }
    }

    private func decrypt() {
        isWorking = true
        Task {
            defer { isWorking = false }
            preview = await state.model.prepareImport(data: data, passphrase: passphrase)
            if preview != nil { passphrase = "" }
        }
    }

    private func apply() {
        guard let preview else { return }
        isWorking = true
        Task {
            defer { isWorking = false }
            summary = await state.model.applyImport(preview, strategy: strategy)
        }
    }
}

/// A red line with the model's last error, inside sheets.
struct ErrorLine: View {
    let error: VaultError?

    var body: some View {
        if let error {
            Label {
                Text(error.message)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .foregroundStyle(.red)
            .font(.callout)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
