import CoreData

/// Folds extra households on this device into one, for Settings → Household.
///
/// Extra households came from debug builds mixing CloudKit test data into the real database, and
/// from a fresh install making a starter household before iCloud finished downloading. The
/// household with the most in it is kept. From the others: people already in the kept household
/// (same name) and the untouched starter family are removed, everything else (meals, recipes,
/// lists, chores, feast pins) moves over, skipping exact duplicates, and the empty households are
/// deleted. Nothing happens until `apply` (the button), and the summary says what will change.
@MainActor
struct HouseholdMerge {
    let keep: CDHousehold
    let others: [CDHousehold]

    /// A merge plan when this device holds more than one household in the same store; nil otherwise.
    static func plan(context: NSManagedObjectContext) -> HouseholdMerge? {
        let request = NSFetchRequest<CDHousehold>(entityName: "CDHousehold")
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]
        let all = (try? context.fetch(request)) ?? []
        guard let keep = all.max(by: { score($0) < score($1) || (score($0) == score($1) && isNewer($0, than: $1)) })
        else { return nil }
        // Relationships can't cross stores, so only households in the kept one's store are merged.
        let others = all.filter { $0 != keep && $0.objectID.persistentStore == keep.objectID.persistentStore }
        return others.isEmpty ? nil : HouseholdMerge(keep: keep, others: others)
    }

    // MARK: What it will do

    struct Summary: Equatable {
        var keptName: String
        var keptCounts: String
        var movedIn: [String]
        var removedPeople: [String]
        var removedHouseholds: Int
    }

    var summary: Summary {
        var moved: [String] = []
        var removedPeople: [String] = []
        for other in others {
            for m in members(of: other) {
                if isDuplicate(m) || isStarter(m) { removedPeople.append(m.name ?? "") } else { moved.append(m.name ?? "") }
            }
            moved += recipes(of: other).filter { duplicateRecipe(of: $0) == nil }.compactMap(\.title)
            moved += lists(of: other).map { "\($0.title ?? "") list" }
            moved += meals(of: other).filter { mealAt($0.day, $0.slot) == nil }.compactMap(\.title)
            moved += chores(of: other).filter { !hasChore(titled: $0.title) }.compactMap(\.title)
        }
        return Summary(
            keptName: keep.name ?? "Household",
            keptCounts: Self.counts(keep),
            movedIn: moved.filter { !$0.isEmpty },
            removedPeople: removedPeople.filter { !$0.isEmpty },
            removedHouseholds: others.count
        )
    }

    // MARK: Doing it

    func apply(persistence: Persistence) {
        let context = persistence.context
        for other in others {
            for m in members(of: other) {
                if isDuplicate(m) || isStarter(m) { context.delete(m) } else { m.household = keep }
            }
            for r in recipes(of: other) {
                if let same = duplicateRecipe(of: r) {
                    for meal in (r.meals as? Set<CDMeal>) ?? [] { meal.recipe = same }
                    for side in (r.sides as? Set<CDMealSide>) ?? [] { side.recipe = same }
                    context.delete(r)
                } else {
                    r.household = keep
                }
            }
            for list in lists(of: other) {
                if let same = lists(of: keep).first(where: { sameText($0.title, list.title) }) {
                    for item in (list.items as? Set<CDListItem>) ?? [] { item.list = same }
                    context.delete(list)
                } else {
                    list.household = keep
                }
            }
            for meal in meals(of: other) {
                if mealAt(meal.day, meal.slot) != nil { context.delete(meal) } else { meal.household = keep }
            }
            for chore in chores(of: other) {
                if hasChore(titled: chore.title) { context.delete(chore) } else { chore.household = keep }
            }
            for pin in (other.feastPins as? Set<CDFeastPin>) ?? [] {
                let taken = ((keep.feastPins as? Set<CDFeastPin>) ?? []).contains { $0.day == pin.day && $0.feastID == pin.feastID }
                if taken { context.delete(pin) } else { pin.household = keep }
            }
            context.delete(other)
        }
        persistence.save()
        persistence.refreshAfterSharing()
    }

    // MARK: Helpers

    private static func score(_ h: CDHousehold) -> Int {
        [h.members, h.meals, h.recipes, h.lists, h.chores, h.feastPins].reduce(0) { $0 + ($1?.count ?? 0) }
    }

    private static func isNewer(_ a: CDHousehold, than b: CDHousehold) -> Bool {
        (a.createdAt ?? .distantPast) > (b.createdAt ?? .distantPast)
    }

    private static func counts(_ h: CDHousehold) -> String {
        func n(_ count: Int, _ one: String, _ many: String) -> String? { count == 0 ? nil : "\(count) \(count == 1 ? one : many)" }
        return [n(h.members?.count ?? 0, "person", "people"), n(h.meals?.count ?? 0, "meal", "meals"),
                n(h.recipes?.count ?? 0, "recipe", "recipes"), n(h.lists?.count ?? 0, "list", "lists"),
                n(h.chores?.count ?? 0, "chore", "chores")].compactMap { $0 }.joined(separator: ", ")
    }

    private func members(of h: CDHousehold) -> [CDMember] { ((h.members as? Set<CDMember>) ?? []).sorted { ($0.sortOrder, $0.name ?? "") < ($1.sortOrder, $1.name ?? "") } }
    private func recipes(of h: CDHousehold) -> [CDRecipe] { ((h.recipes as? Set<CDRecipe>) ?? []).sorted { ($0.title ?? "") < ($1.title ?? "") } }
    private func lists(of h: CDHousehold) -> [CDList] { ((h.lists as? Set<CDList>) ?? []).sorted { $0.sortOrder < $1.sortOrder } }
    private func meals(of h: CDHousehold) -> [CDMeal] { ((h.meals as? Set<CDMeal>) ?? []).sorted { ($0.day ?? "") < ($1.day ?? "") } }
    private func chores(of h: CDHousehold) -> [CDChore] { ((h.chores as? Set<CDChore>) ?? []).sorted { $0.sortOrder < $1.sortOrder } }

    private func sameText(_ a: String?, _ b: String?) -> Bool {
        let fold = { (s: String?) in (s ?? "").trimmingCharacters(in: .whitespaces).lowercased() }
        return !fold(a).isEmpty && fold(a) == fold(b)
    }

    /// Already in the kept household under the same name.
    private func isDuplicate(_ m: CDMember) -> Bool { members(of: keep).contains { sameText($0.name, m.name) } }

    /// One of the untouched placeholder people a fresh install starts with.
    private func isStarter(_ m: CDMember) -> Bool {
        MemberStore.starterFamily.contains { $0.name == m.name && $0.emoji == m.emoji }
    }

    private func duplicateRecipe(of r: CDRecipe) -> CDRecipe? {
        recipes(of: keep).first {
            if let url = r.sourceURL, !url.isEmpty { return $0.sourceURL == url }
            return ($0.sourceURL ?? "").isEmpty && sameText($0.title, r.title)
        }
    }

    private func mealAt(_ day: String?, _ slot: String?) -> CDMeal? {
        meals(of: keep).first { $0.day == day && $0.slot == slot }
    }

    private func hasChore(titled title: String?) -> Bool { chores(of: keep).contains { sameText($0.title, title) } }
}
