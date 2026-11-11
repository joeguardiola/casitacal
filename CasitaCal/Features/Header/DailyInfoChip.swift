import SwiftUI

/// Small rotating card next to the weather. Hidden until a topic is turned on in Settings.
struct DailyInfoChip: View {
    @Environment(DailyInfoStore.self) private var daily
    @State private var sheetDay: DailyDay?
    /// `.infinity` lets the card take whatever room the header has left.
    var maxWidth: CGFloat = .infinity

    private let rotateEvery: TimeInterval = 10

    var body: some View {
        TimelineView(.periodic(from: .now, by: rotateEvery)) { context in
            let items = daily.items(for: context.date)
            ZStack {
                // Runs when the day changes or a topic is switched on, even before there's anything to show.
                Color.clear
                    .frame(width: 0, height: 0)
                    .task(id: refreshKey(context.date)) { await daily.refresh(for: context.date) }
                if !items.isEmpty {
                    let index = Int(context.date.timeIntervalSince1970 / rotateEvery) % items.count
                    let item = items[index]
                    Button { sheetDay = DailyDay(date: context.date) } label: {
                        ViewThatFits(in: .horizontal) {
                            card(item)
                            iconOnly(item)
                        }
                        .id(item.id)
                        .transition(.opacity)
                    }
                    .buttonStyle(.plain)
                    .animation(.easeInOut(duration: 0.6), value: item.id)
                    .accessibilityLabel("Today: \(item.cardLine ?? item.headline)")
                    .accessibilityHint("Shows today's details")
                }
            }
        }
        .sheet(item: $sheetDay) { DailyInfoSheet(date: $0.date) }
    }

    private func refreshKey(_ date: Date) -> String {
        "\(DayKey.from(date))-\(daily.enabledTopics.map(\.rawValue).sorted())"
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 16, style: .continuous) }

    private func card(_ item: DailyItem) -> some View {
        HStack(spacing: 12) {
            TopicIcon(topic: item.topic, crossHeight: 26)
                .font(.title2)
                .foregroundStyle(item.topic.tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                if item.cardLine == nil {
                    Text(item.topic.shortTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
                Text(item.cardLine ?? item.headline)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(item.cardLine == nil ? 2 : 3)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        // idealWidth: what the card asks for when the header checks whether it fits; without it
        // the whole sentence on one line was the ask, which never fit, so only the icon showed.
        // Height capped at the clock and avatars' height so the header never grows.
        .frame(minWidth: 190, idealWidth: 220, maxWidth: maxWidth, minHeight: 66, maxHeight: 76, alignment: .leading)
        .background(Palette.surface, in: shape)
        .overlay(shape.strokeBorder(Palette.hairline))
    }

    private func iconOnly(_ item: DailyItem) -> some View {
        TopicIcon(topic: item.topic, crossHeight: 28)
            .font(.title2)
            .foregroundStyle(item.topic.tint)
            .frame(width: 66, height: 66)
            .background(Palette.surface, in: shape)
            .overlay(shape.strokeBorder(Palette.hairline))
    }
}

/// SF Symbols' "cross" is a medical plus and the emoji is a purple box, so this one is drawn.
struct LatinCross: Shape {
    func path(in rect: CGRect) -> Path {
        let bar = rect.width * 0.3
        var path = Path()
        path.addRoundedRect(in: CGRect(x: rect.midX - bar / 2, y: rect.minY, width: bar, height: rect.height),
                            cornerSize: CGSize(width: bar / 4, height: bar / 4))
        path.addRoundedRect(in: CGRect(x: rect.minX, y: rect.minY + rect.height * 0.26, width: rect.width, height: bar),
                            cornerSize: CGSize(width: bar / 4, height: bar / 4))
        return path
    }
}

struct TopicIcon: View {
    let topic: DailyTopic
    let crossHeight: CGFloat

    var body: some View {
        if topic == .catholic {
            LatinCross().frame(width: crossHeight * 0.68, height: crossHeight)
        } else {
            Image(systemName: topic.symbol)
        }
    }
}

struct DailyDay: Identifiable, Hashable {
    var date: Date
    var id: String { DayKey.from(date) }
}

/// Everything for one day: the story, food and things to do, and what's coming up this week.
struct DailyInfoSheet: View {
    let date: Date

    @Environment(DailyInfoStore.self) private var daily
    @Environment(EventStore.self) private var events
    @Environment(Persistence.self) private var persistence
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var dinnerTitle: String?
    @State private var dishToConfirm: String?
    @State private var finding: FoodSearch?
    /// Feasts this sheet sees as added to the calendar (refreshed after a change).
    @State private var pinned: Set<String> = []

    private struct FoodSearch: Identifiable {
        var idea: String
        var url: URL
        var id: String { idea }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    let items = daily.items(for: date)
                    if items.isEmpty {
                        Text("Nothing special today.")
                            .foregroundStyle(Palette.inkSecondary)
                    }
                    ForEach(items) { itemCard($0) }
                    comingUp
                }
                .padding(20)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.canvas)
            .navigationTitle(date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task {
                refreshPlan()
                await daily.refresh(for: date)
            }
            .sheet(item: $finding, onDismiss: refreshPlan) { search in
                RecipeFinderSheet(dish: FoodIdea.dishName(search.idea), searchURL: search.url, day: date,
                                  allowDinner: FoodIdea.canPlanDinner(search.idea))
            }
            .alert(
                "Replace dinner?",
                isPresented: Binding(get: { dishToConfirm != nil }, set: { if !$0 { dishToConfirm = nil } }),
                presenting: dishToConfirm
            ) { dish in
                Button("Replace") { planDinner(dish) }
                Button("Cancel", role: .cancel) {}
            } message: { dish in
                Text("\(dinnerTitle ?? "Something else") is planned that night. Replace it with \(dish)?")
            }
        }
    }

    private func itemCard(_ item: DailyItem) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label { Text(item.topic.title) } icon: { TopicIcon(topic: item.topic, crossHeight: 16) }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(item.topic.tint)
                Text(item.headline)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !item.badges.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(item.badges, id: \.self) { badge in
                            Text(badge)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(item.topic.tint)
                                .padding(.horizontal, 10).padding(.vertical, 4)
                                .background(item.topic.tint.opacity(0.13), in: Capsule())
                        }
                    }
                }
                if let detail = item.detail { body(detail) }
                if let story = item.story { body(story) }
                if let note = item.note {
                    Text(note).font(.subheadline).foregroundStyle(Palette.inkSecondary)
                }
                foodIdeas(item.food)
                ideas("Things to Do", symbol: "sparkles", item.activities)
                ideas("Read Together", symbol: "book", item.readings)
                ideas("Pray", symbol: "hands.sparkles", item.prayers)
                if let indulgence = item.indulgence { indulgenceNote(indulgence) }
                if let link = item.link {
                    Link(item.linkLabel ?? "Read more", destination: link).font(.subheadline.weight(.semibold))
                    Text("From Wikipedia, CC BY-SA 4.0").font(.caption).foregroundStyle(Palette.inkSecondary)
                }
                if let celebration = item.celebration { addButton(celebration) }
            }
        }
    }

    private func body(_ text: String) -> some View {
        Text(text)
            .font(.body)
            .foregroundStyle(Palette.ink)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func ideas(_ title: String, symbol: String, _ list: [String]) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.inkSecondary)
                ForEach(list, id: \.self) { idea in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(Palette.accent)
                        Text(idea)
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func foodIdeas(_ list: [String]) -> some View {
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label("Food Ideas", systemImage: "fork.knife")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.inkSecondary)
                ForEach(list, id: \.self, content: foodRow)
            }
        }
    }

    private func foodRow(_ idea: String) -> some View {
        let layout = sizeClass == .compact
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        let dish = FoodIdea.dishName(idea)
        return layout {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(Palette.accent)
                Text(idea)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if FoodIdea.hasRecipe(idea) {
                HStack(spacing: 8) {
                    if let url = FoodIdea.recipeSearchURL(idea) {
                        Button("Find a Recipe") { finding = FoodSearch(idea: idea, url: url) }
                    }
                    if FoodIdea.canPlanDinner(idea) {
                        if dinnerTitle == dish {
                            Label("Planned", systemImage: "checkmark")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.green)
                        } else {
                            Button("Plan Dinner") { requestDinner(dish) }
                        }
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
            }
        }
    }

    private func requestDinner(_ dish: String) {
        if dinnerTitle?.isEmpty == false {
            dishToConfirm = dish
        } else {
            planDinner(dish)
        }
    }

    private func planDinner(_ dish: String) {
        MealPlan.planDinner(title: dish, day: DayKey.from(date), persistence: persistence)
        dinnerTitle = dish
    }

    private func indulgenceNote(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Indulgence", systemImage: "seal")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.inkSecondary)
            Text(text)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("A plenary indulgence also needs the usual conditions: confession, Communion, prayer for the Pope's intentions and detachment from all sin. Only one can be gained each day.")
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func refreshPlan() {
        dinnerTitle = MealPlan.dinnerTitle(day: DayKey.from(date), context: persistence.context)
        pinned = Set(daily.celebrations(on: date).filter { FeastPins.isPinned($0, context: persistence.context) }.map(\.id))
    }

    /// Adds the feast to the bottom of the day on the calendar, for the whole household.
    /// Nothing goes to Google; feasts added there before still count as added.
    @ViewBuilder
    private func addButton(_ c: Celebration) -> some View {
        if pinned.contains(c.id) {
            HStack(spacing: 12) {
                Label("On the calendar", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
                Button("Remove", role: .destructive) {
                    FeastPins.unpin(c, persistence: persistence)
                    refreshPlan()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } else if DailyInfoStore.isOnCalendar(c.entry.name, day: date, events: events.events) {
            Label("On the family calendar", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
        } else {
            Button {
                FeastPins.pin(c, persistence: persistence)
                refreshPlan()
            } label: {
                Label("Add to calendar", systemImage: "calendar.badge.plus")
            }
            .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    private var comingUp: some View {
        let upcoming = daily.comingUp(after: date)
        if !upcoming.isEmpty {
            Text("Coming Up This Week")
                .font(.headline)
                .foregroundStyle(Palette.inkSecondary)
                .padding(.top, 6)
            ForEach(upcoming, id: \.day) { day, items in
                HStack(alignment: .top, spacing: 12) {
                    Text(day, format: .dateTime.weekday(.abbreviated).day())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.inkSecondary)
                        .frame(width: 70, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(items) { Text($0.headline).foregroundStyle(Palette.ink) }
                    }
                }
            }
        }
    }
}

/// Settings → Daily info: the per-device topic switches.
struct DailyInfoSettings: View {
    @Environment(DailyInfoStore.self) private var daily
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        @Bindable var daily = daily
        Form {
            Section {
                ForEach(DailyTopic.allCases.filter { isPad || $0 == .catholic }) { topic in
                    Toggle(topic.title, isOn: Binding(get: { daily.isOn(topic) }, set: { daily.set(topic, on: $0) }))
                }
            } footer: {
                if isPad { Text("Chosen topics rotate next to the weather. Tap the card for details.") }
            }
            if daily.isOn(.catholic) {
                Section {
                    Picker("Which days", selection: $daily.catholicLevel) {
                        ForEach(CatholicLevel.allCases) { Text($0.title).tag($0) }
                    }
                    Toggle("Show every feast on the calendar", isOn: $daily.showFeastsOnCalendar)
                } header: {
                    Text("Catholic feast days")
                } footer: {
                    Text("Feasts sit at the bottom of the day. Add single feasts from their details. Dates follow the U.S. calendar.")
                }
            }
        }
        .navigationTitle("Daily Info")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension DailyInfoStore {
    /// "Catholic, History", "3 topics" or "Off", for the Settings row.
    var settingsSummary: String {
        let on = DailyTopic.allCases.filter(isOn)
        switch on.count {
        case 0: return "Off"
        case 1...2: return on.map(\.settingsLabel).joined(separator: ", ")
        default: return "\(on.count) topics"
        }
    }
}

extension DailyTopic {
    var settingsLabel: String {
        switch self {
        case .catholic: "Catholic"
        case .currentEvent: "Coming Up"
        case .nationalDay: "World Days"
        case .history: "History"
        case .affirmation: "Thought"
        }
    }
}
