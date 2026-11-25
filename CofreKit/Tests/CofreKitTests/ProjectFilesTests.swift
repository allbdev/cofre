import Foundation
import Testing

/// Checks on files outside the package: the app's String Catalog, entitlements and sources.
/// They live here so `swift test` enforces the rules in CLAUDE.md without building the app.
enum Repo {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // CofreKitTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // CofreKit
        .deletingLastPathComponent()  // repo root

    static func swiftFiles(in relativePath: String) throws -> [URL] {
        let directory = root.appending(path: relativePath)
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    static func read(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }
}

struct LocalizationTests {
    /// SwiftUI initializers and modifiers whose first string literal is a localization key.
    static let keyCalls =
        #"(?:(?:Text|Button|Label|Toggle|Picker|TextField|SecureField|LabeledContent|ContentUnavailableView|Window|MenuBarExtra|CommandMenu|\.help|LocalizedStringResource|\.navigationTitle|Section|Menu)\(|String\(localized:)\s*"((?:[^"\\]|\\.)*)""#

    struct Catalog {
        /// Normalized key → (original key, pt-BR value)
        var entries: [String: (key: String, portuguese: String?)]
    }

    static func loadCatalog() throws -> Catalog {
        let data = try Data(contentsOf: Repo.root.appending(path: "Cofre/Localizable.xcstrings"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["sourceLanguage"] as? String == "en")
        let strings = try #require(json["strings"] as? [String: Any])
        var entries: [String: (String, String?)] = [:]
        for (key, value) in strings {
            let localizations = (value as? [String: Any])?["localizations"] as? [String: Any]
            let unit = (localizations?["pt-BR"] as? [String: Any])?["stringUnit"] as? [String: Any]
            let translated = unit?["state"] as? String == "translated" ? unit?["value"] as? String : nil
            entries[normalizeCatalogKey(key)] = (key, translated)
        }
        return Catalog(entries: entries)
    }

    /// Keys used in the app's views and in CofreKit's user-facing messages.
    static func usedKeys() throws -> Set<String> {
        let regex = try NSRegularExpression(pattern: keyCalls)
        var keys = Set<String>()
        var sources = try Repo.swiftFiles(in: "Cofre")
        sources += try Repo.swiftFiles(in: "CofreKit/Sources")
        for file in sources {
            let text = try Repo.read(file)
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text) {
                    keys.insert(normalizeSourceLiteral(String(text[range])))
                }
            }
        }
        // VaultError.message: one string literal per line inside the switch.
        let errors = try Repo.read(Repo.root.appending(path: "CofreKit/Sources/CofreKit/VaultError.swift"))
        let lineLiteral = try NSRegularExpression(pattern: #"^\s*"((?:[^"\\]|\\.)*)"\s*$"#, options: .anchorsMatchLines)
        for match in lineLiteral.matches(in: errors, range: NSRange(errors.startIndex..., in: errors)) {
            if let range = Range(match.range(at: 1), in: errors) {
                keys.insert(normalizeSourceLiteral(String(errors[range])))
            }
        }
        return keys
    }

    /// `Copied “\(name)” · clears in \(remaining) s` → `Copied “%_” · clears in %_ s`
    static func normalizeSourceLiteral(_ literal: String) -> String {
        var result = ""
        var index = literal.startIndex
        while index < literal.endIndex {
            if literal[index...].hasPrefix("\\(") {
                var depth = 0
                var cursor = literal.index(after: index)
                while cursor < literal.endIndex {
                    if literal[cursor] == "(" { depth += 1 }
                    if literal[cursor] == ")" {
                        depth -= 1
                        if depth == 0 { break }
                    }
                    cursor = literal.index(after: cursor)
                }
                result += "%_"
                index = cursor < literal.endIndex ? literal.index(after: cursor) : cursor
            } else {
                result.append(literal[index])
                index = literal.index(after: index)
            }
        }
        return result
    }

    /// `Copied “%@” · clears in %lld s` → `Copied “%_” · clears in %_ s`
    static func normalizeCatalogKey(_ key: String) -> String {
        key.replacingOccurrences(of: #"%(\d+\$)?(lld|ld|d|@|f|\.\d+f)"#, with: "%_", options: .regularExpression)
    }

    @Test func normalization() {
        #expect(
            Self.normalizeSourceLiteral(#"Updated \(date, format: .relative(presentation: .named))"#) == "Updated %_")
        #expect(Self.normalizeSourceLiteral(#"A \(String(x)) b \(y)"#) == "A %_ b %_")
        #expect(Self.normalizeCatalogKey("A %@ b %lld c %1$@") == "A %_ b %_ c %_")
    }

    @Test func everyInterfaceStringHasAPortugueseTranslation() throws {
        let catalog = try Self.loadCatalog()
        let used = try Self.usedKeys()
        #expect(used.count > 50, "the key scan found suspiciously few strings")
        for key in used.sorted() {
            guard let entry = catalog.entries[key] else {
                Issue.record("Missing from Cofre/Localizable.xcstrings: \(key)")
                continue
            }
            #expect(entry.portuguese?.isEmpty == false, "No PT-BR translation for: \(entry.key)")
        }
    }

    @Test func noUnusedCatalogEntries() throws {
        let catalog = try Self.loadCatalog()
        let used = try Self.usedKeys()
        for (normalized, entry) in catalog.entries where !used.contains(normalized) {
            Issue.record("Unused catalog entry (remove it): \(entry.key)")
        }
    }

    @Test func translationsKeepTheirPlaceholders() throws {
        for entry in try Self.loadCatalog().entries.values {
            guard let portuguese = entry.portuguese else { continue }
            let pattern = #"%(\d+\$)?(lld|ld|d|@|f)"#
            let count = { (text: String) in
                (try? NSRegularExpression(pattern: pattern))?
                    .numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text)) ?? 0
            }
            #expect(count(entry.key) == count(portuguese), "Placeholders differ: \(entry.key) → \(portuguese)")
        }
    }
}

struct SecurityRulesTests {
    @Test func entitlementsAreSandboxedWithoutNetwork() throws {
        let data = try Data(contentsOf: Repo.root.appending(path: "Config/Cofre.entitlements"))
        let plist = try #require(
            try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
        #expect(plist["com.apple.security.app-sandbox"] as? Bool == true)
        let networkKeys = plist.keys.filter { $0.hasPrefix("com.apple.security.network") }
        #expect(networkKeys.isEmpty, "Cofre must never get network entitlements: \(networkKeys)")
        #expect(
            Set(plist.keys) == ["com.apple.security.app-sandbox", "com.apple.security.files.user-selected.read-write"])
    }

    @Test func noNetworkingOrLoggingAPIsInSources() throws {
        let forbidden = [
            "URLSession", "URLRequest", "NWConnection", "Network.framework", "import Network", "print(", "NSLog(",
            "Logger(", "os_log(",
        ]
        var sources = try Repo.swiftFiles(in: "Cofre")
        sources += try Repo.swiftFiles(in: "CofreKit/Sources")
        for file in sources {
            let text = try Repo.read(file)
            for token in forbidden where text.contains(token) {
                Issue.record("\(file.lastPathComponent) uses \(token)")
            }
        }
    }

    @Test func valuesAreNeverPutInText() throws {
        // A value only leaves SecretValue through exposedData / exposedString(); in the app,
        // only the pasteboard adapter may call them.
        for file in try Repo.swiftFiles(in: "Cofre") where file.lastPathComponent != "SystemPasteboard.swift" {
            let text = try Repo.read(file)
            #expect(!text.contains("exposedString"), "\(file.lastPathComponent) reads a secret's text")
            #expect(!text.contains("exposedData"), "\(file.lastPathComponent) reads a secret's bytes")
        }
    }
}
