import Foundation

/// A recipe pulled out of a web page.
struct ParsedRecipe: Equatable, Sendable {
    var title: String
    var sourceURL: URL
    var siteName: String?
    var summary: String?
    var imageURL: URL?
    var ingredients: [String] = []
    /// Lines starting with "## " are section headings ("For the sauce").
    var steps: [String] = []
    var prepMinutes = 0
    var cookMinutes = 0
    var totalMinutes = 0
    var servings: String?

    /// True when the page had real recipe data (not just a title and photo).
    var hasRecipeDetails: Bool { !ingredients.isEmpty || !steps.isEmpty }
}

/// Reads recipes from web pages.
///
/// Most recipe sites embed a schema.org `Recipe` as JSON-LD (it's what powers Google's recipe
/// cards), so we read that: title, photo, ingredients, steps, times, servings. Pages without it
/// still give a title and photo from their Open Graph tags (what Messages shows for a link).
enum RecipeParser {
    static func parse(html: String, url: URL) -> ParsedRecipe? {
        let meta = metaTags(in: html)
        let siteName = meta["og:site_name"].map(clean) ?? hostName(url)

        if let r = jsonLDRecipes(in: html).first {
            var recipe = ParsedRecipe(title: clean(string(r["name"]) ?? meta["og:title"] ?? ""), sourceURL: url)
            recipe.siteName = siteName ?? (r["publisher"] as? [String: Any]).flatMap { string($0["name"]) }
            recipe.summary = string(r["description"]).map(clean).flatMap { $0.isEmpty ? nil : $0 }
            recipe.imageURL = image(r["image"], base: url) ?? meta["og:image"].flatMap { URL(string: $0, relativeTo: url)?.absoluteURL }
            recipe.ingredients = strings(r["recipeIngredient"] ?? r["ingredients"]).map(clean).filter { !$0.isEmpty }
            recipe.steps = instructions(r["recipeInstructions"])
            recipe.prepMinutes = minutes(string(r["prepTime"]))
            recipe.cookMinutes = minutes(string(r["cookTime"]))
            recipe.totalMinutes = minutes(string(r["totalTime"]))
            if recipe.totalMinutes == 0 { recipe.totalMinutes = recipe.prepMinutes + recipe.cookMinutes }
            recipe.servings = servings(r["recipeYield"])
            if recipe.title.isEmpty { recipe.title = titleTag(in: html) ?? siteName ?? "Recipe" }
            return recipe
        }

        // No recipe data: fall back to the link preview.
        guard let title = (meta["og:title"] ?? meta["twitter:title"] ?? titleTag(in: html)).map(clean), !title.isEmpty else {
            return nil
        }
        var recipe = ParsedRecipe(title: title, sourceURL: url)
        recipe.siteName = siteName
        recipe.summary = (meta["og:description"] ?? meta["description"]).map(clean)
        recipe.imageURL = (meta["og:image"] ?? meta["og:image:url"] ?? meta["twitter:image"])
            .flatMap { URL(string: $0, relativeTo: url)?.absoluteURL }
        return recipe
    }

    // MARK: - JSON-LD

    static func jsonLDRecipes(in html: String) -> [[String: Any]] {
        let pattern = #"<script[^>]*type\s*=\s*["']?application/ld\+json["']?[^>]*>([\s\S]*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = html as NSString
        var found: [[String: Any]] = []
        for m in regex.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let body = ns.substring(with: m.range(at: 1))
            guard let json = decodeJSON(body) else { continue }
            collectRecipes(json, into: &found)
        }
        return found
    }

    private static func decodeJSON(_ text: String) -> Any? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("<!--") { t = String(t.dropFirst(4)) }
        if t.hasSuffix("-->") { t = String(t.dropLast(3)) }
        if t.hasPrefix("//<![CDATA[") { t = String(t.dropFirst(11)) }
        if t.hasSuffix("//]]>") { t = String(t.dropLast(5)) }
        if let data = t.data(using: .utf8), let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            return json
        }
        // Some sites put raw line breaks/tabs inside strings, which isn't valid JSON.
        let relaxed = t.replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")
        return relaxed.data(using: .utf8).flatMap { try? JSONSerialization.jsonObject(with: $0, options: [.fragmentsAllowed]) }
    }

    private static func collectRecipes(_ json: Any, into found: inout [[String: Any]], depth: Int = 0) {
        guard depth < 6 else { return }
        if let array = json as? [Any] {
            for item in array { collectRecipes(item, into: &found, depth: depth + 1) }
        } else if let dict = json as? [String: Any] {
            if isType(dict["@type"], "Recipe") { found.append(dict); return }
            for key in ["@graph", "mainEntity", "mainEntityOfPage", "itemListElement", "item"] {
                if let child = dict[key] { collectRecipes(child, into: &found, depth: depth + 1) }
            }
        }
    }

    private static func isType(_ value: Any?, _ type: String) -> Bool {
        if let s = value as? String { return s == type || s.hasSuffix("/\(type)") }
        if let a = value as? [Any] { return a.contains { isType($0, type) } }
        return false
    }

    // MARK: - Fields

    private static func string(_ value: Any?) -> String? {
        switch value {
        case let s as String: s
        case let n as NSNumber: n.stringValue
        case let a as [Any]: a.lazy.compactMap { string($0) }.first
        case let d as [String: Any]: string(d["@value"] ?? d["text"] ?? d["name"])
        default: nil
        }
    }

    private static func strings(_ value: Any?) -> [String] {
        switch value {
        case let s as String: s.components(separatedBy: .newlines)
        case let a as [Any]: a.compactMap { string($0) }
        default: []
        }
    }

    private static func image(_ value: Any?, base: URL) -> URL? {
        let raw: String? = switch value {
        case let s as String: s
        case let a as [Any]: a.lazy.compactMap { v -> String? in
            if let s = v as? String { return s }
            return (v as? [String: Any]).flatMap { string($0["url"] ?? $0["contentUrl"]) }
        }.first
        case let d as [String: Any]: string(d["url"] ?? d["contentUrl"])
        default: nil
        }
        return raw.flatMap { URL(string: $0.trimmingCharacters(in: .whitespaces), relativeTo: base)?.absoluteURL }
    }

    /// Flattens HowToStep / HowToSection / plain strings into lines.
    static func instructions(_ value: Any?) -> [String] {
        var lines: [String] = []
        func walk(_ v: Any?) {
            switch v {
            case let s as String:
                // A single HTML/text blob: split into paragraphs or list items.
                let parts = s.replacingOccurrences(of: #"(?i)</?(li|p|br)\s*/?>"#, with: "\n", options: .regularExpression)
                    .components(separatedBy: .newlines)
                lines += parts.map(clean).filter { !$0.isEmpty }
            case let a as [Any]:
                a.forEach(walk)
            case let d as [String: Any]:
                if isType(d["@type"], "HowToSection") {
                    if let name = string(d["name"]).map(clean), !name.isEmpty { lines.append("## \(name)") }
                    walk(d["itemListElement"])
                } else if let items = d["itemListElement"] {
                    walk(items)
                } else if let text = string(d["text"]) ?? string(d["name"]) {
                    let t = clean(text)
                    if !t.isEmpty { lines.append(t) }
                }
            default:
                break
            }
        }
        walk(value)
        // Drop step text that just repeats the previous line (some sites set name == text).
        return lines.enumerated().filter { $0.offset == 0 || $0.element != lines[$0.offset - 1] }.map(\.element)
    }

    /// ISO-8601 durations like "PT1H30M", "P0DT0H45M", "PT90M" → minutes.
    static func minutes(_ iso: String?) -> Int {
        guard let iso = iso?.uppercased(), iso.hasPrefix("P") else { return 0 }
        var total = 0.0
        var number = ""
        var inTime = false
        for ch in iso.dropFirst() {
            if ch == "T" { inTime = true; continue }
            if ch.isNumber || ch == "." { number.append(ch); continue }
            let n = Double(number) ?? 0
            number = ""
            switch ch {
            case "D": total += n * 24 * 60
            case "H": total += n * 60
            case "M": total += inTime ? n : n * 30 * 24 * 60
            case "S": total += n / 60
            default: break
            }
        }
        return Int(total.rounded())
    }

    private static func servings(_ value: Any?) -> String? {
        let options = (value as? [Any] ?? [value as Any]).compactMap { string($0) }.map(clean).filter { !$0.isEmpty }
        // Prefer "4 servings" over a bare "4".
        if let words = options.first(where: { $0.contains(where: \.isLetter) }) { return words }
        return options.first.map { "Serves \($0)" }
    }

    // MARK: - HTML helpers

    static func metaTags(in html: String) -> [String: String] {
        guard let tag = try? NSRegularExpression(pattern: #"<meta\s[^>]*>"#, options: [.caseInsensitive]),
              let attr = try? NSRegularExpression(pattern: #"([a-zA-Z:_-]+)\s*=\s*("([^"]*)"|'([^']*)')"#)
        else { return [:] }
        let ns = html as NSString
        var result: [String: String] = [:]
        for m in tag.matches(in: html, range: NSRange(location: 0, length: ns.length)) {
            let t = ns.substring(with: m.range) as NSString
            var attrs: [String: String] = [:]
            for a in attr.matches(in: t as String, range: NSRange(location: 0, length: t.length)) {
                let key = t.substring(with: a.range(at: 1)).lowercased()
                let r = a.range(at: 3).location != NSNotFound ? a.range(at: 3) : a.range(at: 4)
                attrs[key] = t.substring(with: r)
            }
            if let key = (attrs["property"] ?? attrs["name"])?.lowercased(), let content = attrs["content"], result[key] == nil {
                result[key] = decodeEntities(content)
            }
        }
        return result
    }

    private static func titleTag(in html: String) -> String? {
        guard let r = html.range(of: #"<title[^>]*>([\s\S]*?)</title>"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        let inner = html[r].replacingOccurrences(of: #"</?title[^>]*>"#, with: "", options: [.regularExpression, .caseInsensitive])
        return clean(inner)
    }

    private static func hostName(_ url: URL) -> String? {
        guard var host = url.host() else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }

    /// Strips tags, decodes entities, collapses whitespace.
    static func clean(_ text: String) -> String {
        let noTags = text.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
        return decodeEntities(noTags)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let named: [String: String] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": " ", "ndash": "–", "mdash": "—",
            "hellip": "…", "rsquo": "’", "lsquo": "‘", "rdquo": "”", "ldquo": "“", "deg": "°", "frac12": "½",
            "frac14": "¼", "frac34": "¾", "times": "×", "eacute": "é", "egrave": "è", "ntilde": "ñ", "copy": "©", "reg": "®",
        ]
        var out = ""
        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "&", let semi = text[i...].prefix(12).firstIndex(of: ";") {
                let name = text[text.index(after: i)..<semi]
                var replacement: String?
                if name.hasPrefix("#x") || name.hasPrefix("#X") {
                    replacement = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else if name.hasPrefix("#") {
                    replacement = UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else {
                    replacement = named[String(name)]
                }
                if let replacement {
                    out += replacement
                    i = text.index(after: semi)
                    continue
                }
            }
            out.append(text[i])
            i = text.index(after: i)
        }
        return out
    }
}
