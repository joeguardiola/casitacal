import CoreData
import Foundation
import Testing
@testable import CasitaCal

@MainActor
struct MealPlanTests {
    let persistence = Persistence(inMemory: true)

    @discardableResult
    func meal(_ title: String, _ day: String, _ slot: String) -> CDMeal {
        let m = persistence.insert(CDMeal.self)
        m.id = UUID()
        m.title = title
        m.day = day
        m.slot = slot
        persistence.save()
        return m
    }

    func move(_ m: CDMeal, _ day: String, _ slot: String) throws -> Bool {
        try MealPlan.move(mealID: m.id!, toDay: day, slot: slot, context: persistence.context)
    }

    @Test func movesToAnEmptySpot() throws {
        let tacos = meal("Tacos", "2026-11-09", "lunch")
        #expect(try move(tacos, "2026-11-10", "dinner"))
        #expect(tacos.day == "2026-11-10" && tacos.slot == "dinner")
    }

    @Test func occupiedSpotSwaps() throws {
        let tacos = meal("Tacos", "2026-11-09", "lunch")
        let soup = meal("Soup", "2026-11-09", "dinner")
        #expect(try move(tacos, "2026-11-09", "dinner"))
        #expect(tacos.slot == "dinner")
        #expect(soup.slot == "lunch")
        #expect(soup.day == "2026-11-09")
    }

    @Test func sameSpotDoesNothing() throws {
        let tacos = meal("Tacos", "2026-11-09", "lunch")
        #expect(try !move(tacos, "2026-11-09", "lunch"))
        #expect(tacos.slot == "lunch")
    }

    @Test func duplicatesInTheTargetAllMove() throws {
        let tacos = meal("Tacos", "2026-11-09", "lunch")
        let a = meal("Soup", "2026-11-10", "dinner")
        let b = meal("Stew", "2026-11-10", "dinner")
        #expect(try move(tacos, "2026-11-10", "dinner"))
        #expect([a, b].allSatisfy { $0.day == "2026-11-09" && $0.slot == "lunch" })
    }

    @Test func unknownMealIsIgnored() throws {
        #expect(try !MealPlan.move(mealID: UUID(), toDay: "2026-11-09", slot: "dinner", context: persistence.context))
    }

    @Test func moveIsSaved() throws {
        let tacos = meal("Tacos", "2026-11-09", "lunch")
        _ = try move(tacos, "2026-11-12", "dinner")
        #expect(!persistence.context.hasChanges)
    }
}

struct RecipeSearchTests {
    let titles = ["Weeknight Tacos", "Taco Soup", "Crème Brûlée", "Chicken-Chasseur", "Potato Salad"]

    func search(_ q: String, limit: Int = 5) -> [String] {
        RecipeSearch.suggestions(for: q, in: titles, title: { $0 }, limit: limit)
    }

    @Test func blankMatchesNothing() {
        #expect(search("").isEmpty)
        #expect(search("   ").isEmpty)
    }

    @Test func titleStartBeatsWordStartBeatsInside() {
        #expect(search("taco") == ["Taco Soup", "Weeknight Tacos"])
        let items = ["Potato Salad", "Baked Tater Tots", "Tatsoi Stir Fry"]
        let ranked = RecipeSearch.suggestions(for: "tat", in: items, title: { $0 })
        #expect(ranked == ["Tatsoi Stir Fry", "Baked Tater Tots", "Potato Salad"])
    }

    @Test func ignoresCaseAndAccents() {
        #expect(search("creme") == ["Crème Brûlée"])
        #expect(search("BRULEE") == ["Crème Brûlée"])
    }

    @Test func wordsSplitOnPunctuation() {
        #expect(search("chass") == ["Chicken-Chasseur"])
    }

    @Test func respectsTheLimit() {
        #expect(search("a", limit: 2).count == 2)
    }

    @Test func keepsOriginalOrderWithinAGroup() {
        let items = ["Soup A", "Soup B", "Soup C"]
        #expect(RecipeSearch.suggestions(for: "soup", in: items, title: { $0 }) == items)
    }
}
