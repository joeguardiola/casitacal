import CoreData

/// Changes to the weekly meal plan that aren't tied to one screen.
enum MealPlan {
    /// The dinner planned for a day, if any.
    static func dinnerTitle(day: String, context: NSManagedObjectContext) -> String? {
        let request = NSFetchRequest<CDMeal>(entityName: "CDMeal")
        request.predicate = NSPredicate(format: "day == %@ AND slot == %@", day, MealSlot.dinner.rawValue)
        return (try? context.fetch(request))?.first?.title
    }

    /// Puts a dish with no recipe attached on a day's dinner, replacing whatever was planned there.
    @MainActor
    static func planDinner(title: String, day: String, persistence: Persistence) {
        let request = NSFetchRequest<CDMeal>(entityName: "CDMeal")
        request.predicate = NSPredicate(format: "day == %@ AND slot == %@", day, MealSlot.dinner.rawValue)
        let existing = (try? persistence.context.fetch(request)) ?? []
        let meal = existing.first ?? {
            let m = persistence.insert(CDMeal.self)
            m.id = UUID()
            m.day = day
            m.slot = MealSlot.dinner.rawValue
            m.household = persistence.household()
            return m
        }()
        meal.title = title
        meal.recipe = nil
        existing.dropFirst().forEach(persistence.context.delete)
        persistence.save()
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
