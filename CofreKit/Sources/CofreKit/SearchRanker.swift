import Foundation

/// Orders secrets for a search query: whole name, then name prefix, then word prefix, then
/// substring, then letters in order ("stk" finds "Stripe key"). Case- and accent-insensitive.
/// An empty query keeps every item, sorted by name.
public enum SearchRanker {
    enum Match: Int, Comparable {
        case exact, prefix, wordPrefix, substring, subsequence

        static func < (lhs: Match, rhs: Match) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public static func rank<Item>(
        _ items: [Item],
        query: String,
        name: (Item) -> String
    ) -> [Item] {
        let foldedQuery = fold(query).trimmingCharacters(in: .whitespaces)
        guard !foldedQuery.isEmpty else {
            return items.sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending }
        }
        return
            items
            .compactMap { item -> (item: Item, match: Match, name: String)? in
                let itemName = name(item)
                guard let match = match(name: itemName, foldedQuery: foldedQuery) else { return nil }
                return (item, match, itemName)
            }
            .sorted { lhs, rhs in
                if lhs.match != rhs.match { return lhs.match < rhs.match }
                if lhs.name.count != rhs.name.count { return lhs.name.count < rhs.name.count }
                return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
            }
            .map(\.item)
    }

    static func fold(_ text: String) -> String {
        text.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: nil
        )
    }

    static func match(name: String, foldedQuery query: String) -> Match? {
        let folded = fold(name)
        if folded == query { return .exact }
        if folded.hasPrefix(query) { return .prefix }
        let words = folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if words.contains(where: { $0.hasPrefix(query) }) { return .wordPrefix }
        if folded.contains(query) { return .substring }
        let queryLetters = query.filter { !$0.isWhitespace }
        guard !queryLetters.isEmpty else { return nil }
        var remaining = queryLetters[...]
        for character in folded where character == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return .subsequence }
        }
        return nil
    }
}
