import CoreData
import SwiftUI

enum MealSlot: String, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var emoji: String {
        switch self {
        case .breakfast: "🥞"
        case .lunch: "🥪"
        case .dinner: "🍝"
        case .snack: "🍎"
        }
    }
}

/// Weekly meal plan: days across, breakfast/lunch/dinner/snack down.
struct MealsScreen: View {
    @AppStorage(Calendar.weekStartsOnMondayKey) private var weekStartsOnMonday = true
    @AppStorage("meals.showBreakfast") private var showBreakfast = true
    @AppStorage("meals.showLunch") private var showLunch = true
    @AppStorage("meals.showSnack") private var showSnack = false
    @State private var anchor = Date()
    @State private var editing: MealCell?
    @Environment(\.horizontalSizeClass) private var sizeClass

    struct MealCell: Identifiable, Hashable {
        var day: String
        var slot: MealSlot
        var id: String { "\(day)-\(slot.rawValue)" }
    }

    private var days: [Date] { CalendarRanges.days(in: CalendarRanges.range(for: .week, anchor: anchor)) }

    private var slots: [MealSlot] {
        MealSlot.allCases.filter {
            switch $0 {
            case .breakfast: showBreakfast
            case .lunch: showLunch
            case .dinner: true
            case .snack: showSnack
            }
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                HStack(spacing: 4) {
                    CircleNavButton(symbol: "chevron.left", label: "Previous week") { shift(-1) }
                    CircleNavButton(symbol: "chevron.right", label: "Next week") { shift(1) }
                }
                Text(title)
                    .font(sizeClass == .compact ? .title3.weight(.bold) : .title.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if sizeClass != .compact, !CalendarRanges.range(for: .week, anchor: anchor).contains(Date()) {
                    Button("This week") { withAnimation(.snappy) { anchor = Date() } }
                        .buttonStyle(.bordered).controlSize(.large)
                }
                Spacer()
                Menu {
                    Button("This week") { withAnimation(.snappy) { anchor = Date() } }
                    Toggle("Breakfast", isOn: $showBreakfast)
                    Toggle("Lunch", isOn: $showLunch)
                    Toggle("Snacks", isOn: $showSnack)
                } label: {
                    if sizeClass == .compact {
                        Image(systemName: "slider.horizontal.3")
                    } else {
                        Label("Meals shown", systemImage: "slider.horizontal.3")
                    }
                }
                .buttonStyle(.bordered).controlSize(.large)
            }
            if sizeClass == .compact {
                MealList(days: days, slots: slots) { editing = $0 }
            } else {
                MealGrid(days: days, slots: slots) { editing = $0 }
            }
        }
        .padding(sizeClass == .compact ? 14 : 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.canvas)
        .sheet(item: $editing) { MealEditor(cell: $0) }
    }

    private var title: String {
        guard let first = days.first, let last = days.last else { return "" }
        return "\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private func shift(_ n: Int) {
        withAnimation(.snappy) { anchor = CalendarRanges.step(anchor, mode: .week, by: n) }
    }
}

private struct MealGrid: View {
    let days: [Date]
    let slots: [MealSlot]
    var onEdit: (MealsScreen.MealCell) -> Void

    @FetchRequest private var meals: FetchedResults<CDMeal>

    init(days: [Date], slots: [MealSlot], onEdit: @escaping (MealsScreen.MealCell) -> Void) {
        self.days = days
        self.slots = slots
        self.onEdit = onEdit
        _meals = FetchRequest(sortDescriptors: [], predicate: NSPredicate(format: "day IN %@", days.map { DayKey.from($0) }))
    }

    var body: some View {
        let byCell = Dictionary(meals.map { ("\($0.day ?? "")-\($0.slot ?? "")", $0) }, uniquingKeysWith: { a, _ in a })
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]).frame(width: 96, height: 1)
                ForEach(days, id: \.self) { day in
                    let isToday = Calendar.app.isDateInToday(day)
                    VStack(spacing: 2) {
                        Text(day, format: .dateTime.weekday(.abbreviated))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(isToday ? Palette.accent : Palette.inkSecondary)
                        Text(day, format: .dateTime.day())
                            .font(.title2.weight(.bold))
                            .foregroundStyle(isToday ? Palette.accent : Palette.ink)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            ForEach(slots) { slot in
                GridRow {
                    VStack(spacing: 4) {
                        Text(slot.emoji).font(.system(size: 30))
                        Text(slot.label).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.inkSecondary)
                    }
                    .frame(width: 96)
                    ForEach(days, id: \.self) { day in
                        let key = DayKey.from(day)
                        let meal = byCell["\(key)-\(slot.rawValue)"]
                        Button { onEdit(.init(day: key, slot: slot)) } label: {
                            Group {
                                if let title = meal?.title, !title.isEmpty {
                                    Text(title)
                                        .font(.headline)
                                        .foregroundStyle(Palette.ink)
                                        .multilineTextAlignment(.center)
                                        .lineLimit(4)
                                        .minimumScaleFactor(0.8)
                                } else {
                                    Image(systemName: "plus").font(.title3).foregroundStyle(Palette.hairline)
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(meal?.title?.isEmpty == false ? Palette.accent.opacity(0.12) : Palette.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .strokeBorder(Calendar.app.isDateInToday(day) ? Palette.accent.opacity(0.5) : Palette.hairline,
                                                  lineWidth: Calendar.app.isDateInToday(day) ? 2 : 1)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(slot.label), \(day.formatted(.dateTime.weekday(.wide))): \(meal?.title ?? "empty")")
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }
}

/// Phone: one card per day, meals listed inside.
private struct MealList: View {
    let days: [Date]
    let slots: [MealSlot]
    var onEdit: (MealsScreen.MealCell) -> Void

    @FetchRequest private var meals: FetchedResults<CDMeal>

    init(days: [Date], slots: [MealSlot], onEdit: @escaping (MealsScreen.MealCell) -> Void) {
        self.days = days
        self.slots = slots
        self.onEdit = onEdit
        _meals = FetchRequest(sortDescriptors: [], predicate: NSPredicate(format: "day IN %@", days.map { DayKey.from($0) }))
    }

    var body: some View {
        let byCell = Dictionary(meals.map { ("\($0.day ?? "")-\($0.slot ?? "")", $0) }, uniquingKeysWith: { a, _ in a })
        ScrollView {
            VStack(spacing: 12) {
                ForEach(days, id: \.self) { day in
                    let key = DayKey.from(day)
                    let isToday = Calendar.app.isDateInToday(day)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(day, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                            .font(.headline)
                            .foregroundStyle(isToday ? Palette.accent : Palette.ink)
                        ForEach(slots) { slot in
                            Button { onEdit(.init(day: key, slot: slot)) } label: {
                                HStack(spacing: 10) {
                                    Text(slot.emoji)
                                    Text(slot.label).foregroundStyle(Palette.inkSecondary).frame(width: 80, alignment: .leading)
                                    Text(byCell["\(key)-\(slot.rawValue)"]?.title ?? "—")
                                        .foregroundStyle(Palette.ink)
                                        .lineLimit(1)
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(isToday ? Palette.accent.opacity(0.5) : Palette.hairline, lineWidth: isToday ? 2 : 1))
                }
            }
        }
    }
}

private struct MealEditor: View {
    let cell: MealsScreen.MealCell

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(Persistence.self) private var persistence
    @State private var title = ""
    @State private var notes = ""
    @State private var existing: CDMeal?
    @State private var recent: [String] = []
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Tacos", text: $title).font(.title2).focused($focused)
                    TextField("Notes (recipe link, who's cooking…)", text: $notes, axis: .vertical)
                }
                if !recent.isEmpty {
                    Section("Recent") {
                        FlowChips(items: recent) { title = $0 }
                    }
                }
                if existing != nil {
                    Section {
                        Button("Clear", systemImage: "trash", role: .destructive) {
                            if let existing { context.delete(existing) }
                            try? context.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("\(cell.slot.emoji) \(cell.slot.label) · \(DayKey.date(cell.day)?.formatted(.dateTime.weekday(.wide)) ?? "")")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).fontWeight(.semibold) }
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.medium, .large])
    }

    private func load() {
        let request = NSFetchRequest<CDMeal>(entityName: "CDMeal")
        request.predicate = NSPredicate(format: "day == %@ AND slot == %@", cell.day, cell.slot.rawValue)
        existing = try? context.fetch(request).first
        title = existing?.title ?? ""
        notes = existing?.notes ?? ""

        // Recent meals for this slot, most-used first, for one-tap reuse.
        let all = NSFetchRequest<CDMeal>(entityName: "CDMeal")
        all.predicate = NSPredicate(format: "slot == %@", cell.slot.rawValue)
        let counts = ((try? context.fetch(all)) ?? []).compactMap(\.title).filter { !$0.isEmpty }
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        recent = counts.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.prefix(12).map(\.key)
        focused = existing == nil
    }

    private func save() {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            if let existing { context.delete(existing) }
        } else {
            let meal = existing ?? {
                let m = persistence.insert(CDMeal.self)
                m.id = UUID()
                m.day = cell.day
                m.slot = cell.slot.rawValue
                m.household = persistence.household()
                return m
            }()
            meal.title = trimmed
            meal.notes = notes
        }
        try? context.save()
        dismiss()
    }
}

/// Wrapping row of tappable chips.
struct FlowChips: View {
    let items: [String]
    var onTap: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(items, id: \.self) { item in
                Button(item) { onTap(item) }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
            }
        }
        .padding(.vertical, 4)
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
