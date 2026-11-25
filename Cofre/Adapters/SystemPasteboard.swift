import AppKit
import CofreKit

/// `NSPasteboard.general` as a `Pasteboard`. Secrets are written with the nspasteboard.org
/// markers so clipboard managers and Universal Clipboard skip them (`PLAN.md` D6).
@MainActor
final class SystemPasteboard: CofreKit.Pasteboard {
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int { pasteboard.changeCount }

    func writeConcealed(_ value: SecretValue) -> Int {
        let item = NSPasteboardItem()
        if let text = value.exposedString() {
            item.setString(text, forType: .string)
        } else {
            item.setData(value.exposedData, forType: .string)
        }
        item.setData(Data(), forType: Self.concealedType)
        item.setData(Data(), forType: Self.transientType)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        return pasteboard.changeCount
    }

    func readString() -> String? {
        pasteboard.string(forType: .string)
    }

    func clear() {
        pasteboard.clearContents()
    }
}
