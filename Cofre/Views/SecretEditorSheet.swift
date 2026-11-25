import CofreKit
import SwiftUI

/// Add a secret, rename one, or replace its value. The value is typed in a password field or
/// pasted from the clipboard; either way it's never displayed (`PLAN.md` D1).
struct SecretEditorSheet: View {
    enum Mode {
        case add
        case rename(SecretSummary)
        case replace(SecretSummary)
    }

    let mode: Mode

    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var value = ValueInput.Entry()
    @State private var isSaving = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        let model = state.model
        VStack(alignment: .leading, spacing: 16) {
            title
                .font(.headline)

            Form {
                if showsName {
                    TextField("Name", text: $name, prompt: Text("e.g. Stripe secret key (prod)"))
                        .focused($nameFocused)
                }
                if showsValue {
                    ValueInput(entry: $value)
                }
            }
            .formStyle(.columns)

            if let error = model.error {
                Label {
                    Text(error.message)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.red)
                .font(.callout)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(action: save) {
                    saveLabel
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave || isSaving)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            model.error = nil
            if case .rename(let summary) = mode { name = summary.name }
            nameFocused = showsName
        }
        .onChange(of: name) { model.error = nil }
        .onChange(of: value) { model.error = nil }
    }

    @ViewBuilder
    private var title: some View {
        switch mode {
        case .add: Text("New Secret")
        case .rename(let summary): Text("Rename “\(summary.name)”")
        case .replace(let summary): Text("Replace the value of “\(summary.name)”")
        }
    }

    @ViewBuilder
    private var saveLabel: some View {
        switch mode {
        case .add: Text("Add")
        case .rename: Text("Rename")
        case .replace: Text("Replace")
        }
    }

    private var showsName: Bool {
        if case .replace = mode { false } else { true }
    }

    private var showsValue: Bool {
        if case .rename = mode { false } else { true }
    }

    private var canSave: Bool {
        let hasName = !SecretName.trimmed(name).isEmpty
        switch mode {
        case .add: return hasName && value.secret != nil
        case .rename: return hasName
        case .replace: return value.secret != nil
        }
    }

    private func save() {
        let model = state.model
        isSaving = true
        Task {
            defer { isSaving = false }
            let saved: Bool
            switch mode {
            case .add:
                guard let secret = value.secret else { return }
                saved = await model.add(name: name, value: secret)
            case .rename(let summary):
                saved = await model.rename(summary.id, to: name)
            case .replace(let summary):
                guard let secret = value.secret else { return }
                saved = await model.replaceValue(summary.id, with: secret)
            }
            guard saved else { return }
            if value.isPasted, value.clearClipboardAfterSaving {
                model.clearClipboard()
            }
            dismiss()
        }
    }
}

/// The value field: a password field, or "Paste from Clipboard" for multi-line values (PEM keys).
struct ValueInput: View {
    struct Entry: Equatable {
        var typed = ""
        var pasted: SecretValue?
        var clearClipboardAfterSaving = true

        var isPasted: Bool { pasted != nil }

        var secret: SecretValue? {
            if let pasted { return pasted }
            return typed.isEmpty ? nil : SecretValue(typed)
        }
    }

    @Binding var entry: Entry
    @Environment(AppState.self) private var state
    @State private var clipboardWasEmpty = false

    var body: some View {
        LabeledContent("Value") {
            VStack(alignment: .leading, spacing: 8) {
                if let pasted = entry.pasted {
                    HStack {
                        Label {
                            Text("Pasted · length \(pasted.displayLength)")
                        } icon: {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                        Spacer()
                        Button("Clear") { entry.pasted = nil }
                            .controlSize(.small)
                    }
                    Toggle("Clear the clipboard after saving", isOn: $entry.clearClipboardAfterSaving)
                        .controlSize(.small)
                } else {
                    SecureField("Value", text: $entry.typed, prompt: Text("Type or paste the value"))
                        .labelsHidden()
                    HStack {
                        Button("Paste from Clipboard") { pasteFromClipboard() }
                            .controlSize(.small)
                        if clipboardWasEmpty {
                            Text("The clipboard has no text.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func pasteFromClipboard() {
        if let value = state.model.valueFromClipboard() {
            entry.pasted = value
            entry.typed = ""
            clipboardWasEmpty = false
        } else {
            clipboardWasEmpty = true
        }
    }
}
