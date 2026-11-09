import CoreData
import SwiftUI

/// "Tonight: Chicken Chasseur" with the recipe photo — on the dashboard header and the slideshow.
/// After 8 PM it shows tomorrow's dinner instead. Hidden when nothing is planned.
struct TonightDinnerCard: View {
    enum Style { case header, slideshow }
    var style: Style = .header

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            let showTomorrow = Calendar.app.component(.hour, from: ctx.date) >= 20
            let day = showTomorrow ? Calendar.app.date(byAdding: .day, value: 1, to: ctx.date) ?? ctx.date : ctx.date
            DinnerLookup(day: DayKey.from(day), label: showTomorrow ? "Tomorrow" : "Tonight", style: style)
        }
    }
}

private struct DinnerLookup: View {
    let day: String
    let label: String
    let style: TonightDinnerCard.Style

    @FetchRequest private var meals: FetchedResults<CDMeal>
    @State private var showingRecipe: CDRecipe?

    init(day: String, label: String, style: TonightDinnerCard.Style) {
        self.day = day
        self.label = label
        self.style = style
        _meals = FetchRequest(sortDescriptors: [],
                              predicate: NSPredicate(format: "day == %@ AND slot == %@", day, MealSlot.dinner.rawValue))
    }

    var body: some View {
        if let meal = meals.first, let title = meal.title, !title.isEmpty {
            switch style {
            case .header:
                Button { showingRecipe = meal.recipe } label: { headerCard(meal, title) }
                    .buttonStyle(.plain)
                    .allowsHitTesting(meal.recipe != nil) // not .disabled, which would grey out the card
                    .sheet(item: $showingRecipe) { RecipeView(recipe: $0) }
                    .accessibilityLabel("\(label)'s dinner: \(title)")
            case .slideshow:
                slideshowCard(meal, title)
            }
        }
    }

    private func headerCard(_ meal: CDMeal, _ title: String) -> some View {
        HStack(spacing: 10) {
            if meal.recipe?.imageData != nil {
                RecipePhoto(recipe: meal.recipe)
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Text(MealSlot.dinner.emoji).font(.system(size: 30)).frame(width: 52, height: 52)
                    .background(Palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("\(label)'s dinner").font(.caption.weight(.semibold)).foregroundStyle(Palette.inkSecondary).lineLimit(1).minimumScaleFactor(0.75)
                Text(title).font(.headline).foregroundStyle(Palette.ink).lineLimit(1)
            }
            .frame(maxWidth: 220, alignment: .leading)
        }
        .padding(6)
        .padding(.trailing, 8)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.hairline))
    }

    private func slideshowCard(_ meal: CDMeal, _ title: String) -> some View {
        HStack(spacing: 14) {
            if meal.recipe?.imageData != nil {
                RecipePhoto(recipe: meal.recipe)
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.6), lineWidth: 2))
            } else {
                Text(MealSlot.dinner.emoji).font(.system(size: 44))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(label)'s dinner").font(.headline).opacity(0.85)
                Text(title).font(.title2.weight(.bold)).lineLimit(2)
            }
        }
        .padding(.top, 10)
    }
}
