import CoreData
import Foundation
import UIKit

/// Downloads a recipe page + its photo, and saves recipes into the household recipe box.
enum RecipeImporter {
    enum ImportError: LocalizedError {
        case badLink, unreachable(Int), nothingFound
        var errorDescription: String? {
            switch self {
            case .badLink: "That doesn't look like a web link."
            case let .unreachable(code): "The site didn't let us read the page (error \(code)). You can still type the meal and keep the link."
            case .nothingFound: "Couldn't find a recipe on that page."
            }
        }
    }

    /// Pulls the first http(s) link out of pasted text ("Check this out https://…").
    static func firstLink(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.matches(in: text, range: range)
            .compactMap(\.url)
            .first { $0.scheme == "http" || $0.scheme == "https" }
    }

    private static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    static func fetch(_ url: URL) async throws -> (recipe: ParsedRecipe, image: Data?) {
        guard url.scheme == "http" || url.scheme == "https" else { throw ImportError.badLink }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 200
        guard (200..<300).contains(code) else { throw ImportError.unreachable(code) }
        let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        let finalURL = response.url ?? url
        guard let recipe = RecipeParser.parse(html: html, url: finalURL) else { throw ImportError.nothingFound }
        var image: Data?
        if let imageURL = recipe.imageURL { image = try? await downloadImage(imageURL) }
        return (recipe, image)
    }

    static func downloadImage(_ url: URL) async throws -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        return downscaledJPEG(data)
    }

    /// Recipe photos are stored with the recipe and sync through iCloud, so keep them small (~100–200 KB).
    static func downscaledJPEG(_ data: Data, maxPixel: CGFloat = 1200) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height) * image.scale
        let scale = min(1, maxPixel / max(longest, 1))
        let size = CGSize(width: image.size.width * image.scale * scale, height: image.size.height * image.scale * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.75)
    }

    // MARK: - Saving

    /// Saves (or refreshes) a recipe in the box. The same link is only stored once.
    @MainActor
    static func save(_ parsed: ParsedRecipe, image: Data?, persistence: Persistence) -> CDRecipe {
        let context = persistence.context
        let request = NSFetchRequest<CDRecipe>(entityName: "CDRecipe")
        request.predicate = NSPredicate(format: "sourceURL == %@", parsed.sourceURL.absoluteString)
        let recipe = (try? context.fetch(request).first) ?? {
            let r = persistence.insert(CDRecipe.self)
            r.id = UUID()
            r.createdAt = Date()
            r.household = persistence.household()
            return r
        }()
        recipe.title = parsed.title
        recipe.sourceURL = parsed.sourceURL.absoluteString
        recipe.siteName = parsed.siteName
        recipe.summary = parsed.summary
        recipe.imageURL = parsed.imageURL?.absoluteString
        if let image { recipe.imageData = image }
        recipe.ingredients = parsed.ingredients.joined(separator: "\n")
        recipe.steps = parsed.steps.joined(separator: "\n")
        recipe.prepMinutes = Int32(parsed.prepMinutes)
        recipe.cookMinutes = Int32(parsed.cookMinutes)
        recipe.totalMinutes = Int32(parsed.totalMinutes)
        recipe.servings = parsed.servings
        return recipe
    }

    /// Puts a recipe on the plan (replacing whatever was in that slot).
    @MainActor
    static func plan(_ recipe: CDRecipe, day: String, slot: String, persistence: Persistence) {
        let context = persistence.context
        let request = NSFetchRequest<CDMeal>(entityName: "CDMeal")
        request.predicate = NSPredicate(format: "day == %@ AND slot == %@", day, slot)
        let meal = (try? context.fetch(request).first) ?? {
            let m = persistence.insert(CDMeal.self)
            m.id = UUID()
            m.day = day
            m.slot = slot
            m.household = persistence.household()
            return m
        }()
        meal.title = recipe.title
        meal.recipe = recipe
        recipe.lastPlannedAt = Date()
    }
}

extension CDRecipe {
    var ingredientLines: [String] { (ingredients ?? "").split(separator: "\n").map(String.init) }
    var stepLines: [String] { (steps ?? "").split(separator: "\n").map(String.init) }
    var image: UIImage? { imageData.flatMap(UIImage.init(data:)) }
    var link: URL? { sourceURL.flatMap(URL.init(string:)) }

    /// "Prep 15 min · Cook 1 hr · Serves 4"
    var timingSummary: String {
        func fmt(_ m: Int32) -> String {
            let h = m / 60, mm = m % 60
            return h > 0 ? (mm > 0 ? "\(h) hr \(mm) min" : "\(h) hr") : "\(mm) min"
        }
        var parts: [String] = []
        if totalMinutes > 0 { parts.append(fmt(totalMinutes)) }
        else {
            if prepMinutes > 0 { parts.append("Prep \(fmt(prepMinutes))") }
            if cookMinutes > 0 { parts.append("Cook \(fmt(cookMinutes))") }
        }
        if let servings, !servings.isEmpty { parts.append(servings) }
        return parts.joined(separator: " · ")
    }
}
