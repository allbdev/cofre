import CryptoKit
import Foundation
import Testing

@testable import CofreKit

struct ExportCodecTests {
    /// Low iteration counts keep the suite fast; one test uses the real default.
    let codec = ExportCodec(iterations: 1_000, acceptedIterations: 1_000...10_000_000)
    let passphrase = "correct horse battery"
    let date = Date(timeIntervalSince1970: 1_790_000_000)

    private var payload: ExportPayload {
        ExportPayload(
            exportedAt: date,
            items: [
                ExportItem(name: "Stripe key", value: SecretValue("sk_live_1"), createdAt: date, updatedAt: date),
                ExportItem(
                    name: "Chave PEM ção 🔑",
                    value: SecretValue("-----BEGIN KEY-----\nabc\n-----END KEY-----\n"),
                    createdAt: date,
                    updatedAt: date.addingTimeInterval(60)
                ),
            ]
        )
    }

    private func json(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MissingField(key: "root")
        }
        return object
    }

    struct MissingField: Error { var key: String }

    private func field<T>(_ object: [String: Any], _ key: String, as type: T.Type = T.self) throws -> T {
        guard let value = object[key] as? T else { throw MissingField(key: key) }
        return value
    }

    private func base64Field(_ object: [String: Any], _ key: String) throws -> Data {
        guard let data = Data(base64Encoded: try field(object, key, as: String.self)) else {
            throw MissingField(key: key)
        }
        return data
    }

    private func reencode(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object)
    }

    @Test func roundTrips() throws {
        let data = try codec.encode(payload, passphrase: passphrase)
        #expect(try codec.decode(data, passphrase: passphrase) == payload)
    }

    @Test func roundTripsAnyNamesAndBytes() throws {
        var generator = SeededGenerator(seed: 2026)
        for _ in 0..<25 {
            let items = (0..<Int.random(in: 0...5, using: &generator)).map { _ in
                ExportItem(
                    name: Gen.name(using: &generator),
                    value: SecretValue(data: Gen.bytes(using: &generator, count: 1...300)),
                    createdAt: date,
                    updatedAt: date
                )
            }
            let passphrase = Gen.string(using: &generator, length: 12...40)
            let original = ExportPayload(exportedAt: date, items: items)
            let data = try codec.encode(original, passphrase: passphrase)
            #expect(try codec.decode(data, passphrase: passphrase) == original)
        }
    }

    @Test func fileMatchesTheDocumentedShape() throws {
        let object = try json(try codec.encode(payload, passphrase: passphrase))
        #expect(object["format"] as? String == "cofre-export")
        #expect(object["version"] as? Int == 1)
        let kdf: [String: Any] = try field(object, "kdf")
        #expect(kdf["algorithm"] as? String == "PBKDF2-HMAC-SHA256")
        #expect(kdf["iterations"] as? Int == 1_000)
        #expect(try base64Field(kdf, "salt").count == 16)
        let cipher: [String: Any] = try field(object, "cipher")
        #expect(cipher["algorithm"] as? String == "AES-256-GCM")
        #expect(try base64Field(cipher, "nonce").count == 12)
        #expect(Set(object.keys) == ["format", "version", "kdf", "cipher", "ciphertext"])
    }

    @Test func noPlaintextInTheFile() throws {
        let data = try codec.encode(payload, passphrase: passphrase)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("sk_live_1"))
        #expect(!text.contains("Stripe"))
        #expect(!text.contains(Data("sk_live_1".utf8).base64EncodedString()))
    }

    @Test func saltAndNonceAreFreshEveryTime() throws {
        let first = try json(try codec.encode(payload, passphrase: passphrase))
        let second = try json(try codec.encode(payload, passphrase: passphrase))
        #expect(
            (first["kdf"] as? [String: Any])?["salt"] as? String != (second["kdf"] as? [String: Any])?["salt"]
                as? String)
        #expect(first["ciphertext"] as? String != second["ciphertext"] as? String)
    }

    @Test func defaultsToSixHundredThousandIterations() throws {
        let data = try ExportCodec().encode(ExportPayload(exportedAt: date, items: []), passphrase: passphrase)
        let kdf: [String: Any] = try field(try json(data), "kdf")
        #expect(kdf["iterations"] as? Int == 600_000)
        #expect(try ExportCodec().decode(data, passphrase: passphrase).items.isEmpty)
    }

    /// Matches the Python recipe in docs/EXPORT_FORMAT.md, so the doc stays true.
    @Test func decryptsByTheDocumentedRecipe() throws {
        let data = try codec.encode(payload, passphrase: passphrase)
        let object = try json(data)
        let kdf: [String: Any] = try field(object, "kdf")
        let cipher: [String: Any] = try field(object, "cipher")
        let saltText: String = try field(kdf, "salt")
        let iterations: Int = try field(kdf, "iterations")
        let key = try ExportCodec.deriveKey(
            passphrase: passphrase,
            salt: try base64Field(kdf, "salt"),
            iterations: iterations
        )
        let combined = try base64Field(object, "ciphertext")
        let box = try AES.GCM.SealedBox(
            nonce: AES.GCM.Nonce(data: try base64Field(cipher, "nonce")),
            ciphertext: combined.dropLast(16),
            tag: combined.suffix(16)
        )
        let aad = "cofre-export/1/PBKDF2-HMAC-SHA256/\(iterations)/\(saltText)/AES-256-GCM"
        let plaintext = try AES.GCM.open(box, using: key, authenticating: Data(aad.utf8))
        let decoded = try json(plaintext)
        let items: [[String: Any]] = try field(decoded, "items")
        #expect(items.first?["name"] as? String == "Stripe key")
        #expect(items.first?["value"] as? String == Data("sk_live_1".utf8).base64EncodedString())
    }

    /// PBKDF2-HMAC-SHA256 test vector (RFC 7914 §11), so the KDF wiring is the standard one.
    @Test func pbkdf2MatchesTheStandardVector() throws {
        let key = try ExportCodec.deriveKey(passphrase: "passwd", salt: Data("salt".utf8), iterations: 1)
        let hex = key.withUnsafeBytes { Data($0) }.map { String(format: "%02x", $0) }.joined()
        #expect(hex == "55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc")
    }

    @Test func passphrasesAreNormalized() throws {
        let composed = "senha-çãé-longa"  // precomposed
        let decomposed = composed.decomposedStringWithCanonicalMapping
        #expect(composed.unicodeScalars.count != decomposed.unicodeScalars.count)
        let data = try codec.encode(payload, passphrase: composed)
        #expect(try codec.decode(data, passphrase: decomposed) == payload)
    }

    // MARK: - Failures

    @Test func shortPassphrasesAreRefused() {
        #expect(throws: VaultError.passphraseTooShort) {
            try codec.encode(payload, passphrase: "short")
        }
    }

    @Test func wrongPassphraseFails() throws {
        let data = try codec.encode(payload, passphrase: passphrase)
        #expect(throws: VaultError.exportDecryptionFailed) {
            try codec.decode(data, passphrase: "incorrect horse battery")
        }
    }

    @Test func anyFlippedCiphertextByteFails() throws {
        var object = try json(try codec.encode(payload, passphrase: passphrase))
        let bytes = try base64Field(object, "ciphertext")
        for index in [0, bytes.count / 2, bytes.count - 1] {
            var tampered = bytes
            tampered[index] ^= 0x01
            object["ciphertext"] = tampered.base64EncodedString()
            #expect(throws: VaultError.exportDecryptionFailed) {
                try codec.decode(try reencode(object), passphrase: passphrase)
            }
        }
    }

    @Test func changingTheIterationCountFails() throws {
        var object = try json(try codec.encode(payload, passphrase: passphrase))
        var kdf: [String: Any] = try field(object, "kdf")
        kdf["iterations"] = 1_001
        object["kdf"] = kdf
        #expect(throws: VaultError.exportDecryptionFailed) {
            try codec.decode(try reencode(object), passphrase: passphrase)
        }
    }

    @Test(arguments: [99_999, 10_000_001, 0, -5])
    func iterationCountsOutsideTheRangeAreRefused(_ iterations: Int) throws {
        var object = try json(try codec.encode(payload, passphrase: passphrase))
        var kdf: [String: Any] = try field(object, "kdf")
        kdf["iterations"] = iterations
        object["kdf"] = kdf
        #expect(throws: VaultError.exportBadParameters) {
            try ExportCodec().decode(try reencode(object), passphrase: passphrase)
        }
    }

    @Test func badSaltOrNonceIsRefused() throws {
        let object = try json(try codec.encode(payload, passphrase: passphrase))
        var badSalt = object
        badSalt["kdf"] = [
            "algorithm": "PBKDF2-HMAC-SHA256", "iterations": 1_000, "salt": Data(count: 8).base64EncodedString(),
        ]
        #expect(throws: VaultError.exportBadParameters) {
            try codec.decode(try reencode(badSalt), passphrase: passphrase)
        }
        var badNonce = object
        badNonce["cipher"] = ["algorithm": "AES-256-GCM", "nonce": "not base64!"]
        #expect(throws: VaultError.exportBadParameters) {
            try codec.decode(try reencode(badNonce), passphrase: passphrase)
        }
    }

    @Test func unknownAlgorithmsAreRefused() throws {
        var object = try json(try codec.encode(payload, passphrase: passphrase))
        object["cipher"] = ["algorithm": "ChaCha20", "nonce": Data(count: 12).base64EncodedString()]
        #expect(throws: VaultError.exportUnsupportedAlgorithm) {
            try codec.decode(try reencode(object), passphrase: passphrase)
        }
    }

    @Test func newerVersionsAreRefusedWithTheirNumber() throws {
        var object = try json(try codec.encode(payload, passphrase: passphrase))
        object["version"] = 2
        #expect(throws: VaultError.exportUnsupportedVersion(2)) {
            try codec.decode(try reencode(object), passphrase: passphrase)
        }
    }

    @Test(arguments: [
        Data("not json".utf8),
        Data("{}".utf8),
        Data(#"{"format":"something-else","version":1}"#.utf8),
        Data(#"{"format":"cofre-export","version":1}"#.utf8),
        Data(),
    ])
    func otherFilesAreRefused(_ data: Data) {
        #expect(throws: VaultError.exportNotACofreFile) {
            try codec.decode(data, passphrase: passphrase)
        }
    }

    @Test func oversizedFilesAreRefusedBeforeParsing() {
        let huge = Data(count: ExportCodec.maximumFileSize + 1)
        #expect(throws: VaultError.exportTooLarge) { try codec.decode(huge, passphrase: passphrase) }
    }

    @Test func invalidNamesInsideTheFileAreRefused() throws {
        let bad = ExportPayload(
            exportedAt: date,
            items: [ExportItem(name: "two\nlines", value: SecretValue("x"), createdAt: date, updatedAt: date)]
        )
        let data = try codec.encode(bad, passphrase: passphrase)
        #expect(throws: VaultError.exportCorruptPayload) { try codec.decode(data, passphrase: passphrase) }
    }
}
