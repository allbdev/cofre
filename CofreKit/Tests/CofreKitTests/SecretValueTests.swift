import Foundation
import Testing

@testable import CofreKit

struct SecretValueTests {
    let value = SecretValue("sk_live_supersecret")

    @Test func descriptionNeverContainsTheValue() {
        #expect(value.description == "••••••")
        #expect(value.debugDescription == "SecretValue(••••••)")
        #expect(!"\(value)".contains("supersecret"))
        #expect(!String(reflecting: value).contains("supersecret"))
    }

    @Test func dumpAndMirrorDontRevealTheValue() {
        var dumped = ""
        dump(value, to: &dumped)
        #expect(!dumped.contains("supersecret"))
        #expect(Mirror(reflecting: value).children.isEmpty)
    }

    @Test func wrappedInOtherTypesItStaysRedacted() {
        let item = ExportItem(name: "Stripe", value: value, createdAt: .now, updatedAt: .now)
        #expect(!"\(item)".contains("supersecret"))
        #expect(!"\([value])".contains("supersecret"))
    }

    @Test func exposesTextAndLength() {
        #expect(value.exposedString() == "sk_live_supersecret")
        #expect(value.displayLength == 19)
        #expect(SecretValue("ção🔑").displayLength == 4)
        #expect(SecretValue("ção🔑").byteCount == 9)
    }

    @Test func binaryValuesReportBytes() {
        let binary = SecretValue(data: Data([0xFF, 0xFE, 0x00]))
        #expect(binary.exposedString() == nil)
        #expect(binary.displayLength == 3)
    }

    @Test func emptiness() {
        #expect(SecretValue("").isEmpty)
        #expect(!value.isEmpty)
    }
}
