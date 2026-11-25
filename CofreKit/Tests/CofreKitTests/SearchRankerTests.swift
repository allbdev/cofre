import Foundation
import Testing

@testable import CofreKit

struct SearchRankerTests {
    private func rank(_ names: [String], _ query: String) -> [String] {
        SearchRanker.rank(names, query: query, name: { $0 })
    }

    @Test func emptyQueryKeepsEverythingSortedByName() {
        #expect(rank(["b", "A", "c10", "c9"], "") == ["A", "b", "c9", "c10"])
        #expect(rank(["b", "A"], "   ") == ["A", "b"])
    }

    @Test func ordersByMatchQuality() {
        let names = ["Token for stripe", "Stripe key", "stripe", "My Stripe webhook", "Sxtxrxixpxe"]
        #expect(
            rank(names, "stripe") == [
                "stripe",  // exact
                "Stripe key",  // prefix
                "Token for stripe",  // word prefix (shorter wins the tie)
                "My Stripe webhook",  // word prefix
                "Sxtxrxixpxe",  // letters in order
            ]
        )
    }

    @Test func substringAndSubsequence() {
        // "tal" is inside "Digital"; "GitHub token" has no "a".
        #expect(rank(["GitHub token", "Digital Ocean"], "tal") == ["Digital Ocean"])
        // A substring beats letters-in-order, even for a longer name.
        #expect(rank(["Gxtxk", "My GTK things"], "gtk") == ["My GTK things", "Gxtxk"])
        #expect(rank(["Stripe key", "AWS"], "stk") == ["Stripe key"])
    }

    @Test func ignoresCaseAndAccents() {
        #expect(rank(["Senha do Café"], "CAFE") == ["Senha do Café"])
        #expect(rank(["cafe"], "Café") == ["cafe"])
    }

    @Test func dropsNonMatches() {
        #expect(rank(["AWS", "GCP"], "stripe").isEmpty)
    }

    @Test func everyNameFindsItself() {
        var generator = SeededGenerator(seed: 42)
        for _ in 0..<300 {
            let names = (0..<8).map { _ in Gen.name(using: &generator) }
            let target = names.randomElement(using: &generator)!
            let ranked = rank(names, target)
            #expect(ranked.contains(target), "\(target) not found in \(names)")
            // An exact match always ranks first.
            #expect(SearchRanker.fold(ranked.first!) == SearchRanker.fold(target))
        }
    }

    @Test func resultsAreASubsetAndPrefixesOfANameAlwaysMatchIt() {
        var generator = SeededGenerator(seed: 99)
        for _ in 0..<300 {
            let names = (0..<6).map { _ in Gen.name(using: &generator) }
            let target = names.randomElement(using: &generator)!
            let prefix = String(target.prefix(Int.random(in: 1...target.count, using: &generator)))
            let ranked = rank(names, prefix)
            #expect(Set(ranked).isSubset(of: Set(names)))
            if !prefix.trimmingCharacters(in: .whitespaces).isEmpty {
                #expect(ranked.contains(target), "\(prefix) didn't match \(target)")
            }
        }
    }
}
