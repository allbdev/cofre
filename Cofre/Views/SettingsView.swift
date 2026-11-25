import CofreKit
import SwiftUI

/// Clipboard clear delay, auto-lock timeout, and the quick access shortcut.
/// Keys match `UserDefaultsPreferences`, which `VaultModel` reads.
struct SettingsView: View {
    @AppStorage("clipboardClearDelay") private var clipboardClearDelay = PreferenceDefaults.clipboardClearDelay
    @AppStorage("autoLockTimeout") private var autoLockTimeout = PreferenceDefaults.autoLockTimeout

    var body: some View {
        Form {
            Picker("Clear the clipboard after", selection: $clipboardClearDelay) {
                ForEach(PreferenceDefaults.clipboardClearDelayChoices, id: \.self) { seconds in
                    Text(Self.format(seconds)).tag(seconds)
                }
            }
            Picker("Lock after inactivity", selection: $autoLockTimeout) {
                ForEach(PreferenceDefaults.autoLockTimeoutChoices, id: \.self) { seconds in
                    Text(Self.format(seconds)).tag(seconds)
                }
            }
            Text("Cofre also locks when your Mac sleeps, the screen locks or you quit.")
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent("Quick access") {
                Text(GlobalHotKey.Shortcut.defaultQuickAccess.display)
                    .monospaced()
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// "30 seconds", "5 minutes", "1 hour" in the system language.
    static func format(_ seconds: TimeInterval) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }
}
