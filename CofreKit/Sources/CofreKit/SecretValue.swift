import Foundation

/// The bytes of a secret.
///
/// It never prints, dumps or logs its contents, and it isn't `Codable`: the only ways to get the
/// bytes out are `exposedData` and `exposedString()`, used by the store, the export codec and the
/// pasteboard adapter.
public struct SecretValue: Sendable, Equatable {
    /// Largest value accepted (a long PEM certificate chain is a few KB).
    public static let maximumByteCount = 64 * 1024

    public let exposedData: Data

    public init(data: Data) {
        exposedData = data
    }

    public init(_ string: String) {
        exposedData = Data(string.utf8)
    }

    public var isEmpty: Bool { exposedData.isEmpty }

    public var byteCount: Int { exposedData.count }

    /// Characters when the value is UTF-8 text (what the UI shows as "42 characters"), bytes otherwise.
    public var displayLength: Int {
        exposedString()?.count ?? exposedData.count
    }

    public func exposedString() -> String? {
        String(data: exposedData, encoding: .utf8)
    }
}

extension SecretValue: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "••••••" }
    public var debugDescription: String { "SecretValue(••••••)" }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}
