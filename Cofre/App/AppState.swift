import CofreKeychain
import CofreKit
import Foundation
import Observation

/// App-wide state: the vault model plus which sheet or panel is up. Shared by the main window,
/// the menu bar, the quick panel and the menu commands.
@MainActor
@Observable
final class AppState {
    enum Sheet: Identifiable {
        case add
        case rename(SecretSummary)
        case replace(SecretSummary)
        case export
        case importFile(data: Data, fileName: String)

        var id: String {
            switch self {
            case .add: "add"
            case .rename(let summary): "rename-\(summary.id)"
            case .replace(let summary): "replace-\(summary.id)"
            case .export: "export"
            case .importFile(_, let fileName): "import-\(fileName)"
            }
        }
    }

    let model: VaultModel
    /// Debug runs with `-CofreStore memory` keep secrets only while the app runs.
    let usesMemoryStore: Bool

    var sheet: Sheet?
    var pendingDelete: SecretSummary?
    var isImporterPresented = false
    var isExporterPresented = false
    /// Encrypted bytes waiting for the save panel (set by the export sheet).
    var pendingExport: ExportFile?

    init(model: VaultModel, usesMemoryStore: Bool) {
        self.model = model
        self.usesMemoryStore = usesMemoryStore
    }

    /// The real app: Keychain store, system clipboard, `UserDefaults` settings.
    static func live() -> AppState {
        let usesMemoryStore = Self.memoryStoreRequested
        let store: any SecretStore = usesMemoryStore ? InMemorySecretStore() : KeychainSecretStore()
        let model = VaultModel(
            store: store,
            clipboard: ClipboardService(pasteboard: SystemPasteboard()),
            preferences: UserDefaultsPreferences()
        )
        return AppState(model: model, usesMemoryStore: usesMemoryStore)
    }

    /// `-CofreStore memory` on the command line (or in the scheme), debug builds only.
    private static var memoryStoreRequested: Bool {
        #if DEBUG
            UserDefaults.standard.string(forKey: "CofreStore") == "memory"
        #else
            false
        #endif
    }
}
