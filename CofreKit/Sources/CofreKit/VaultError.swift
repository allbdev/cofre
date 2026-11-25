import Foundation

/// Every failure the user can see. `message` is shown in the app (translated in
/// `Cofre/Localizable.xcstrings`); it never contains a secret value.
public enum VaultError: Error, Equatable, Sendable {
    case nameEmpty
    case nameTooLong
    case nameMultiline
    case nameTaken(String)
    case valueEmpty
    case valueTooLarge
    case notFound
    case locked
    case authenticationCancelled
    case authenticationFailed
    case keychainUnavailable
    case keychain(status: Int32)
    case passphraseTooShort
    case passphrasesDontMatch
    case exportNotACofreFile
    case exportTooLarge
    case exportUnsupportedVersion(Int)
    case exportUnsupportedAlgorithm
    case exportBadParameters
    case exportDecryptionFailed
    case exportCorruptPayload

    public var message: LocalizedStringResource {
        switch self {
        case .nameEmpty:
            "Give the secret a name."
        case .nameTooLong:
            "Names can be at most \(SecretName.maximumLength) characters."
        case .nameMultiline:
            "Names must fit on one line."
        case .nameTaken(let name):
            "There's already a secret called “\(name)”."
        case .valueEmpty:
            "The value is empty."
        case .valueTooLarge:
            "The value is too large (64 KB at most)."
        case .notFound:
            "That secret no longer exists."
        case .locked:
            "Cofre is locked. Unlock it to use your secrets."
        case .authenticationCancelled:
            "Unlocking was cancelled."
        case .authenticationFailed:
            "Cofre couldn't confirm it's you."
        case .keychainUnavailable:
            "The Keychain isn't available to this copy of Cofre. It must be signed with a development team (see the README)."
        case .keychain(let status):
            "The Keychain reported an error (\(String(status)))."
        case .passphraseTooShort:
            "Use a passphrase of at least \(ExportCodec.minimumPassphraseLength) characters."
        case .passphrasesDontMatch:
            "The passphrases don't match."
        case .exportNotACofreFile:
            "This isn't a Cofre export file."
        case .exportTooLarge:
            "This file is too large to be a Cofre export."
        case .exportUnsupportedVersion(let version):
            "This export was made by a newer Cofre (format \(String(version))). Update Cofre to import it."
        case .exportUnsupportedAlgorithm, .exportBadParameters:
            "This export file uses settings Cofre doesn't accept."
        case .exportDecryptionFailed:
            "Wrong passphrase, or the file was modified."
        case .exportCorruptPayload:
            "The file decrypted, but its contents are damaged."
        }
    }
}
