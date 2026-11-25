import CofreKit
import SwiftUI

/// First launch: nothing stored yet.
struct EmptyVaultView: View {
    let add: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No secrets yet", systemImage: "key.horizontal")
        } description: {
            Text("Add an API key, token or password. Its value is never shown, only copied.")
        } actions: {
            Button("New Secret…", action: add)
                .buttonStyle(.borderedProminent)
        }
    }
}

/// The Keychain refused this copy of the app (unsigned build).
struct KeychainUnavailableView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Keychain not available", systemImage: "lock.trianglebadge.exclamationmark")
        } description: {
            Text(VaultError.keychainUnavailable.message)
        } actions: {
            #if DEBUG
                Text("For a quick look, run the Debug build with -CofreStore memory.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            #endif
        }
    }
}

/// "Copied “Stripe key” · clears in 24 s", counting down until the clipboard is cleared.
struct CopyToast: View {
    let receipt: CopyReceipt?

    var body: some View {
        if let receipt {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let remaining = Int(receipt.clearsAt.timeIntervalSince(context.date).rounded(.up))
                if remaining > 0 {
                    Label {
                        Text("Copied “\(receipt.name)” · clears in \(remaining) s")
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .font(.callout)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityAddTraits(.updatesFrequently)
                }
            }
        }
    }
}

/// Nudge to export when there's no backup, or it's older than the latest change.
struct BackupBanner: View {
    let status: BackupStatus
    let export: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "externaldrive.badge.exclamationmark")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Group {
                if case .changedSinceExport = status {
                    Text("Secrets changed since your last backup.")
                } else {
                    Text("No backup yet. If this Mac is lost, your secrets go with it.")
                }
            }
            .font(.callout)
            Spacer()
            Button("Export…", action: export)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.12))
    }
}
