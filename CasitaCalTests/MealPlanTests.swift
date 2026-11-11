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

    // MARK: Sides

    func recipe(_ title: String) -> CDRecipe {
        let r = persistence.insert(CDRecipe.self)
        r.id = UUID()
        r.title = title
        return r
    }

    func sides(_ day: String) -> [String] {
        MealPlan.meal(day: day, context: persistence.context)?.sortedSides.compactMap(\.title) ?? []
    }

    @Test func sidesNeedADinner() {
        #expect(!MealPlan.addSide(title: "Salad", day: "2026-11-09", persistence: persistence))
    }

    @Test func sidesAddInOrder() {
        meal("Tacos", "2026-11-09", "dinner")
        MealPlan.addSide(title: "Rice", day: "2026-11-09", persistence: persistence)
        MealPlan.addSide(title: "Beans", recipe: recipe("Charro beans"), day: "2026-11-09", persistence: persistence)
        #expect(sides("2026-11-09") == ["Rice", "Beans"])
        #expect(MealPlan.meal(day: "2026-11-09", context: persistence.context)?.sortedSides.last?.recipe?.title == "Charro beans")
    }

    @Test func sidesMoveWithTheirMeal() throws {
        let tacos = meal("Tacos", "2026-11-09", "dinner")
        meal("Soup", "2026-11-10", "dinner")
        MealPlan.addSide(title: "Rice", day: "2026-11-09", persistence: persistence)
        MealPlan.addSide(title: "Bread", day: "2026-11-10", persistence: persistence)
        _ = try move(tacos, "2026-11-10", "dinner")
        #expect(sides("2026-11-10") == ["Rice"])
        #expect(sides("2026-11-09") == ["Bread"])
    }

    @Test func clearingAMealClearsItsSides() throws {
        let tacos = meal("Tacos", "2026-11-09", "dinner")
        MealPlan.addSide(title: "Rice", day: "2026-11-09", persistence: persistence)
        persistence.context.delete(tacos)
        persistence.save()
        let request = NSFetchRequest<CDMealSide>(entityName: "CDMealSide")
        #expect(try persistence.context.count(for: request) == 0)
    }

    @Test func planningADinnerLinksTheRecipeAndKeepsSides() {
        meal("Tacos", "2026-11-09", "dinner")
        MealPlan.addSide(title: "Rice", day: "2026-11-09", persistence: persistence)
        let pie = recipe("Shepherd's pie")
        MealPlan.planDinner(title: "Shepherd's pie", recipe: pie, day: "2026-11-09", persistence: persistence)
        let dinner = MealPlan.meal(day: "2026-11-09", context: persistence.context)
        #expect(dinner?.title == "Shepherd's pie")
        #expect(dinner?.recipe == pie)
        #expect(pie.lastPlannedAt != nil)
        #expect(sides("2026-11-09") == ["Rice"])
    }

    @Test func deletingARecipeKeepsTheSide() {
        meal("Tacos", "2026-11-09", "dinner")
        let beans = recipe("Charro beans")
        MealPlan.addSide(title: "Beans", recipe: beans, day: "2026-11-09", persistence: persistence)
        persistence.context.delete(beans)
        persistence.save()
        #expect(sides("2026-11-09") == ["Beans"])
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
