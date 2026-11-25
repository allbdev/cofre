import Foundation

/// Rules for secret names (`PLAN.md` D9): trimmed, 1–100 characters, one line, unique by `key`.
public enum SecretName {
    public static let maximumLength = 100

    /// The name with surrounding whitespace removed.
    public static func trimmed(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The comparison key: "Stripe Key", "stripe key" and "STRIPE KÉY" all clash.
    public static func key(_ name: String) -> String {
        trimmed(name).folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: nil
        )
    }

    /// Checks the format only (no uniqueness) and returns the trimmed name.
    public static func validateFormat(_ raw: String) throws(VaultError) -> String {
        let name = trimmed(raw)
        guard !name.isEmpty else { throw .nameEmpty }
        guard name.count <= maximumLength else { throw .nameTooLong }
        guard !name.contains(where: \.isNewline) else { throw .nameMultiline }
        return name
    }

    /// Checks the format and that no other secret (other than `excluding`) has the same key.
    public static func validate(
        _ raw: String,
        against existing: [SecretSummary],
        excluding excludedID: UUID? = nil
    ) throws(VaultError) -> String {
        let name = try validateFormat(raw)
        let nameKey = key(name)
        if let clash = existing.first(where: { $0.id != excludedID && key($0.name) == nameKey }) {
            throw .nameTaken(clash.name)
        }
        return name
    }

    /// `name`, or `name (2)`, `name (3)`… — the first one whose key isn't in `takenKeys`.
    /// The base is shortened when needed so the result stays within `maximumLength`.
    public static func uniqueVariant(of name: String, takenKeys: Set<String>) -> String {
        if !takenKeys.contains(key(name)) { return name }
        var counter = 2
        while true {
            let suffix = " (\(counter))"
            let base = String(name.prefix(maximumLength - suffix.count))
                .trimmingCharacters(in: .whitespaces)
            let candidate = base + suffix
            if !takenKeys.contains(key(candidate)) { return candidate }
            counter += 1
        }
    }
}
