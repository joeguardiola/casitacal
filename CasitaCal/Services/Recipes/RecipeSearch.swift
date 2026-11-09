import Foundation

/// Matching for the add-meal autocomplete. Ignores case and accents.
enum RecipeSearch {
    /// Best matches first: titles starting with the text, then a word starting with it, then
    /// anywhere inside. Within each group the original order (most recently planned) is kept.
    static func suggestions<T>(for query: String, in items: [T], title: (T) -> String?, limit: Int = 5) -> [T] {
        let needle = fold(query)
        guard !needle.isEmpty else { return [] }

        var startsWith: [T] = []
        var wordStartsWith: [T] = []
        var contains: [T] = []
        for item in items {
            let haystack = fold(title(item) ?? "")
            if haystack.hasPrefix(needle) {
                startsWith.append(item)
            } else if words(in: haystack).contains(where: { $0.hasPrefix(needle) }) {
                wordStartsWith.append(item)
            } else if haystack.contains(needle) {
                contains.append(item)
            }
        }
        return Array((startsWith + wordStartsWith + contains).prefix(limit))
    }

    private static func fold(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private static func words(in text: String) -> [Substring] {
        text.split { !$0.isLetter && !$0.isNumber }
    }
}
