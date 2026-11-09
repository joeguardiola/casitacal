import CoreData
import PhotosUI
import SwiftUI

/// Weekly meal plan: days across, breakfast/lunch/dinner/snack down.
struct MealsScreen: View {
    @AppStorage(Calendar.weekStartsOnMondayKey) private var weekStartsOnMonday = true
    @AppStorage("meals.showBreakfast") private var showBreakfast = true
    @AppStorage("meals.showLunch") private var showLunch = true
    @AppStorage("meals.showSnack") private var showSnack = false
    @State private var anchor = Date()
    @State private var pageEdge: Edge = .trailing
    @State private var editing: MealCell?
    @State private var viewing: Viewing?
    @State private var showingRecipeBox = false
    @Environment(\.horizontalSizeClass) private var sizeClass

    struct MealCell: Identifiable, Hashable {
        var day: String
        var slot: MealSlot
        var id: String { "\(day)-\(slot.rawValue)" }
    }

    struct Viewing: Identifiable {
        var cell: MealCell
        var recipe: CDRecipe
        var id: String { cell.id }
    }

    /// Planned meals with a recipe open the recipe; everything else opens the editor.
    private func open(_ cell: MealCell, _ meal: CDMeal?) {
        if let recipe = meal?.recipe { viewing = Viewing(cell: cell, recipe: recipe) } else { editing = cell }
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
                Button { showingRecipeBox = true } label: {
                    if sizeClass == .compact {
                        Image(systemName: "book.closed")
                    } else {
                        Label("Recipes", systemImage: "book.closed")
                    }
                }
                .buttonStyle(.bordered).controlSize(.large)
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
            PagedContent(key: days.first, edge: pageEdge) {
                if sizeClass == .compact {
                    MealList(days: days, slots: slots, onOpen: open)
                } else {
                    MealGrid(days: days, slots: slots, onOpen: open)
                }
            }
            .swipeToPage(previous: { shift(-1) }, next: { shift(1) })
        }
        .padding(sizeClass == .compact ? 14 : 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.canvas)
        .sheet(item: $editing) { MealEditor(cell: $0) }
        .sheet(item: $viewing) { v in
            RecipeView(recipe: v.recipe) {
                viewing = nil
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(450))
                    editing = v.cell
                }
            }
        }
        .sheet(isPresented: $showingRecipeBox) { RecipeBox() }
    }

    private var title: String {
        guard let first = days.first, let last = days.last else { return "" }
        return "\(first.formatted(.dateTime.month(.abbreviated).day())) – \(last.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private func shift(_ n: Int) {
        pageEdge = n > 0 ? .trailing : .leading
        Task { @MainActor in
            withAnimation(.snappy) { anchor = CalendarRanges.step(anchor, mode: .week, by: n) }
        }
    }
}

private struct MealGrid: View {
    let days: [Date]
    let slots: [MealSlot]
    var onOpen: (MealsScreen.MealCell, CDMeal?) -> Void

    @FetchRequest private var meals: FetchedResults<CDMeal>

    init(days: [Date], slots: [MealSlot], onOpen: @escaping (MealsScreen.MealCell, CDMeal?) -> Void) {
        self.days = days
        self.slots = slots
        self.onOpen = onOpen
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
                        .frame(width: dayWidth)
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
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 16, style: .continuous) }

    var body: some View {
        Group {
            if let title {
                if isBig && hasPhoto {
                    ZStack(alignment: .bottomLeading) {
                        Color.clear.overlay { RecipePhoto(recipe: meal?.recipe) }
                        LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .center, endPoint: .bottom)
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.white)
                            .lineLimit(3)
                            .padding(10)
                    }
                } else if hasPhoto {
                    HStack(spacing: 8) {
                        RecipePhoto(recipe: meal?.recipe)
                            .frame(width: 44, height: 44)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink).lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .background(Palette.accent.opacity(0.12))
                } else {
                    Text(title)
                        .font(isBig ? .headline : .subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                        .lineLimit(isBig ? 4 : 2)
                        .minimumScaleFactor(0.8)
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

    @FetchRequest private var meals: FetchedResults<CDMeal>

    init(days: [Date], slots: [MealSlot], onOpen: @escaping (MealsScreen.MealCell, CDMeal?) -> Void) {
        self.days = days
        self.slots = slots
        self.onOpen = onOpen
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
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDRecipe.lastPlannedAt, order: .reverse), SortDescriptor(\CDRecipe.createdAt, order: .reverse)])
    private var savedRecipes: FetchedResults<CDRecipe>

    @State private var title = ""
    @State private var notes = ""
    @State private var existing: CDMeal?
    @State private var recent: [String] = []
    @State private var chosen: CDRecipe?
    @State private var link = LinkImport()
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Tacos", text: $title).font(.title2)
                }
                recipeSection
                if !savedRecipes.isEmpty && chosen == nil && link.result == nil {
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
                if !recent.isEmpty {
                    Section("Recent") {
                        FlowChips(items: recent) { title = $0 }
                    }
                }
                Section {
                    TextField("Notes (who's cooking, sides…)", text: $notes, axis: .vertical)
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
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .fontWeight(.semibold)
                        .disabled(link.state == .loading)
                }
            }
            .onAppear(perform: load)
            .onChange(of: link.result?.recipe) { _, new in
                if let new, title.trimmingCharacters(in: .whitespaces).isEmpty { title = new.title }
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                    photoData = RecipeImporter.downscaledJPEG(data)
                }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var recipeSection: some View {
        Section {
            if let chosen {
                HStack(spacing: 12) {
                    RecipeChip(recipe: chosen, isSelected: true)
                    Spacer()
                    Button("Remove", role: .destructive) { self.chosen = nil }
                }
            } else if let result = link.result {
                ParsedRecipeCard(recipe: result.recipe, image: result.image)
                Button("Remove recipe", role: .destructive) { link.clear() }
            } else {
                LinkImportField(link: link)
                PhotosPicker(selection: $photoItem, matching: .images) {
                    if let photoData, let ui = UIImage(data: photoData) {
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
            if chosen == nil && link.result == nil {
                Text("Paste a link from any recipe site — the photo, ingredients and steps come in automatically.")
            }
        }
    }

    private func pick(_ recipe: CDRecipe) {
        chosen = recipe
        title = recipe.title ?? title
        link.clear()
    }

    private func load() {
        let request = NSFetchRequest<CDMeal>(entityName: "CDMeal")
        request.predicate = NSPredicate(format: "day == %@ AND slot == %@", cell.day, cell.slot.rawValue)
        existing = try? context.fetch(request).first
        title = existing?.title ?? ""
        notes = existing?.notes ?? ""
        chosen = existing?.recipe

        // Recent meals for this slot, most-used first, for one-tap reuse (ones without a recipe).
        let all = NSFetchRequest<CDMeal>(entityName: "CDMeal")
        all.predicate = NSPredicate(format: "slot == %@ AND recipe == nil", cell.slot.rawValue)
        let counts = ((try? context.fetch(all)) ?? []).compactMap(\.title).filter { !$0.isEmpty }
            .reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }
        recent = counts.sorted { ($1.value, $0.key) < ($0.value, $1.key) }.prefix(12).map(\.key)
    }

    private func save() {
        var recipe = chosen
        if let result = link.result {
            recipe = RecipeImporter.save(result.recipe, image: result.image, persistence: persistence)
        } else if recipe == nil, let photoData {
            // A meal with just a photo still goes in the recipe box (handy to plan again).
            let r = persistence.insert(CDRecipe.self)
            r.id = UUID()
            r.createdAt = Date()
            r.household = persistence.household()
            r.title = title.trimmingCharacters(in: .whitespaces)
            r.imageData = photoData
            recipe = r
        } else if recipe == nil, let url = RecipeImporter.firstLink(in: link.text) {
            // Site blocked reading: keep the link anyway.
            let r = persistence.insert(CDRecipe.self)
            r.id = UUID()
            r.createdAt = Date()
            r.household = persistence.household()
            r.title = title.trimmingCharacters(in: .whitespaces)
            r.sourceURL = url.absoluteString
            r.siteName = url.host()
            recipe = r
        }

        let trimmed = title.trimmingCharacters(in: .whitespaces)
        let finalTitle = trimmed.isEmpty ? (recipe?.title ?? "") : trimmed
        if finalTitle.isEmpty {
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
            meal.title = finalTitle
            meal.notes = notes
            meal.recipe = recipe
            if let recipe {
                if (recipe.title ?? "").isEmpty { recipe.title = finalTitle }
                recipe.lastPlannedAt = Date()
            }
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
