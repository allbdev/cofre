import Foundation
import Testing

@testable import CofreKit

struct SecretNameTests {
    private func summary(_ name: String, id: UUID = UUID()) -> SecretSummary {
        SecretSummary(id: id, name: name, createdAt: .now, updatedAt: .now)
    }

    @Test func trimsSurroundingWhitespace() throws {
        #expect(try SecretName.validateFormat("  GitHub token \n") == "GitHub token")
    }

    @Test(arguments: ["", "   ", "\n\t"])
    func rejectsEmptyNames(_ raw: String) {
        #expect(throws: VaultError.nameEmpty) { try SecretName.validateFormat(raw) }
    }

    @Test func acceptsExactlyTheMaximumLength() throws {
        let name = String(repeating: "a", count: SecretName.maximumLength)
        #expect(try SecretName.validateFormat(name) == name)
    }

    @Test func rejectsLongNames() {
        let name = String(repeating: "é", count: SecretName.maximumLength + 1)
        #expect(throws: VaultError.nameTooLong) { try SecretName.validateFormat(name) }
    }

    @Test(arguments: ["first\nsecond", "first\rsecond", "a\u{2028}b"])
    func rejectsMultilineNames(_ raw: String) {
        #expect(throws: VaultError.nameMultiline) { try SecretName.validateFormat(raw) }
    }

    @Test(arguments: [
        ("Stripe Key", "stripe key"),
        ("Stripe Key", "STRIPE KÉY"),
        ("Café", "cafe"),
        ("Token", "  token  "),
        ("ＡＢＣ", "abc"),
    ])
    func keysIgnoreCaseAccentsWidthAndSpaces(_ lhs: String, _ rhs: String) {
        #expect(SecretName.key(lhs) == SecretName.key(rhs))
    }

    @Test func rejectsDuplicatesAndNamesTheClash() {
        let existing = [summary("AWS access key")]
        #expect(throws: VaultError.nameTaken("AWS access key")) {
            try SecretName.validate("aws ACCESS key", against: existing)
        }
    }

    @Test func renamingToItsOwnNameIsAllowed() throws {
        let id = UUID()
        let existing = [summary("Token", id: id), summary("Other")]
        #expect(try SecretName.validate("TOKEN", against: existing, excluding: id) == "TOKEN")
    }

    @Test func uniqueVariantCounts() {
        let taken: Set = [SecretName.key("Key"), SecretName.key("Key (2)")]
        #expect(SecretName.uniqueVariant(of: "Key", takenKeys: taken) == "Key (3)")
        #expect(SecretName.uniqueVariant(of: "Fresh", takenKeys: taken) == "Fresh")
    }

    @Test func uniqueVariantStaysWithinTheLimit() throws {
        let long = String(repeating: "x", count: SecretName.maximumLength)
        let variant = SecretName.uniqueVariant(of: long, takenKeys: [SecretName.key(long)])
        #expect(variant.count <= SecretName.maximumLength)
        #expect(variant.hasSuffix(" (2)"))
        #expect(try SecretName.validateFormat(variant) == variant)
    }

    @Test func uniqueVariantIsAlwaysFreeAndValid() throws {
        var generator = SeededGenerator(seed: 7)
        for _ in 0..<300 {
            let name = Gen.name(using: &generator)
            var taken: Set<String> = [SecretName.key(name)]
            for counter in 2..<Int.random(in: 2...6, using: &generator) {
                taken.insert(SecretName.key("\(name) (\(counter))"))
            }
            let variant = SecretName.uniqueVariant(of: name, takenKeys: taken)
            #expect(!taken.contains(SecretName.key(variant)))
            #expect(try SecretName.validateFormat(variant) == variant)
        }
    }
}
