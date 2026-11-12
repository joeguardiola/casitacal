import CoreData
import Foundation
import Testing
@testable import CasitaCal

/// The kitchen iPad's real mess on 2026-11-11: the real household, an old test household, a
/// fresh-install starter household and the schema-setup leftover.
@MainActor
struct HouseholdMergeTests {
    let p = Persistence(inMemory: true)

    func household(_ name: String, daysAgo: Double) -> CDHousehold {
        let h = p.createHousehold(name: name)
        h.createdAt = Date(timeIntervalSinceNow: -daysAgo * 86_400)
        return h
    }

    @discardableResult
    func member(_ name: String, _ emoji: String, in h: CDHousehold) -> CDMember {
        let m = p.insert(CDMember.self)
        m.id = UUID(); m.name = name; m.emoji = emoji; m.colorId = "1"; m.household = h
        return m
    }

    func meal(_ title: String, _ day: String, _ slot: String, in h: CDHousehold) {
        let m = p.insert(CDMeal.self)
        m.id = UUID(); m.title = title; m.day = day; m.slot = slot; m.household = h
    }

    func recipe(_ title: String, in h: CDHousehold) {
        let r = p.insert(CDRecipe.self)
        r.id = UUID(); r.title = title; r.household = h
    }

    func list(_ title: String, in h: CDHousehold) {
        let l = p.insert(CDList.self)
        l.id = UUID(); l.title = title; l.household = h
    }

    func setUpKitchenIPad() -> (real: CDHousehold, test: CDHousehold) {
        let test = household("Our casita", daysAgo: 4)
        let real = household("Our casita", daysAgo: 3)
        let schema = household("Schema setup (safe to delete)", daysAgo: 1)
        let fresh = household("Our casita", daysAgo: 0)
        _ = schema
        for (n, e) in [("Joe", "🧔"), ("Jonah", "🧒"), ("Lauren", "👩")] { member(n, e, in: real) }
        meal("Salmon Piccata", "2026-11-10", "dinner", in: real)
        meal("Leftovers", "2026-11-09", "dinner", in: real)
        meal("Chicken soup", "2026-11-14", "lunch", in: real)
        recipe("Salmon Piccata", in: real)
        for (n, e) in [("Jonah", "🧒"), ("Lauren", "👩")] { member(n, e, in: test) }
        recipe("7-Can Soup", in: test)
        list("To-do", in: test)
        list("Groceries", in: test)
        for m in MemberStore.starterFamily { member(m.name, m.emoji, in: fresh) }
        p.save()
        return (real, test)
    }

    func count(_ entity: String) -> Int { (try? p.context.count(for: NSFetchRequest<NSManagedObject>(entityName: entity))) ?? -1 }

    @Test func keepsTheRealHousehold() throws {
        let (real, _) = setUpKitchenIPad()
        let plan = try #require(HouseholdMerge.plan(context: p.context))
        #expect(plan.keep == real)
        #expect(plan.others.count == 3)
    }

    @Test func mergeLeavesOneHouseholdWithEverything() throws {
        let (real, _) = setUpKitchenIPad()
        try #require(HouseholdMerge.plan(context: p.context)).apply(persistence: p)
        #expect(count("CDHousehold") == 1)
        #expect(p.activeHousehold == real)
        #expect(((real.members as? Set<CDMember>) ?? []).compactMap(\.name).sorted() == ["Joe", "Jonah", "Lauren"])
        #expect(count("CDMember") == 3)
        #expect(real.recipes?.count == 2)
        #expect(real.lists?.count == 2)
        #expect(real.meals?.count == 3)
        #expect(HouseholdMerge.plan(context: p.context) == nil) // nothing left to offer
    }

    @Test func duplicateRecipesAndMealsAreNotDoubled() throws {
        let real = household("Our casita", daysAgo: 3)
        let other = household("Our casita", daysAgo: 1)
        member("Joe", "🧔", in: real)
        meal("Tacos", "2026-11-12", "dinner", in: real)
        meal("Soup", "2026-11-12", "dinner", in: other)  // same spot: the kept one wins
        meal("Pancakes", "2026-11-13", "breakfast", in: other)
        recipe("Tacos", in: real)
        recipe("Tacos", in: other)
        p.save()
        try #require(HouseholdMerge.plan(context: p.context)).apply(persistence: p)
        #expect((real.meals as? Set<CDMeal>)?.compactMap(\.title).sorted() == ["Pancakes", "Tacos"])
        #expect(real.recipes?.count == 1)
    }

    @Test func oneHouseholdOffersNothing() {
        let h = household("Our casita", daysAgo: 1)
        member("Joe", "🧔", in: h)
        p.save()
        #expect(HouseholdMerge.plan(context: p.context) == nil)
    }
}
