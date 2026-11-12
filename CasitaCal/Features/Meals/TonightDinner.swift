import CoreData
import SwiftUI

/// "Tonight's dinner: Chicken Chasseur" with the recipe photo, on the slideshow.
/// After 8 PM it shows tomorrow's dinner instead. Hidden when nothing is planned.
struct TonightDinnerCard: View {
    var body: some View {
        TimelineView(.everyMinute) { ctx in
            let showTomorrow = Calendar.app.component(.hour, from: ctx.date) >= 20
            let day = showTomorrow ? Calendar.app.date(byAdding: .day, value: 1, to: ctx.date) ?? ctx.date : ctx.date
            DinnerLookup(day: DayKey.from(day), label: showTomorrow ? "Tomorrow" : "Tonight")
        }
    }
}

private struct DinnerLookup: View {
    let day: String
    let label: String

    @FetchRequest private var meals: FetchedResults<CDMeal>

    init(day: String, label: String) {
        self.day = day
        self.label = label
        _meals = FetchRequest(sortDescriptors: [],
                              predicate: NSPredicate(format: "day == %@ AND slot == %@", day, MealSlot.dinner.rawValue))
    }

    var body: some View {
        if let meal = meals.first, let title = meal.displayTitle {
            slideshowCard(meal, title)
        }
    }

    private func slideshowCard(_ meal: CDMeal, _ title: String) -> some View {
        HStack(spacing: 14) {
            if let photo = meal.photoRecipe {
                RecipePhoto(recipe: photo)
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.6), lineWidth: 2))
            } else {
                Text(MealSlot.dinner.emoji).font(.system(size: 44))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.plate.main.isEmpty ? "\(label)'s sides" : "\(label)'s dinner").font(.headline).opacity(0.85)
                Text(title).font(.title2.weight(.bold)).lineLimit(2)
            }
        }
        .padding(.top, 10)
    }
}
