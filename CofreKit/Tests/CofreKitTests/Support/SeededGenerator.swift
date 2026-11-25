import Foundation

@testable import CofreKit

/// SplitMix64: a tiny deterministic generator so property-style tests are reproducible.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

enum Gen {
    /// Characters that tend to break things: accents, emoji, symbols, spaces, CJK.
    static let alphabet: [Character] = Array(
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_.:/@#$%&*()[]{}'\"\\áéíóúãõçÁÉÜñ€😀🔑中文"
    )

    static func string(using generator: inout SeededGenerator, length: ClosedRange<Int>) -> String {
        let count = Int.random(in: length, using: &generator)
        return String((0..<count).map { _ in alphabet.randomElement(using: &generator)! })
    }

    static func bytes(using generator: inout SeededGenerator, count: ClosedRange<Int>) -> Data {
        let length = Int.random(in: count, using: &generator)
        return Data((0..<length).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    /// A valid secret name (trimmed, non-empty, one line, ≤ 100 characters).
    static func name(using generator: inout SeededGenerator) -> String {
        while true {
            let candidate = SecretName.trimmed(string(using: &generator, length: 1...40))
            if !candidate.isEmpty { return candidate }
        }
    }
}
