import CoreData
import SwiftUI

/// Rolling columns of stacked event cards, today on the left and widened. Tap anywhere in a day
/// to widen it (tap again to even them out); double-tap a day to add an event on it.
struct WeekView: View {
    let days: [Date]
    let events: [CalendarEvent]
    let members: [Member]
    var onSelect: (CalendarEvent) -> Void
    var onAdd: (Date) -> Void

    @State private var widthChoice: WeekColumns.Choice = .automatic
    @State private var openRecipe: CDRecipe?
    @FetchRequest private var dinners: FetchedResults<CDMeal>

    private let spacing: CGFloat = 8

    init(days: [Date], events: [CalendarEvent], members: [Member],
         onSelect: @escaping (CalendarEvent) -> Void, onAdd: @escaping (Date) -> Void) {
        self.days = days
        self.events = events
        self.members = members
        self.onSelect = onSelect
        self.onAdd = onAdd
        _dinners = FetchRequest(sortDescriptors: [], predicate: NSPredicate(
            format: "day IN %@ AND slot == %@", days.map { DayKey.from($0) }, MealSlot.dinner.rawValue
        ))
    }

    var body: some View {
        GeometryReader { geo in
            let widened = WeekColumns.widenedIndex(widthChoice, days: days)
            let widths = WeekColumns.widths(total: geo.size.width, spacing: spacing, count: days.count, widened: widened)
            let dinnerByDay = Dictionary(dinners.map { ($0.day ?? "", $0) }, uniquingKeysWith: { a, _ in a })
            HStack(alignment: .top, spacing: spacing) {
                ForEach(Array(days.enumerated()), id: \.element) { index, day in
                    let agenda = DayLayout.agenda(events, on: day)
                    WeekDayColumn(
                        day: day,
                        events: agenda.filter { !$0.isFeastOverlay },
                        feasts: agenda.filter(\.isFeastOverlay),
                        members: members,
                        dinner: dinnerByDay[DayKey.from(day)],
                        isWidened: index == widened,
                        onToggleWidth: {
                            withAnimation(.snappy) {
                                widthChoice = WeekColumns.toggled(widthChoice, tapped: index, days: days)
                            }
                        },
                        onAdd: { onAdd(day) },
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
    let feasts: [CalendarEvent]
    let members: [Member]
    let dinner: CDMeal?
    let isWidened: Bool
    var onToggleWidth: () -> Void
    var onAdd: () -> Void
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
                let hasDinner = dinner?.isPlanned == true
                if !feasts.isEmpty || hasDinner {
                    VStack(spacing: 5) {
                        ForEach(feasts) { feast in
                            FeastFooter(title: feast.title) { onSelect(feast) }
                        }
                        if let dinner, let title = dinner.displayTitle {
                            DinnerFooter(title: title, recipe: dinner.recipe ?? dinner.photoRecipe, onOpen: onOpenRecipe)
                        }
                    }
                    .padding(5)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.surface, in: shape)
            .clipShape(shape)
            .overlay(shape.strokeBorder(isToday ? Palette.accent.opacity(0.5) : Palette.hairline, lineWidth: isToday ? 2 : 1))
            .opacity(day < Calendar.current.startOfDay(for: .now) ? 0.6 : 1)
        }
        // Anywhere in the column that isn't an event or a footer: tap to widen, double-tap to add.
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onAdd)
        .onTapGesture(perform: onToggleWidth)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: isWidened ? "Return to equal columns" : "Make this day wider", onToggleWidth)
        .accessibilityAction(named: "Add event", onAdd)
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
    /// Not a button: taps go to the whole column (single to widen, double to add).
    private var header: some View {
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).month(.wide).day()))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isWidened ? "Return to equal columns" : "Make this day wider")
        .accessibilityAction { onToggleWidth() }
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

/// A feast day added to the calendar (or all of them, with "Show every feast on the calendar"), shown at the
/// bottom of the day like the dinner. Opens the day's story.
private struct FeastFooter: View {
    let title: String
    var onOpen: () -> Void

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 10, style: .continuous) }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 7) {
                LatinCross()
                    .frame(width: 10, height: 15)
                    .foregroundStyle(Palette.feast)
                    .frame(width: 18)
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background(Palette.feast.opacity(0.13), in: shape)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Feast: \(title)")
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
