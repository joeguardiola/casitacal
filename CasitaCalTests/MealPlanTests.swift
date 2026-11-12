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

@MainActor
struct MealSidesTests {
    let persistence = Persistence(inMemory: true)
    let day = "2026-11-12"

    func recipe(_ title: String, side: Bool = false) -> CDRecipe {
        let r = persistence.insert(CDRecipe.self)
        r.id = UUID()
        r.title = title
        r.isSide = side
        return r
    }

    var dinner: CDMeal? { MealPlan.meal(day: day, context: persistence.context) }

    @Test func aMealCanStartFromASide() {
        MealPlan.addSide(title: "Salad", day: day, persistence: persistence)
        #expect(dinner?.mainTitle == "")
        #expect(dinner?.sideTitles == ["Salad"])
        #expect(dinner?.displayTitle == "+ Salad") // reads as a side, not the main
        #expect(dinner?.isPlanned == true)
        #expect(MealPlan.dinnerTitle(day: day, context: persistence.context) == nil) // nothing to replace
    }

    @Test func aMainAddedLaterKeepsTheSides() {
        MealPlan.addSide(title: "Salad", day: day, persistence: persistence)
        MealPlan.plan(recipe("Lasagna"), day: day, slot: .dinner, persistence: persistence)
        #expect(dinner?.displayTitle == "Lasagna")
        #expect(dinner?.sideTitles == ["Salad"])
        #expect(MealSides.summary(dinner!, short: false) == "with Salad")
    }

    @Test func planningASideRecipeNeverReplacesTheMain() {
        MealPlan.planDinner(title: "Tacos", day: day, persistence: persistence)
        let rice = recipe("Rice", side: true)
        MealPlan.plan(rice, day: day, slot: .dinner, persistence: persistence)
        MealPlan.plan(rice, day: day, slot: .dinner, persistence: persistence) // not twice
        #expect(dinner?.mainTitle == "Tacos")
        #expect(dinner?.sortedSides.map(\.recipe) == [rice])
    }

    @Test func sidesOnlyTitleListsThemAll() {
        MealPlan.addSide(title: "Salad", day: day, persistence: persistence)
        MealPlan.addSide(title: "Rolls", day: day, persistence: persistence)
        #expect(dinner?.displayTitle == "+ Salad, Rolls")
        #expect(MealSides.summary(dinner!, short: true) == "+ Salad, Rolls")
        #expect(MealSides.spoken(dinner!) == "No main yet, with " + ["Salad", "Rolls"].formatted(.list(type: .and)))
    }

    @Test func photoComesFromASideOnlyWithoutAMain() {
        let bread = recipe("Bread", side: true)
        bread.imageData = Data([1])
        MealPlan.plan(bread, day: day, slot: .dinner, persistence: persistence)
        #expect(dinner?.photoRecipe == bread)
        MealPlan.planDinner(title: "Soup", day: day, persistence: persistence)
        #expect(dinner?.photoRecipe == nil)
    }

    @Test func existingSideOnlyRecipesGetTagged() throws {
        let defaults = try #require(UserDefaults(suiteName: "MealSidesTests-\(UUID().uuidString)"))
        let salad = recipe("Salad")
        let tacos = recipe("Tacos")
        let both = recipe("Mac and cheese")
        MealPlan.addSide(title: "Salad", recipe: salad, day: day, persistence: persistence)
        MealPlan.planMain(title: "Tacos", recipe: tacos, day: day, slot: .dinner, persistence: persistence)
        MealPlan.addSide(title: "Mac", recipe: both, day: day, persistence: persistence)
        MealPlan.planMain(title: "Mac", recipe: both, day: "2026-11-13", slot: .dinner, persistence: persistence)
        MealPlan.tagExistingSides(persistence: persistence, defaults: defaults)
        #expect(salad.isSide)
        #expect(!tacos.isSide)
        #expect(!both.isSide)
    }
}

struct DishListTests {
    func split(_ s: String) -> [String]? {
        DishList.split(s).map { [$0.main] + $0.sides }
    }

    @Test func saturdaysLunch() {
        #expect(split("Chicken soup, slice of Colby jack, blackberries and 2 saltines")
                == ["Chicken soup", "Slice of Colby jack", "Blackberries", "2 saltines"])
    }

    @Test func oneDishStaysWhole() {
        #expect(split("Mac and cheese") == nil)
        #expect(split("Rice and beans") == nil)
        #expect(split("Chicken & dumplings") == nil)
        #expect(split("Salmon Piccata (Ready in 20 Minutes)") == nil)
        #expect(split("Leftovers") == nil)
    }

    @Test func withStartsTheSides() {
        #expect(split("Steak with salad, rolls") == ["Steak", "Salad", "Rolls"])
        #expect(split("Pork chops with mac and cheese") == ["Pork chops", "Mac and cheese"])
        #expect(split("Tacos with rice, beans and guacamole") == ["Tacos", "Rice", "Beans", "Guacamole"])
    }

    @Test func otherSeparators() {
        #expect(split("Burgers + fries") == ["Burgers", "Fries"])
        #expect(split("Mac and cheese, peas") == ["Mac and cheese", "Peas"])
        #expect(split("Chili; cornbread") == ["Chili", "Cornbread"])
    }

    @Test func parenthesesStayTogether() {
        #expect(split("Curry (mild, with rice)") == nil)
        #expect(split("Curry (mild, spicy), naan") == ["Curry (mild, spicy)", "Naan"])
    }

    @Test @MainActor func typedListShowsAsMainAndSides() {
        let p = Persistence(inMemory: true)
        let m = p.insert(CDMeal.self)
        m.id = UUID()
        m.title = "Soup, crackers and fruit"
        #expect(m.plate.main == "Soup")
        #expect(m.plate.sides == ["Crackers", "Fruit"])
        #expect(m.displayTitle == "Soup")
        // A saved recipe's name is never split.
        let r = p.insert(CDRecipe.self)
        r.id = UUID()
        r.title = "Soup, crackers and fruit"
        m.recipe = r
        #expect(m.plate.main == "Soup, crackers and fruit")
    }
}
