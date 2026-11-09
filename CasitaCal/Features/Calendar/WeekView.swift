import CoreData
import SwiftUI

/// Rolling columns of stacked event cards, today on the left. Tap a day's header to widen it.
struct WeekView: View {
    let days: [Date]
    let events: [CalendarEvent]
    let members: [Member]
    var onSelect: (CalendarEvent) -> Void

    @State private var widenedDay: Date?
    @State private var openRecipe: CDRecipe?
    @FetchRequest private var dinners: FetchedResults<CDMeal>

    private let spacing: CGFloat = 8

    init(days: [Date], events: [CalendarEvent], members: [Member], onSelect: @escaping (CalendarEvent) -> Void) {
        self.days = days
        self.events = events
        self.members = members
        self.onSelect = onSelect
        _dinners = FetchRequest(sortDescriptors: [], predicate: NSPredicate(
            format: "day IN %@ AND slot == %@", days.map { DayKey.from($0) }, MealSlot.dinner.rawValue
        ))
    }

    var body: some View {
        GeometryReader { geo in
            let widened = widenedDay.flatMap(days.firstIndex(of:))
            let widths = WeekColumns.widths(total: geo.size.width, spacing: spacing, count: days.count, widened: widened)
            let dinnerByDay = Dictionary(dinners.map { ($0.day ?? "", $0) }, uniquingKeysWith: { a, _ in a })
            HStack(alignment: .top, spacing: spacing) {
                ForEach(Array(days.enumerated()), id: \.element) { index, day in
                    WeekDayColumn(
                        day: day,
                        events: DayLayout.agenda(events, on: day),
                        members: members,
                        dinner: dinnerByDay[DayKey.from(day)],
                        isWidened: index == widened,
                        onToggleWidth: {
                            withAnimation(.snappy) { widenedDay = widenedDay == day ? nil : day }
                        },
                        onSelect: onSelect,
                        onOpenRecipe: { openRecipe = $0 }
                    )
                    .frame(width: widths[index])
                }
            }
        }
        .sheet(item: $openRecipe) { RecipeView(recipe: $0) }
    }
}

private struct WeekDayColumn: View {
    let day: Date
    let events: [CalendarEvent]
    let members: [Member]
    let dinner: CDMeal?
    let isWidened: Bool
    var onToggleWidth: () -> Void
    var onSelect: (CalendarEvent) -> Void
    var onOpenRecipe: (CDRecipe) -> Void

    @State private var hasMoreBelow = false

    private var isToday: Bool { Calendar.current.isDateInToday(day) }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 16, style: .continuous) }

    var body: some View {
        VStack(spacing: 6) {
            header
            VStack(spacing: 0) {
                eventList
                if let dinner, let title = dinner.title, !title.isEmpty {
                    DinnerFooter(title: title, recipe: dinner.recipe, onOpen: onOpenRecipe)
                        .padding(5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.surface, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(isToday ? Palette.accent.opacity(0.5) : Palette.hairline, lineWidth: isToday ? 2 : 1))
            .opacity(day < Calendar.current.startOfDay(for: .now) ? 0.6 : 1)
        }
    }

    private var eventList: some View {
        ScrollView {
            VStack(spacing: 6) {
                ForEach(events) { e in
                    EventCard(event: e, style: EventStyle(e, members: members), size: .compact)
                        .onTapGesture { onSelect(e) }
                }
            }
            .padding(5)
        }
        .scrollIndicators(.hidden)
        .onScrollGeometryChange(for: Bool.self) { geo in
            geo.contentSize.height - geo.visibleRect.maxY > 6
        } action: { _, more in
            withAnimation(.easeOut(duration: 0.15)) { hasMoreBelow = more }
        }
        .overlay(alignment: .bottom) {
            if hasMoreBelow { moreBelowHint }
        }
    }

    /// One compact line instead of the old two-line header: more room for events.
    private var header: some View {
        Button(action: onToggleWidth) {
            HStack(spacing: 6) {
                Group {
                    if isToday {
                        Text("Today")
                    } else {
                        Text(day, format: .dateTime.weekday(isWidened ? .wide : .abbreviated))
                    }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isToday ? Palette.accent : Palette.inkSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                Text(day, format: .dateTime.day())
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(isToday ? .white : Palette.ink)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(isToday ? Palette.accent : .clear))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityHint(isWidened ? "Return to equal columns" : "Make this day wider")
    }

    /// Fade and chevron at the bottom of a column while more events are below. Doesn't block touches.
    private var moreBelowHint: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(colors: [Palette.surface.opacity(0), Palette.surface], startPoint: .top, endPoint: .bottom)
                .frame(height: 44)
            Image(systemName: "chevron.compact.down")
                .font(.title2.weight(.bold))
                .foregroundStyle(Palette.accent)
                .padding(.bottom, 4)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .transition(.opacity)
    }
}

/// That day's planned dinner, pinned below the events so a busy day can't scroll it away.
/// Opens the recipe when there is one, like the header's dinner card.
private struct DinnerFooter: View {
    let title: String
    let recipe: CDRecipe?
    var onOpen: (CDRecipe) -> Void

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 10, style: .continuous) }

    var body: some View {
        Button {
            if let recipe { onOpen(recipe) }
        } label: {
            HStack(spacing: 6) {
                if recipe?.imageData != nil {
                    RecipePhoto(recipe: recipe)
                        .frame(width: 30, height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                } else {
                    Text(MealSlot.dinner.emoji).font(.subheadline)
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
            .background(Palette.accent.opacity(0.13), in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .allowsHitTesting(recipe != nil) // not .disabled, which would grey out the title
        .accessibilityLabel("Dinner: \(title)")
    }
}
