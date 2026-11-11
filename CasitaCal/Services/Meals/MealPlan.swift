import CoreData

/// Changes to the weekly meal plan that aren't tied to one screen.
enum MealPlan {
    /// The dinner planned for a day, if any.
    static func dinnerTitle(day: String, context: NSManagedObjectContext) -> String? {
        let request = NSFetchRequest<CDMeal>(entityName: "CDMeal")
        request.predicate = NSPredicate(format: "day == %@ AND slot == %@", day, MealSlot.dinner.rawValue)
        return (try? context.fetch(request))?.first?.title
    }

    /// The meal planned in a day's slot, if any.
    static func meal(day: String, slot: MealSlot = .dinner, context: NSManagedObjectContext) -> CDMeal? {
        let request = NSFetchRequest<CDMeal>(entityName: "CDMeal")
        request.predicate = NSPredicate(format: "day == %@ AND slot == %@", day, slot.rawValue)
        return (try? context.fetch(request))?.first
    }

    /// Puts a dish on a day's dinner, replacing the main dish planned there. Sides stay.
    /// With no recipe, the dish goes on the plan as just a name.
    @MainActor
    static func planDinner(title: String, recipe: CDRecipe? = nil, day: String, persistence: Persistence) {
        let request = NSFetchRequest<CDMeal>(entityName: "CDMeal")
        request.predicate = NSPredicate(format: "day == %@ AND slot == %@", day, MealSlot.dinner.rawValue)
        let existing = (try? persistence.context.fetch(request)) ?? []
        let meal = existing.first ?? newMeal(day: day, slot: .dinner, persistence: persistence)
        meal.title = title
        meal.recipe = recipe
        recipe?.lastPlannedAt = Date()
        existing.dropFirst().forEach(persistence.context.delete)
        persistence.save()
    }

    /// Adds a side to a day's dinner. Returns `false` when no dinner is planned that day.
    @MainActor
    @discardableResult
    static func addSide(title: String, recipe: CDRecipe? = nil, day: String, persistence: Persistence) -> Bool {
        guard let meal = meal(day: day, context: persistence.context), !(meal.title ?? "").isEmpty else { return false }
        let side = persistence.insert(CDMealSide.self)
        side.id = UUID()
        side.createdAt = Date()
        side.title = title
        side.recipe = recipe
        side.sortOrder = Int16((meal.sortedSides.last?.sortOrder ?? -1) + 1)
        side.meal = meal
        recipe?.lastPlannedAt = Date()
        persistence.save()
        return true
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
