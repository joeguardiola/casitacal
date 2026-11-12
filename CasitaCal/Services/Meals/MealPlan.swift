import CoreData

/// Changes to the weekly meal plan that aren't tied to one screen.
enum MealPlan {
    /// The main dish planned for a day's dinner, if any (nil when there's nothing, or only sides).
    static func dinnerTitle(day: String, context: NSManagedObjectContext) -> String? {
        guard let main = meal(day: day, context: context)?.mainTitle, !main.isEmpty else { return nil }
        return main
    }

    /// The meal planned in a day's slot, if any.
    static func meal(day: String, slot: MealSlot = .dinner, context: NSManagedObjectContext) -> CDMeal? {
        let request = NSFetchRequest<CDMeal>(entityName: "CDMeal")
        request.predicate = NSPredicate(format: "day == %@ AND slot == %@", day, slot.rawValue)
        return (try? context.fetch(request))?.first
    }

    /// Puts a saved recipe on the plan: a side joins that meal's sides, a main replaces the
    /// main dish there (sides stay).
    @MainActor
    static func plan(_ recipe: CDRecipe, day: String, slot: MealSlot, persistence: Persistence) {
        if recipe.isSide {
            addSide(title: recipe.title ?? "", recipe: recipe, day: day, slot: slot, persistence: persistence)
        } else {
            planMain(title: recipe.title ?? "", recipe: recipe, day: day, slot: slot, persistence: persistence)
        }
    }

    /// Puts a dish on a day's dinner, replacing the main dish planned there. Sides stay.
    /// With no recipe, the dish goes on the plan as just a name.
    @MainActor
    static func planDinner(title: String, recipe: CDRecipe? = nil, day: String, persistence: Persistence) {
        planMain(title: title, recipe: recipe, day: day, slot: .dinner, persistence: persistence)
    }

    @MainActor
    static func planMain(title: String, recipe: CDRecipe?, day: String, slot: MealSlot, persistence: Persistence) {
        let request = NSFetchRequest<CDMeal>(entityName: "CDMeal")
        request.predicate = NSPredicate(format: "day == %@ AND slot == %@", day, slot.rawValue)
        let existing = (try? persistence.context.fetch(request)) ?? []
        let meal = existing.first ?? newMeal(day: day, slot: slot, persistence: persistence)
        meal.title = title
        meal.recipe = recipe
        recipe?.lastPlannedAt = Date()
        existing.dropFirst().forEach(persistence.context.delete)
        persistence.save()
    }

    /// Adds a side to a day's meal, starting the meal if nothing is planned yet (a main can come
    /// later). A recipe that's already a side there isn't added twice.
    @MainActor
    static func addSide(title: String, recipe: CDRecipe? = nil, day: String, slot: MealSlot = .dinner,
                        persistence: Persistence) {
        let meal = meal(day: day, slot: slot, context: persistence.context)
            ?? newMeal(day: day, slot: slot, persistence: persistence)
        let sides = meal.sortedSides
        let alreadyThere = sides.contains {
            if let recipe { return $0.recipe == recipe }
            return $0.recipe == nil && $0.title == title
        }
        if !alreadyThere {
            let side = persistence.insert(CDMealSide.self)
            side.id = UUID()
            side.createdAt = Date()
            side.title = title
            side.recipe = recipe
            side.sortOrder = Int16((sides.last?.sortOrder ?? -1) + 1)
            side.meal = meal
        }
        recipe?.lastPlannedAt = Date()
        persistence.save()
    }

    @MainActor
    static func newMeal(day: String, slot: MealSlot, persistence: Persistence) -> CDMeal {
        let m = persistence.insert(CDMeal.self)
        m.id = UUID()
        m.day = day
        m.slot = slot.rawValue
        m.household = persistence.household()
        return m
    }

    /// One time, after recipes learned main vs. side: recipes only ever planned as a side become sides.
    @MainActor
    static func tagExistingSides(persistence: Persistence, defaults: UserDefaults = .standard) {
        let key = "recipes.sidesTagged"
        guard !defaults.bool(forKey: key) else { return }
        let request = NSFetchRequest<CDRecipe>(entityName: "CDRecipe")
        request.predicate = NSPredicate(format: "course == nil AND sides.@count > 0 AND meals.@count == 0")
        for recipe in (try? persistence.context.fetch(request)) ?? [] { recipe.isSide = true }
        persistence.save()
        defaults.set(true, forKey: key)
    }

    /// Moves a planned meal to another day and slot. If that spot is taken, the meals trade places.
    /// Every record in the target spot moves, so nothing ends up hidden behind a duplicate.
    /// - Returns: `false` if nothing changed (unknown meal, or dropped where it already was).
    @discardableResult
    static func move(mealID: UUID, toDay day: String, slot: String, context: NSManagedObjectContext) throws -> Bool {
        let request = NSFetchRequest<CDMeal>(entityName: "CDMeal")
        request.predicate = NSPredicate(format: "id == %@", mealID as CVarArg)
        request.fetchLimit = 1
        guard let meal = try context.fetch(request).first else { return false }

        let fromDay = meal.day
        let fromSlot = meal.slot
        if fromDay == day && fromSlot == slot { return false }

        let occupants = NSFetchRequest<CDMeal>(entityName: "CDMeal")
        occupants.predicate = NSPredicate(format: "day == %@ AND slot == %@", day, slot)
        for other in try context.fetch(occupants) {
            other.day = fromDay
            other.slot = fromSlot
        }

        meal.day = day
        meal.slot = slot
        try context.save()
        return true
    }
}
