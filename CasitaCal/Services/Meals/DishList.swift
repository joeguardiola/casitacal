import Foundation

/// Reads a typed meal like "Chicken soup, slice of Colby jack, blackberries and 2 saltines" as a
/// main dish plus sides, so it shows on the plan like one picked from recipes.
///
/// Careful by design: a single dish ("Mac and cheese", "Rice and beans") is never split. "and" only
/// splits inside a list that already has commas ("a, b and c"); "with" starts the sides
/// ("Steak with salad, rolls"). Text in parentheses stays with its dish.
enum DishList {
    /// The main dish and its sides, or nil when the text is a single dish.
    static func split(_ text: String) -> (main: String, sides: [String])? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var items: [String]
        if let with = rangeOutsideParentheses(of: " with ", in: trimmed) {
            let main = String(trimmed[..<with.lowerBound])
            let rest = listItems(String(trimmed[with.upperBound...]), splitAnd: true)
            items = [main] + rest
        } else {
            let parts = separated(trimmed)
            guard parts.count > 1 else { return nil }
            items = listItems(trimmed, splitAnd: true)
        }
        items = items.map(clean).filter { !$0.isEmpty }
        guard items.count > 1 else { return nil }
        return (capitalizedFirst(items[0]), items.dropFirst().map(capitalizedFirst))
    }

    /// "a, b + c; d and e" → [a, b, c, d, e]. The last item splits on "and"/"&" only when the list
    /// already had a separator, or `splitAnd` is set for a lone "with" phrase that has one.
    private static func listItems(_ text: String, splitAnd: Bool) -> [String] {
        var parts = separated(text)
        guard splitAnd, parts.count > 1, let last = parts.popLast() else { return parts }
        return parts + splitOnAnd(last)
    }

    /// Splits on commas, "+" and ";" outside parentheses.
    private static func separated(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        for ch in text {
            switch ch {
            case "(", "[": depth += 1; current.append(ch)
            case ")", "]": depth = max(0, depth - 1); current.append(ch)
            case ",", ";", "+":
                if depth == 0 { parts.append(current); current = "" } else { current.append(ch) }
            default: current.append(ch)
            }
        }
        parts.append(current)
        return parts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private static func splitOnAnd(_ text: String) -> [String] {
        for word in [" and ", " & "] {
            if let r = rangeOutsideParentheses(of: word, in: text) {
                return [String(text[..<r.lowerBound]), String(text[r.upperBound...])]
            }
        }
        return [text]
    }

    private static func rangeOutsideParentheses(of word: String, in text: String) -> Range<String.Index>? {
        var search = text.startIndex..<text.endIndex
        while let r = text.range(of: word, options: .caseInsensitive, range: search) {
            let before = text[..<r.lowerBound]
            let open = before.filter { $0 == "(" || $0 == "[" }.count
            let close = before.filter { $0 == ")" || $0 == "]" }.count
            if open <= close { return r }
            search = r.upperBound..<text.endIndex
        }
        return nil
    }

    /// Drops a leading "and"/"&"/"with" and stray punctuation.
    private static func clean(_ item: String) -> String {
        var s = item.trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: ".")))
        for lead in ["and ", "& ", "with "] where s.lowercased().hasPrefix(lead) {
            s = String(s.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces)
        }
        return s
    }

    private static func capitalizedFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return first.uppercased() + s.dropFirst()
    }
}

extension CDMeal {
    /// The meal as it should read on the plan: the main dish and its sides. A typed main that's
    /// really a list ("Soup, crackers and fruit") is shown as a main plus sides; saved recipes
    /// are never split.
    var plate: (main: String, sides: [String]) {
        let main = mainTitle
        if recipe == nil, let parts = DishList.split(main) {
            return (parts.main, parts.sides + sideTitles)
        }
        return (main, sideTitles)
    }

    /// One-line name for small spots (Week, the slideshow card): the main dish, or "+ Salad, Rolls"
    /// when only sides are planned, so a side never reads as the main.
    var displayTitle: String? {
        let plate = plate
        if !plate.main.isEmpty { return plate.main }
        return plate.sides.isEmpty ? nil : "+ " + plate.sides.joined(separator: ", ")
    }

    /// Has a main dish or at least one side.
    var isPlanned: Bool { !mainTitle.isEmpty || !sideTitles.isEmpty }

    /// The recipe whose photo stands for the meal: the main's, else the first side with one.
    var photoRecipe: CDRecipe? {
        if let recipe, recipe.imageData != nil { return recipe }
        if !mainTitle.isEmpty { return nil }
        return sortedSides.lazy.compactMap(\.recipe).first { $0.imageData != nil }
    }
}
