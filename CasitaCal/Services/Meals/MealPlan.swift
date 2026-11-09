import CoreData

/// Changes to the weekly meal plan that aren't tied to one screen.
enum MealPlan {
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
