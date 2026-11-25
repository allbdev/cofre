import CofreKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// `.cofre` export files, declared in `Config/Info.plist` as `<bundle id>.export`.
    static let cofreExport = UTType(
        exportedAs: (Bundle.main.bundleIdentifier ?? "cofre") + ".export",
        conformingTo: .data
    )
}

/// The encrypted bytes handed to the save panel. Already encrypted by `ExportCodec`.
struct ExportFile: FileDocument {
    static let readableContentTypes: [UTType] = [.cofreExport]

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum ImportFileReader {
    /// Reads a file the user picked in the open panel (sandbox: security-scoped access).
    static func read(_ url: URL) throws(VaultError) -> Data {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= ExportCodec.maximumFileSize else { throw .exportTooLarge }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw .exportNotACofreFile
        }
    }
}
