import CoreData

// Core Data entities for household data that will sync through iCloud.
// CloudKit rules: every attribute optional or defaulted, every relationship optional
// with an inverse, no unique constraints. Days are stored as "yyyy-MM-dd" keys so they
// mean the same calendar day on every device.

@objc(CDHousehold)
final class CDHousehold: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var createdAt: Date?
    @NSManaged var members: NSSet?
    @NSManaged var chores: NSSet?
    @NSManaged var lists: NSSet?
    @NSManaged var meals: NSSet?
    @NSManaged var recipes: NSSet?
    @NSManaged var feastPins: NSSet?
}

@objc(CDMember)
final class CDMember: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var name: String?
    @NSManaged var emoji: String?
    @NSManaged var colorId: String?
    @NSManaged var role: String?
    /// Comma-separated.
    @NSManaged var nicknames: String?
    @NSManaged var sortOrder: Int16
    @NSManaged var household: CDHousehold?
}

@objc(CDChore)
final class CDChore: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var title: String?
    @NSManaged var emoji: String?
    /// Comma-separated member UUIDs. Empty = anyone.
    @NSManaged var assigneeIDs: String?
    /// "once" | "daily" | "days"
    @NSManaged var repeatKind: String?
    /// For "days": bit (weekday - 1), Sunday = bit 0 … Saturday = bit 6.
    @NSManaged var weekdayMask: Int16
    /// First day (or the due day for "once").
    @NSManaged var startDay: String?
    /// "morning" | "afternoon" | "evening" | "anytime"
    @NSManaged var timeOfDay: String?
    @NSManaged var stars: Int16
    @NSManaged var sortOrder: Int16
    @NSManaged var createdAt: Date?
    @NSManaged var household: CDHousehold?
    @NSManaged var completions: NSSet?
}

@objc(CDChoreCompletion)
final class CDChoreCompletion: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var day: String?
    /// Who did it ("" when the chore is for anyone).
    @NSManaged var memberID: String?
    @NSManaged var completedAt: Date?
    @NSManaged var chore: CDChore?
}

@objc(CDList)
final class CDList: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var title: String?
    @NSManaged var emoji: String?
    @NSManaged var sortOrder: Int16
    @NSManaged var createdAt: Date?
    @NSManaged var household: CDHousehold?
    @NSManaged var items: NSSet?
}

@objc(CDListItem)
final class CDListItem: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var title: String?
    @NSManaged var isDone: Bool
    @NSManaged var createdAt: Date?
    @NSManaged var completedAt: Date?
    @NSManaged var list: CDList?
}

@objc(CDMeal)
final class CDMeal: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var day: String?
    /// "breakfast" | "lunch" | "dinner" | "snack"
    @NSManaged var slot: String?
    @NSManaged var title: String?
    @NSManaged var notes: String?
    @NSManaged var household: CDHousehold?
    @NSManaged var recipe: CDRecipe?
    @NSManaged var sides: NSSet?
}

/// A side dish on a planned meal. Only the meal's own title (the main dish) shows on the calendar.
@objc(CDMealSide)
final class CDMealSide: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var title: String?
    @NSManaged var sortOrder: Int16
    @NSManaged var createdAt: Date?
    @NSManaged var meal: CDMeal?
    @NSManaged var recipe: CDRecipe?
}

/// A feast day someone added to the calendar. Shown at the bottom of that day; never sent to Google.
@objc(CDFeastPin)
final class CDFeastPin: NSManagedObject {
    @NSManaged var id: UUID?
    /// "yyyy-MM-dd"
    @NSManaged var day: String?
    /// `FeastEntry.id`
    @NSManaged var feastID: String?
    @NSManaged var title: String?
    @NSManaged var createdAt: Date?
    @NSManaged var household: CDHousehold?
}

extension CDMeal {
    var sortedSides: [CDMealSide] {
        ((sides as? Set<CDMealSide>) ?? []).sorted {
            ($0.sortOrder, $0.createdAt ?? .distantPast) < ($1.sortOrder, $1.createdAt ?? .distantPast)
        }
    }
}

/// A saved recipe (the recipe box). Imported from a link, or just a name + photo.
@objc(CDRecipe)
final class CDRecipe: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var title: String?
    @NSManaged var sourceURL: String?
    @NSManaged var siteName: String?
    @NSManaged var summary: String?
    /// Downscaled JPEG, stored with the recipe so it works offline and syncs (CloudKit asset).
    @NSManaged var imageData: Data?
    @NSManaged var imageURL: String?
    /// One ingredient per line.
    @NSManaged var ingredients: String?
    /// One step per line; lines starting with "## " are section headings.
    @NSManaged var steps: String?
    @NSManaged var prepMinutes: Int32
    @NSManaged var cookMinutes: Int32
    @NSManaged var totalMinutes: Int32
    @NSManaged var servings: String?
    @NSManaged var notes: String?
    @NSManaged var createdAt: Date?
    @NSManaged var lastPlannedAt: Date?
    @NSManaged var household: CDHousehold?
    @NSManaged var meals: NSSet?
    @NSManaged var sides: NSSet?
}

/// The Core Data model, built in code (keeps the schema reviewable in diffs).
enum CasitaModel {
    nonisolated(unsafe) static let shared: NSManagedObjectModel = build()

    private static func build() -> NSManagedObjectModel {
        func entity<T: NSManagedObject>(_ type: T.Type, _ attributes: [NSAttributeDescription]) -> NSEntityDescription {
            let e = NSEntityDescription()
            e.name = String(describing: type)
            e.managedObjectClassName = String(describing: type)
            e.properties = attributes
            return e
        }
        func attr(_ name: String, _ type: NSAttributeType, default value: Any? = nil) -> NSAttributeDescription {
            let a = NSAttributeDescription()
            a.name = name
            a.attributeType = type
            a.isOptional = value == nil
            a.defaultValue = value
            if type == .binaryDataAttributeType { a.allowsExternalBinaryDataStorage = true }
            return a
        }
        func link(_ from: NSEntityDescription, _ name: String, to: NSEntityDescription, toMany: Bool,
                  inverse: String, inverseToMany: Bool, cascade: Bool) {
            let r = NSRelationshipDescription()
            r.name = name
            r.destinationEntity = to
            r.isOptional = true
            r.minCount = 0
            r.maxCount = toMany ? 0 : 1
            r.deleteRule = cascade ? .cascadeDeleteRule : .nullifyDeleteRule
            let inv = NSRelationshipDescription()
            inv.name = inverse
            inv.destinationEntity = from
            inv.isOptional = true
            inv.minCount = 0
            inv.maxCount = inverseToMany ? 0 : 1
            inv.deleteRule = .nullifyDeleteRule
            r.inverseRelationship = inv
            inv.inverseRelationship = r
            from.properties.append(r)
            to.properties.append(inv)
        }

        let household = entity(CDHousehold.self, [
            attr("id", .UUIDAttributeType), attr("name", .stringAttributeType), attr("createdAt", .dateAttributeType),
        ])
        let member = entity(CDMember.self, [
            attr("id", .UUIDAttributeType), attr("name", .stringAttributeType), attr("emoji", .stringAttributeType),
            attr("colorId", .stringAttributeType), attr("role", .stringAttributeType),
            attr("nicknames", .stringAttributeType), attr("sortOrder", .integer16AttributeType, default: 0),
        ])
        let chore = entity(CDChore.self, [
            attr("id", .UUIDAttributeType), attr("title", .stringAttributeType), attr("emoji", .stringAttributeType),
            attr("assigneeIDs", .stringAttributeType), attr("repeatKind", .stringAttributeType),
            attr("weekdayMask", .integer16AttributeType, default: 0), attr("startDay", .stringAttributeType),
            attr("timeOfDay", .stringAttributeType), attr("stars", .integer16AttributeType, default: 1),
            attr("sortOrder", .integer16AttributeType, default: 0), attr("createdAt", .dateAttributeType),
        ])
        let completion = entity(CDChoreCompletion.self, [
            attr("id", .UUIDAttributeType), attr("day", .stringAttributeType),
            attr("memberID", .stringAttributeType), attr("completedAt", .dateAttributeType),
        ])
        let list = entity(CDList.self, [
            attr("id", .UUIDAttributeType), attr("title", .stringAttributeType), attr("emoji", .stringAttributeType),
            attr("sortOrder", .integer16AttributeType, default: 0), attr("createdAt", .dateAttributeType),
        ])
        let item = entity(CDListItem.self, [
            attr("id", .UUIDAttributeType), attr("title", .stringAttributeType),
            attr("isDone", .booleanAttributeType, default: false),
            attr("createdAt", .dateAttributeType), attr("completedAt", .dateAttributeType),
        ])
        let meal = entity(CDMeal.self, [
            attr("id", .UUIDAttributeType), attr("day", .stringAttributeType), attr("slot", .stringAttributeType),
            attr("title", .stringAttributeType), attr("notes", .stringAttributeType),
        ])

        let recipe = entity(CDRecipe.self, [
            attr("id", .UUIDAttributeType), attr("title", .stringAttributeType), attr("sourceURL", .stringAttributeType),
            attr("siteName", .stringAttributeType), attr("summary", .stringAttributeType),
            attr("imageData", .binaryDataAttributeType), attr("imageURL", .stringAttributeType),
            attr("ingredients", .stringAttributeType), attr("steps", .stringAttributeType),
            attr("prepMinutes", .integer32AttributeType, default: 0), attr("cookMinutes", .integer32AttributeType, default: 0),
            attr("totalMinutes", .integer32AttributeType, default: 0), attr("servings", .stringAttributeType),
            attr("notes", .stringAttributeType), attr("createdAt", .dateAttributeType), attr("lastPlannedAt", .dateAttributeType),
        ])

        let side = entity(CDMealSide.self, [
            attr("id", .UUIDAttributeType), attr("title", .stringAttributeType),
            attr("sortOrder", .integer16AttributeType, default: 0), attr("createdAt", .dateAttributeType),
        ])
        let feastPin = entity(CDFeastPin.self, [
            attr("id", .UUIDAttributeType), attr("day", .stringAttributeType), attr("feastID", .stringAttributeType),
            attr("title", .stringAttributeType), attr("createdAt", .dateAttributeType),
        ])

        link(household, "members", to: member, toMany: true, inverse: "household", inverseToMany: false, cascade: true)
        link(household, "chores", to: chore, toMany: true, inverse: "household", inverseToMany: false, cascade: true)
        link(household, "lists", to: list, toMany: true, inverse: "household", inverseToMany: false, cascade: true)
        link(household, "meals", to: meal, toMany: true, inverse: "household", inverseToMany: false, cascade: true)
        link(chore, "completions", to: completion, toMany: true, inverse: "chore", inverseToMany: false, cascade: true)
        link(list, "items", to: item, toMany: true, inverse: "list", inverseToMany: false, cascade: true)
        link(household, "recipes", to: recipe, toMany: true, inverse: "household", inverseToMany: false, cascade: true)
        // Deleting a recipe keeps the planned meals (they just lose the link).
        link(recipe, "meals", to: meal, toMany: true, inverse: "recipe", inverseToMany: false, cascade: false)
        // Clearing a meal clears its sides; deleting a recipe keeps the side (it just loses the link).
        link(meal, "sides", to: side, toMany: true, inverse: "meal", inverseToMany: false, cascade: true)
        link(recipe, "sides", to: side, toMany: true, inverse: "recipe", inverseToMany: false, cascade: false)
        link(household, "feastPins", to: feastPin, toMany: true, inverse: "household", inverseToMany: false, cascade: true)

        let model = NSManagedObjectModel()
        model.entities = [household, member, chore, completion, list, item, meal, recipe, side, feastPin]
        return model
    }
}
