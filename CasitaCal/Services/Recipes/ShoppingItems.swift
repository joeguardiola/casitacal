import Foundation

/// Turns recipe ingredient lines into tidy shopping-list items and spots ones already on the list.
/// Only used when someone taps "Add to Shopping List…" on a recipe — nothing is added automatically.
///
/// "1 ½ pounds ground beef, trimmed" → name "ground beef", amount "1 ½ pounds" → "Ground beef (1 ½ pounds)"
enum ShoppingItems {
    struct Item: Equatable {
        var name: String
        var amount: String?

        var listTitle: String {
            let n = name.prefix(1).uppercased() + name.dropFirst()
            return amount.map { "\(n) (\($0))" } ?? n
        }
    }

    private static let units: Set<String> = [
        "cup", "cups", "c", "tbsp", "tbsps", "tablespoon", "tablespoons", "tbs", "tsp", "tsps", "teaspoon", "teaspoons",
        "oz", "ounce", "ounces", "lb", "lbs", "pound", "pounds", "g", "gram", "grams", "kg", "kilogram", "kilograms",
        "ml", "milliliter", "milliliters", "l", "liter", "liters", "litre", "litres", "pint", "pints", "quart", "quarts",
        "clove", "cloves", "can", "cans", "jar", "jars", "package", "packages", "pkg", "packet", "packets", "bag", "bags",
        "pinch", "pinches", "dash", "dashes", "stick", "sticks", "slice", "slices", "bunch", "bunches", "head", "heads",
        "sprig", "sprigs", "handful", "handfuls", "piece", "pieces", "fillet", "fillets", "box", "boxes", "bottle", "bottles",
    ]
    private static let fractionChars = Set("0123456789¼½¾⅓⅔⅛⅜⅝⅞/.-–")

    static func item(from line: String) -> Item {
        var text = line
            .replacingOccurrences(of: #"\([^)]*\)"#, with: " ", options: .regularExpression) // "(225g)", "(Note 1)"
            .replacingOccurrences(of: #"\$[\d.]+"#, with: " ", options: .regularExpression)  // Budget Bytes prices
        // Prep notes after a comma: "onion, finely chopped" → "onion"
        if let comma = text.firstIndex(of: ",") { text = String(text[..<comma]) }
        var words = text.split(whereSeparator: \.isWhitespace).map(String.init)

        var amount: [String] = []
        while let w = words.first,
              w.allSatisfy({ fractionChars.contains($0) }) || ["a", "an", "about", "plus"].contains(w.lowercased()) {
            amount.append(words.removeFirst())
        }
        if let w = words.first, units.contains(w.lowercased().trimmingCharacters(in: .punctuationCharacters)) {
            amount.append(words.removeFirst())
        }
        if words.first?.lowercased() == "of" { words.removeFirst() }

        let name = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        let qty = amount.filter { !["a", "an", "about"].contains($0.lowercased()) }.joined(separator: " ")
        if name.isEmpty { return Item(name: line.trimmingCharacters(in: .whitespaces), amount: nil) }
        return Item(name: name.lowercased(), amount: qty.isEmpty ? nil : qty)
    }

    /// Is something like this already on the list? ("whole milk" vs "Milk", "2 eggs" vs "eggs")
    static func isAlreadyOnList(_ candidate: Item, existing: [String]) -> Bool {
        let key = normalize(candidate.name)
        guard !key.isEmpty else { return false }
        return existing.contains { title in
            let other = normalize(item(from: title).name)
            guard !other.isEmpty else { return false }
            return key == other || key.hasSuffix(" " + other) || other.hasSuffix(" " + key)
                || singular(key) == singular(other)
        }
    }

    private static func normalize(_ s: String) -> String {
        s.lowercased().folding(options: .diacriticInsensitive, locale: nil)
            .replacingOccurrences(of: #"[^a-z ]"#, with: " ", options: .regularExpression)
            .split(separator: " ").joined(separator: " ")
    }

    private static func singular(_ s: String) -> String {
        if s.hasSuffix("oes") { return String(s.dropLast(2)) }
        if s.hasSuffix("ies") { return String(s.dropLast(3)) + "y" }
        if s.hasSuffix("s") && !s.hasSuffix("ss") { return String(s.dropLast()) }
        return s
    }
}
