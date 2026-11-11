import CoreData
import PhotosUI
import SwiftUI

/// Rolling seven-day meal plan: today on the left, breakfast/lunch/dinner/snack down.
struct MealsScreen: View {
    @AppStorage("meals.showBreakfast") private var showBreakfast = true
    @AppStorage("meals.showLunch") private var showLunch = true
    @AppStorage("meals.showSnack") private var showSnack = false
    @State private var anchor = Date()
    @State private var pageEdge: Edge = .trailing
    @State private var editing: MealCell?
    @State private var viewing: Viewing?
    @State private var showingRecipeBox = false
    @State private var hoverPaging: Task<Void, Never>?
    @State private var movedCount = 0
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.managedObjectContext) private var context

    private static let dayCount = 7

    struct MealCell: Identifiable, Hashable {
        var day: String
        var slot: MealSlot
        var id: String { "\(day)-\(slot.rawValue)" }
    }

    struct Viewing: Identifiable {
        var cell: MealCell
        var recipe: CDRecipe
        var sides: [CDMealSide]
        var id: String { cell.id }
    }

    /// Planned meals with a recipe open the recipe (with its sides); everything else opens the editor.
    private func open(_ cell: MealCell, _ meal: CDMeal?) {
        if let meal, let recipe = meal.recipe {
            viewing = Viewing(cell: cell, recipe: recipe, sides: meal.sortedSides)
        } else {
            editing = cell
        }
    }

    /// A meal was dropped on `cell`. If that spot is taken, the two meals trade places.
    private func move(_ payload: String, to cell: MealCell) -> Bool {
        guard let id = UUID(uuidString: payload) else { return false }
        let moved = (try? MealPlan.move(mealID: id, toDay: cell.day, slot: cell.slot.rawValue, context: context)) ?? false
        if moved { movedCount += 1 }
        return moved
    }

    private var days: [Date] { CalendarRanges.rollingDays(from: anchor, count: Self.dayCount) }

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
                    weekButton("chevron.left", label: "Previous week", by: -1)
                    weekButton("chevron.right", label: "Next week", by: 1)
                }
                Text(title)
                    .font(sizeClass == .compact ? .title3.weight(.bold) : .title.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if sizeClass != .compact, !Calendar.app.isDateInToday(anchor) {
                    Button("Today", action: goToToday)
                        .buttonStyle(.bordered).controlSize(.large).fixedSize()
                }
                Spacer()
                Button { showingRecipeBox = true } label: {
                    if sizeClass == .compact {
                        Image(systemName: "book.closed")
                    } else {
                        Label("Recipes", systemImage: "book.closed")
                    }
                }
                .buttonStyle(.bordered).controlSize(.large)
                Menu {
                    // Phones have no room for the Today button beside the dates.
                    if sizeClass == .compact {
                        Button("Go to Today", systemImage: "arrow.uturn.backward", action: goToToday)
                        Divider()
                    }
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
            PagedContent(key: days.first, edge: pageEdge) {
                if sizeClass == .compact {
                    MealList(days: days, slots: slots, onOpen: open, onMove: move)
                } else {
                    MealGrid(days: days, slots: slots, onOpen: open, onMove: move)
                }
            }
            .swipeToPage(previous: { shift(-1) }, next: { shift(1) })
        }
        .padding(sizeClass == .compact ? 14 : 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.canvas)
        .sheet(item: $editing) { MealEditor(cell: $0) }
        .sheet(item: $viewing) { v in
            RecipeView(recipe: v.recipe, sides: v.sides) {
                viewing = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    editing = v.cell
                }
            }
        }
        .sheet(isPresented: $showingRecipeBox) { RecipeBox() }
        .sensoryFeedback(.success, trigger: movedCount)
        .modifier(FollowsToday(anchor: $anchor))
    }

    /// Week arrow that also pages while a dragged meal hovers over it, to reach other weeks.
    private func weekButton(_ symbol: String, label: String, by n: Int) -> some View {
        CircleNavButton(symbol: symbol, label: label) { shift(n) }
            .dropDestination(for: String.self) { _, _ in false } isTargeted: { over in
                hoverPaging?.cancel()
                hoverPaging = over ? pageWhileHovering(by: n) : nil
            }
    }

    private func pageWhileHovering(by n: Int) -> Task<Void, Never> {
        Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(700))
                if Task.isCancelled { return }
                shift(n)
            }
        }
    }

    private var title: String {
        guard let first = days.first, let last = days.last else { return "" }
        return "\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private func shift(_ n: Int) {
        pageEdge = n > 0 ? .trailing : .leading
        Task { @MainActor in
            withAnimation(.snappy) { anchor = CalendarRanges.stepRolling(anchor, count: Self.dayCount, by: n) }
        }
    }

    private func goToToday() {
        let now = Date()
        pageEdge = now < anchor ? .leading : .trailing
        Task { @MainActor in
            withAnimation(.snappy) { anchor = now }
        }
    }
}

private struct MealGrid: View {
    let days: [Date]
    let slots: [MealSlot]
    var onOpen: (MealsScreen.MealCell, CDMeal?) -> Void
    var onMove: (String, MealsScreen.MealCell) -> Bool

    @FetchRequest private var meals: FetchedResults<CDMeal>

    init(days: [Date], slots: [MealSlot], onOpen: @escaping (MealsScreen.MealCell, CDMeal?) -> Void,
         onMove: @escaping (String, MealsScreen.MealCell) -> Bool) {
        self.days = days
        self.slots = slots
        self.onOpen = onOpen
        self.onMove = onMove
        _meals = FetchRequest(sortDescriptors: [], predicate: NSPredicate(format: "day IN %@", days.map { DayKey.from($0) }))
    }

    var body: some View {
        let byCell = Dictionary(meals.map { ("\($0.day ?? "")-\($0.slot ?? "")", $0) }, uniquingKeysWith: { a, _ in a })
        // Explicit day widths keep all seven days on screen when the iPad is in portrait.
        GeometryReader { geo in
            grid(byCell: byCell, dayWidth: dayWidth(total: geo.size.width))
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }

    private func dayWidth(total: CGFloat) -> CGFloat {
        let count = CGFloat(max(days.count, 1))
        let gaps: CGFloat = 10 * count
        return max((total - 84 - gaps) / count, 0)
    }

    private func grid(byCell: [String: CDMeal], dayWidth: CGFloat) -> some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            GridRow {
                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]).frame(width: 84, height: 1)
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
                    .frame(width: dayWidth)
                }
            }
            ForEach(slots) { slot in
                // Dinner gets the big photo tiles; other meals stay compact.
                let isBig = slot == .dinner
                GridRow {
                    VStack(spacing: 4) {
                        Text(slot.emoji).font(.system(size: isBig ? 30 : 22))
                        Text(slot.label).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.inkSecondary)
                    }
                    .frame(width: 84)
                    ForEach(days, id: \.self) { day in
                        let key = DayKey.from(day)
                        let meal = byCell["\(key)-\(slot.rawValue)"]
                        Button { onOpen(.init(day: key, slot: slot), meal) } label: {
                            MealTile(meal: meal, isBig: isBig, isToday: Calendar.app.isDateInToday(day))
                        }
                        .buttonStyle(.plain)
                        .draggableMeal(meal)
                        .frame(width: dayWidth)
                        .modifier(MealDropTarget(cornerRadius: 16) { onMove($0, .init(day: key, slot: slot)) })
                        .accessibilityLabel("\(slot.label), \(day.formatted(.dateTime.weekday(.wide))): \(meal?.title ?? "empty")")
                    }
                }
                .frame(height: isBig ? nil : 72)
                .frame(maxHeight: isBig ? .infinity : nil)
            }
        }
    }
}

private struct MealTile: View {
    let meal: CDMeal?
    let isBig: Bool
    let isToday: Bool

    private var title: String? { meal?.title.flatMap { $0.isEmpty ? nil : $0 } }
    private var hasPhoto: Bool { meal?.recipe?.imageData != nil }
    /// "with Salad, Rolls" on the big dinner tiles; "+ 2 sides" on the small ones.
    private var sidesText: String? { meal.flatMap { MealSides.summary($0, short: !isBig) } }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 16, style: .continuous) }

    var body: some View {
        Group {
            if let title {
                if isBig && hasPhoto {
                    ZStack(alignment: .bottomLeading) {
                        Color.clear.overlay { RecipePhoto(recipe: meal?.recipe) }
                        LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .lineLimit(3)
                            if let sides = sidesText {
                                Text(sides).font(.caption.weight(.medium)).foregroundStyle(.white.opacity(0.85)).lineLimit(2)
                            }
                        }
                        .padding(10)
                    }
                } else if hasPhoto {
                    HStack(spacing: 8) {
                        RecipePhoto(recipe: meal?.recipe)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(2)
                            if let sides = sidesText {
                                Text(sides).font(.caption2).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .background(Palette.accent.opacity(0.12))
                } else {
                    VStack(spacing: 3) {
                        Text(title)
                            .font(isBig ? .headline : .subheadline.weight(.semibold))
                            .foregroundStyle(Palette.ink)
                            .lineLimit(isBig ? 4 : 2)
                            .minimumScaleFactor(0.8)
                        if let sides = sidesText {
                            Text(sides)
                                .font(isBig ? .caption.weight(.medium) : .caption2)
                                .foregroundStyle(Palette.inkSecondary)
                                .lineLimit(isBig ? 3 : 1)
                        }
                    }
                    .multilineTextAlignment(.center)
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.accent.opacity(0.12))
                }
            } else {
                Image(systemName: "plus").font(.title3).foregroundStyle(Palette.hairline)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Palette.surface)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(shape)
        .overlay(shape.strokeBorder(isToday ? Palette.accent.opacity(0.6) : Palette.hairline, lineWidth: isToday ? 2 : 1))
        .contentShape(shape)
    }
}

/// Phone: one card per day, meals listed inside.
private struct MealList: View {
    let days: [Date]
    let slots: [MealSlot]
    var onOpen: (MealsScreen.MealCell, CDMeal?) -> Void
    var onMove: (String, MealsScreen.MealCell) -> Bool

    @FetchRequest private var meals: FetchedResults<CDMeal>

    init(days: [Date], slots: [MealSlot], onOpen: @escaping (MealsScreen.MealCell, CDMeal?) -> Void,
         onMove: @escaping (String, MealsScreen.MealCell) -> Bool) {
        self.days = days
        self.slots = slots
        self.onOpen = onOpen
        self.onMove = onMove
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
                            let meal = byCell["\(key)-\(slot.rawValue)"]
                            Button { onOpen(.init(day: key, slot: slot), meal) } label: {
                                HStack(spacing: 10) {
                                    Text(slot.emoji)
                                    Text(slot.label).foregroundStyle(Palette.inkSecondary).frame(width: 80, alignment: .leading)
                                    Text(meal?.title ?? "—")
                                        .foregroundStyle(Palette.ink)
                                        .lineLimit(1)
                                    if let meal, let sides = MealSides.summary(meal, short: true) {
                                        Text(sides).font(.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                                    }
                                    Spacer()
                                    if meal?.recipe?.imageData != nil {
                                        RecipePhoto(recipe: meal?.recipe)
                                            .frame(width: 40, height: 40)
                                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    }
                                }
                                .padding(.vertical, 4)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .draggableMeal(meal)
                            .modifier(MealDropTarget(cornerRadius: 8) { onMove($0, .init(day: key, slot: slot)) })
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

enum MealSides {
    /// "with Salad, Rolls", or "+ 2 sides" where there's little room. Nil with no sides.
    static func summary(_ meal: CDMeal, short: Bool) -> String? {
        let titles = meal.sortedSides.compactMap(\.title).filter { !$0.isEmpty }
        guard !titles.isEmpty else { return nil }
        if short { return titles.count == 1 ? "+ 1 side" : "+ \(titles.count) sides" }
        return "with " + titles.formatted(.list(type: .and))
    }
}

private extension View {
    /// Press and hold a planned meal for its menu (remove it), or keep moving to drag it
    /// somewhere else. Empty spots do neither.
    func draggableMeal(_ meal: CDMeal?) -> some View {
        modifier(PlannedMealActions(meal: meal))
    }
}

private struct PlannedMealActions: ViewModifier {
    let meal: CDMeal?
    @Environment(\.managedObjectContext) private var context
    @Environment(Persistence.self) private var persistence

    func body(content: Content) -> some View {
        if let meal, let id = meal.id?.uuidString, let title = meal.title, !title.isEmpty {
            content
                .contextMenu {
                    Button("Remove from Plan", systemImage: "trash", role: .destructive) {
                        withAnimation(.snappy) {
                            context.delete(meal) // its sides go with it
                            persistence.save()
                        }
                    }
                } preview: {
                    MealDragPreview(title: title, recipe: meal.recipe)
                }
                .draggable(id) { MealDragPreview(title: title, recipe: meal.recipe) }
        } else {
            content
        }
    }
}

private struct MealDragPreview: View {
    let title: String
    let recipe: CDRecipe?

    var body: some View {
        HStack(spacing: 10) {
            if recipe?.imageData != nil {
                RecipePhoto(recipe: recipe)
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            Text(title)
                .font(.headline)
                .foregroundStyle(Palette.ink)
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: 240)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Accepts a dropped meal and highlights while one hovers over it.
private struct MealDropTarget: ViewModifier {
    var cornerRadius: CGFloat
    var onDrop: (String) -> Bool
    @State private var isTargeted = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .overlay {
                if isTargeted {
                    shape.fill(Palette.accent.opacity(0.15))
                        .overlay(shape.strokeBorder(Palette.accent, lineWidth: 3))
                        .allowsHitTesting(false)
                }
            }
            .dropDestination(for: String.self) { ids, _ in
                guard let id = ids.first else { return false }
                return onDrop(id)
            } isTargeted: { isTargeted = $0 }
    }
}

/// One dish being edited: the main dish or a side. Becomes a saved recipe (if it has one) on Save.
@MainActor
@Observable
final class DishDraft: Identifiable, Hashable {
    let id = UUID()
    /// The saved side this edits; nil for the main dish or a side that isn't saved yet.
    let side: CDMealSide?
    var title: String
    var chosen: CDRecipe?
    let link = LinkImport()
    var photoData: Data?

    init(title: String = "", chosen: CDRecipe? = nil, side: CDMealSide? = nil) {
        self.title = title
        self.chosen = chosen
        self.side = side
    }

    nonisolated static func == (a: DishDraft, b: DishDraft) -> Bool { a.id == b.id }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var trimmedTitle: String { title.trimmingCharacters(in: .whitespaces) }
    var isLoading: Bool { link.state == .loading }
    var isBlank: Bool {
        trimmedTitle.isEmpty && chosen == nil && link.result == nil && photoData == nil && link.text.isEmpty
    }

    /// The recipe to attach: a picked one, a pasted link, or just a photo (still handy to plan again).
    func resolveRecipe(persistence: Persistence) -> CDRecipe? {
        if let result = link.result {
            return RecipeImporter.save(result.recipe, image: result.image, persistence: persistence)
        }
        if let chosen { return chosen }
        if let photoData {
            let r = newRecipe(persistence)
            r.imageData = photoData
            return r
        }
        if let url = RecipeImporter.firstLink(in: link.text) {
            // Site blocked reading: keep the link anyway.
            let r = newRecipe(persistence)
            r.sourceURL = url.absoluteString
            r.siteName = url.host()
            return r
        }
        return nil
    }

    /// What was typed, or the recipe's name. Gives a nameless recipe the typed name.
    func finalTitle(with recipe: CDRecipe?) -> String {
        let name = trimmedTitle.isEmpty ? (recipe?.title ?? "") : trimmedTitle
        if let recipe, (recipe.title ?? "").isEmpty { recipe.title = name }
        return name
    }

    private func newRecipe(_ persistence: Persistence) -> CDRecipe {
        let r = persistence.insert(CDRecipe.self)
        r.id = UUID()
        r.createdAt = Date()
        r.household = persistence.household()
        r.title = trimmedTitle
        return r
    }
}

/// Name, saved-recipe autocomplete, and link or photo, for the main dish and for each side.
private struct DishFields: View {
    @Bindable var dish: DishDraft
    var placeholder: String
    var savedRecipes: [CDRecipe]

    @State private var photoItem: PhotosPickerItem?
    @FocusState private var titleFocused: Bool

    /// Saved recipes matching what's being typed. Tapping one attaches it; typing alone never does.
    private var suggestions: [CDRecipe] {
        guard titleFocused, dish.chosen == nil, dish.link.result == nil else { return [] }
        return RecipeSearch.suggestions(for: dish.title, in: savedRecipes, title: { $0.title })
    }

    var body: some View {
        Section {
            TextField(placeholder, text: $dish.title).font(.title2).focused($titleFocused)
            ForEach(suggestions, id: \.objectID) { recipe in
                Button {
                    titleFocused = false
                    pick(recipe)
                } label: {
                    RecipeSuggestionRow(recipe: recipe)
                }
                .buttonStyle(.plain)
            }
        }
        .onChange(of: dish.link.result?.recipe) { _, new in
            if let new, dish.trimmedTitle.isEmpty { dish.title = new.title }
        }
        .onChange(of: photoItem) { _, item in
            Task { @MainActor in
                guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                dish.photoData = RecipeImporter.downscaledJPEG(data)
            }
        }
        recipeSection
        if !savedRecipes.isEmpty && dish.chosen == nil && dish.link.result == nil {
            Section("From your recipes") {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(savedRecipes.prefix(20), id: \.objectID) { r in
                            Button { pick(r) } label: { RecipeChip(recipe: r) }.buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    @ViewBuilder
    private var recipeSection: some View {
        Section {
            if let chosen = dish.chosen {
                HStack(spacing: 12) {
                    RecipeChip(recipe: chosen, isSelected: true)
                    Spacer()
                    Button("Remove", role: .destructive) { dish.chosen = nil }
                }
            } else if let result = dish.link.result {
                ParsedRecipeCard(recipe: result.recipe, image: result.image)
                Button("Remove recipe", role: .destructive) { dish.link.clear() }
            } else {
                LinkImportField(link: dish.link)
                let preview = dish.photoData.flatMap { UIImage(data: $0) }
                PhotosPicker(selection: $photoItem, matching: .images) {
                    if let ui = preview {
                        HStack {
                            Image(uiImage: ui).resizable().scaledToFill().frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Text("Change photo")
                        }
                    } else {
                        Label("Or add a photo", systemImage: "photo")
                    }
                }
            }
        } header: {
            Text("Recipe")
        } footer: {
            if dish.chosen == nil && dish.link.result == nil {
                Text("Paste a link from any recipe site — the photo, ingredients and steps come in automatically.")
            }
        }
    }

    private func pick(_ recipe: CDRecipe) {
        dish.chosen = recipe
        dish.title = recipe.title ?? dish.title
        dish.link.clear()
    }
}

private struct MealEditor: View {
    let cell: MealsScreen.MealCell

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(Persistence.self) private var persistence
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDRecipe.lastPlannedAt, order: .reverse), SortDescriptor(\CDRecipe.createdAt, order: .reverse)])
    private var savedRecipes: FetchedResults<CDRecipe>

    @State private var main = DishDraft()
    @State private var sides: [DishDraft] = []
    /// Saved sides taken off in this editor; deleted on Save, kept on Cancel.
    @State private var removedSides: [CDMealSide] = []
    @State private var editingSide: DishDraft?
    @State private var viewingRecipe: CDRecipe?
    @State private var notes = ""
    @State private var existing: CDMeal?
    @State private var recent: [String] = []

    var body: some View {
        NavigationStack {
            Form {
                DishFields(dish: main, placeholder: "e.g. Tacos", savedRecipes: Array(savedRecipes))
                if !recent.isEmpty {
                    Section("Recent") {
                        FlowChips(items: recent) { main.title = $0 }
                    }
                }
                sidesSection
                Section {
                    TextField("Notes (who's cooking…)", text: $notes, axis: .vertical)
                }
                if existing != nil {
                    Section {
                        Button("Clear", systemImage: "trash", role: .destructive) {
                            if let existing { context.delete(existing) }
                            persistence.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle("\(cell.slot.emoji) \(cell.slot.label) · \(DayKey.date(cell.day)?.formatted(.dateTime.weekday(.wide)) ?? "")")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $editingSide) { side in
                Form {
                    DishFields(dish: side, placeholder: "e.g. Garlic bread", savedRecipes: Array(savedRecipes))
                }
                .navigationTitle(side.trimmedTitle.isEmpty ? "Side" : side.trimmedTitle)
                .navigationBarTitleDisplayMode(.inline)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(main.isLoading || sides.contains(where: \.isLoading))
                }
            }
            .onAppear(perform: load)
            .onChange(of: editingSide) { _, new in
                // Back from a new side without filling anything in: drop it.
                if new == nil { sides.removeAll { $0.side == nil && $0.isBlank } }
            }
            .sheet(item: $viewingRecipe) { RecipeView(recipe: $0) }
        }
        .presentationDetents([.large])
    }

    private var sidesSection: some View {
        Section {
            ForEach(sides) { side in
                HStack(spacing: 12) {
                    Button { editingSide = side } label: { SideRow(dish: side) }
                        .buttonStyle(.plain)
                    if let recipe = side.chosen {
                        Button { viewingRecipe = recipe } label: {
                            Image(systemName: "book").font(.title3)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Open the \(side.trimmedTitle) recipe")
                    }
                }
            }
            .onDelete { offsets in
                removedSides += offsets.compactMap { sides[$0].side }
                sides.remove(atOffsets: offsets)
            }
            Button("Add a side", systemImage: "plus.circle") {
                let side = DishDraft()
                sides.append(side)
                editingSide = side
            }
        } header: {
            Text("Sides")
        } footer: {
            if !sides.isEmpty { Text("Only the main dish shows on the calendar.") }
        }
    }

    private func load() {
        existing = MealPlan.meal(day: cell.day, slot: cell.slot, context: context)
        main = DishDraft(title: existing?.title ?? "", chosen: existing?.recipe)
        sides = (existing?.sortedSides ?? []).map { DishDraft(title: $0.title ?? "", chosen: $0.recipe, side: $0) }
        notes = existing?.notes ?? ""

        // Recent meals for this slot, most-used first, for one-tap reuse (ones without a recipe).
        let all = NSFetchRequest<CDMeal>(entityName: "CDMeal")
        all.predicate = NSPredicate(format: "slot == %@ AND recipe == nil", cell.slot.rawValue)
        let counts = ((try? context.fetch(all)) ?? []).compactMap(\.title).filter { !$0.isEmpty }
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        recent = counts.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.prefix(12).map(\.key)
    }

    private func save() {
        let recipe = main.resolveRecipe(persistence: persistence)
        let finalTitle = main.finalTitle(with: recipe)
        if finalTitle.isEmpty {
            if let existing { context.delete(existing) } // its sides go with it
        } else {
            let meal = existing ?? MealPlan.newMeal(day: cell.day, slot: cell.slot, persistence: persistence)
            meal.title = finalTitle
            meal.notes = notes
            meal.recipe = recipe
            recipe?.lastPlannedAt = Date()
            saveSides(on: meal)
        }
        persistence.save()
        dismiss()
    }

    private func saveSides(on meal: CDMeal) {
        removedSides.forEach(context.delete)
        var order: Int16 = 0
        for draft in sides {
            let recipe = draft.resolveRecipe(persistence: persistence)
            let title = draft.finalTitle(with: recipe)
            guard !title.isEmpty else {
                if let saved = draft.side { context.delete(saved) }
                continue
            }
            let side = draft.side ?? {
                let s = persistence.insert(CDMealSide.self)
                s.id = UUID()
                s.createdAt = Date()
                return s
            }()
            if recipe != nil && side.recipe != recipe { recipe?.lastPlannedAt = Date() }
            side.title = title
            side.recipe = recipe
            side.sortOrder = order
            side.meal = meal
            order += 1
        }
    }
}

/// A side in the meal editor's list.
private struct SideRow: View {
    let dish: DishDraft
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 8, style: .continuous) }

    private var image: UIImage? {
        if let data = dish.chosen?.imageData ?? dish.link.result?.image ?? dish.photoData { return UIImage(data: data) }
        return nil
    }

    private var subtitle: String? {
        if let chosen = dish.chosen { return chosen.siteName ?? "Saved recipe" }
        if let result = dish.link.result { return result.recipe.siteName ?? "Recipe from a link" }
        return nil
    }

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Text("🥗")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Palette.accent.opacity(0.12))
                }
            }
            .frame(width: 40, height: 40)
            .clipShape(shape)
            VStack(alignment: .leading, spacing: 2) {
                Text(dish.trimmedTitle.isEmpty ? "New side" : dish.trimmedTitle)
                    .foregroundStyle(dish.trimmedTitle.isEmpty ? Palette.inkSecondary : Palette.ink)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(Palette.inkSecondary).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.hairline)
        }
        .contentShape(Rectangle())
    }
}

private struct RecipeSuggestionRow: View {
    let recipe: CDRecipe
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 8, style: .continuous) }

    var body: some View {
        HStack(spacing: 12) {
            if recipe.imageData != nil {
                RecipePhoto(recipe: recipe).frame(width: 40, height: 40).clipShape(shape)
            } else {
                Text(MealSlot.dinner.emoji).frame(width: 40, height: 40).background(Palette.accent.opacity(0.12), in: shape)
            }
            Text(recipe.title ?? "").foregroundStyle(Palette.ink).lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "plus.circle").foregroundStyle(Palette.accent)
        }
        .contentShape(Rectangle())
        .accessibilityLabel("Use saved recipe \(recipe.title ?? "")")
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
