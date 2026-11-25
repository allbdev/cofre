import CommonCrypto
import CryptoKit
import Foundation

/// One secret inside an export file.
public struct ExportItem: Sendable, Equatable {
    public var name: String
    public var value: SecretValue
    public var createdAt: Date
    public var updatedAt: Date

    public init(name: String, value: SecretValue, createdAt: Date, updatedAt: Date) {
        self.name = name
        self.value = value
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// The decrypted contents of an export file.
public struct ExportPayload: Sendable, Equatable {
    public var exportedAt: Date
    public var items: [ExportItem]

    public init(exportedAt: Date, items: [ExportItem]) {
        self.exportedAt = exportedAt
        self.items = items
    }
}

/// Reads and writes `.cofre` files exactly as `docs/EXPORT_FORMAT.md` describes:
/// PBKDF2-HMAC-SHA256 → AES-256-GCM, versioned JSON.
public struct ExportCodec: Sendable {
    public static let formatName = "cofre-export"
    public static let currentVersion = 1
    public static let kdfAlgorithm = "PBKDF2-HMAC-SHA256"
    public static let cipherAlgorithm = "AES-256-GCM"
    public static let defaultIterations = 600_000
    public static let acceptedIterations = 100_000...10_000_000
    public static let minimumPassphraseLength = 12
    public static let maximumFileSize = 10 * 1024 * 1024
    public static let fileExtension = "cofre"

    static let saltLength = 16
    static let nonceLength = 12
    static let tagLength = 16
    static let keyLength = 32

    /// Iterations used when writing. Tests lower it (with `acceptedIterations`) to stay fast.
    public var iterations: Int
    /// Iteration counts accepted when reading.
    public var acceptedIterations: ClosedRange<Int>

    public init(
        iterations: Int = ExportCodec.defaultIterations,
        acceptedIterations: ClosedRange<Int> = ExportCodec.acceptedIterations
    ) {
        self.iterations = iterations
        self.acceptedIterations = acceptedIterations
    }

    // MARK: - Writing

    public func encode(_ payload: ExportPayload, passphrase: String) throws(VaultError) -> Data {
        guard passphrase.count >= Self.minimumPassphraseLength else { throw .passphraseTooShort }
        let salt = Self.randomBytes(count: Self.saltLength)
        let key = try Self.deriveKey(passphrase: passphrase, salt: salt, iterations: iterations)
        let header = Header(iterations: iterations, salt: salt.base64EncodedString())

        let plaintext: Data
        do {
            plaintext = try Self.jsonEncoder.encode(PayloadDTO(payload))
        } catch {
            throw .exportCorruptPayload
        }

        let sealed: AES.GCM.SealedBox
        do {
            sealed = try AES.GCM.seal(
                plaintext,
                using: key,
                nonce: AES.GCM.Nonce(),
                authenticating: Data(header.additionalData.utf8)
            )
        } catch {
            throw .exportCorruptPayload
        }

        let file = FileDTO(
            format: Self.formatName,
            version: Self.currentVersion,
            kdf: .init(algorithm: Self.kdfAlgorithm, iterations: iterations, salt: header.salt),
            cipher: .init(
                algorithm: Self.cipherAlgorithm,
                nonce: Data(sealed.nonce).base64EncodedString()
            ),
            ciphertext: (sealed.ciphertext + sealed.tag).base64EncodedString()
        )
        do {
            return try Self.jsonEncoder.encode(file)
        } catch {
            throw .exportCorruptPayload
        }
    }

    // MARK: - Reading

    public func decode(_ data: Data, passphrase: String) throws(VaultError) -> ExportPayload {
        guard data.count <= Self.maximumFileSize else { throw .exportTooLarge }

        let probe: VersionProbe
        do {
            probe = try JSONDecoder().decode(VersionProbe.self, from: data)
        } catch {
            throw .exportNotACofreFile
        }
        guard probe.format == Self.formatName else { throw .exportNotACofreFile }
        guard probe.version == Self.currentVersion else {
            throw .exportUnsupportedVersion(probe.version)
        }

        let file: FileDTO
        do {
            file = try JSONDecoder().decode(FileDTO.self, from: data)
        } catch {
            throw .exportNotACofreFile
        }
        guard file.kdf.algorithm == Self.kdfAlgorithm, file.cipher.algorithm == Self.cipherAlgorithm
        else { throw .exportUnsupportedAlgorithm }
        guard acceptedIterations.contains(file.kdf.iterations),
            let salt = Data(base64Encoded: file.kdf.salt), salt.count == Self.saltLength,
            let nonceData = Data(base64Encoded: file.cipher.nonce),
            nonceData.count == Self.nonceLength,
            let combined = Data(base64Encoded: file.ciphertext), combined.count >= Self.tagLength,
            let nonce = try? AES.GCM.Nonce(data: nonceData)
        else { throw .exportBadParameters }

        let key = try Self.deriveKey(passphrase: passphrase, salt: salt, iterations: file.kdf.iterations)
        let header = Header(iterations: file.kdf.iterations, salt: file.kdf.salt)
        let plaintext: Data
        do {
            let box = try AES.GCM.SealedBox(
                nonce: nonce,
                ciphertext: combined.dropLast(Self.tagLength),
                tag: combined.suffix(Self.tagLength)
            )
            plaintext = try AES.GCM.open(box, using: key, authenticating: Data(header.additionalData.utf8))
        } catch {
            throw .exportDecryptionFailed
        }

        let dto: PayloadDTO
        do {
            dto = try Self.jsonDecoder.decode(PayloadDTO.self, from: plaintext)
        } catch {
            throw .exportCorruptPayload
        }
        var items: [ExportItem] = []
        for item in dto.items {
            guard let value = Data(base64Encoded: item.value),
                let name = try? SecretName.validateFormat(item.name)
            else { throw .exportCorruptPayload }
            items.append(
                ExportItem(
                    name: name,
                    value: SecretValue(data: value),
                    createdAt: item.createdAt,
                    updatedAt: item.updatedAt
                )
            )
        }
        return ExportPayload(exportedAt: dto.exportedAt, items: items)
    }

    // MARK: - Crypto helpers

    static func deriveKey(passphrase: String, salt: Data, iterations: Int) throws(VaultError)
        -> SymmetricKey
    {
        let password = Data(passphrase.precomposedStringWithCanonicalMapping.utf8)
        var derived = Data(count: keyLength)
        let status = derived.withUnsafeMutableBytes { derivedBytes in
            password.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: CChar.self),
                        password.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keyLength
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw .exportBadParameters }
        return SymmetricKey(data: derived)
    }

    static func randomBytes(count: Int) -> Data {
        var generator = SystemRandomNumberGenerator()
        return Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    private static var jsonEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var jsonDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

// MARK: - File shapes

extension ExportCodec {
    struct Header {
        var iterations: Int
        var salt: String

        /// Bound to the ciphertext so any change to the header fails decryption.
        var additionalData: String {
            "\(ExportCodec.formatName)/\(ExportCodec.currentVersion)/\(ExportCodec.kdfAlgorithm)/\(iterations)/\(salt)/\(ExportCodec.cipherAlgorithm)"
        }
    }

    struct VersionProbe: Decodable {
        var format: String
        var version: Int
    }

    struct FileDTO: Codable {
        struct KDF: Codable {
            var algorithm: String
            var iterations: Int
            var salt: String
        }

        struct Cipher: Codable {
            var algorithm: String
            var nonce: String
        }

        var format: String
        var version: Int
        var kdf: KDF
        var cipher: Cipher
        var ciphertext: String
    }

    struct PayloadDTO: Codable {
        struct Item: Codable {
            var name: String
            var value: String
            var createdAt: Date
            var updatedAt: Date
        }

        var exportedAt: Date
        var items: [Item]

        init(_ payload: ExportPayload) {
            exportedAt = payload.exportedAt
            items = payload.items.map {
                Item(
                    name: $0.name,
                    value: $0.value.exposedData.base64EncodedString(),
                    createdAt: $0.createdAt,
                    updatedAt: $0.updatedAt
                )
            }
        }
    }
}
