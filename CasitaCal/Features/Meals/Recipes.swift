import CoreData
import PhotosUI
import SwiftUI

// MARK: - Images

/// Decoded recipe photos, cached so the week grid doesn't re-decode JPEGs on every redraw.
@MainActor
enum RecipeImageCache {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(for recipe: CDRecipe?) -> UIImage? {
        guard let recipe, let data = recipe.imageData else { return nil }
        let key = "\(recipe.objectID.uriRepresentation().absoluteString)-\(data.count)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

/// A recipe photo that fills its frame (cropped), with a soft placeholder when there's none.
struct RecipePhoto: View {
    let recipe: CDRecipe?
    var placeholder = "🍽️"

    var body: some View {
        Group {
            if let image = RecipeImageCache.image(for: recipe) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    Palette.accent.opacity(0.12)
                    Text(placeholder).font(.system(size: 40))
                }
            }
        }
        .clipped()
    }
}

// MARK: - Link import (shared by the meal editor and the recipe box)

/// Paste a link → fetches the recipe and shows a preview.
@MainActor
@Observable
final class LinkImport {
    enum State: Equatable { case idle, loading, failed(String) }

    var text = "" { didSet { if text != oldValue { scheduleFetch() } } }
    private(set) var state: State = .idle
    private(set) var result: (recipe: ParsedRecipe, image: Data?)?
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var lastFetched: URL?

    func clear() {
        task?.cancel()
        text = ""
        result = nil
        lastFetched = nil
        state = .idle
    }

    private func scheduleFetch() {
        guard let url = RecipeImporter.firstLink(in: text), url != lastFetched else {
            if text.isEmpty { state = .idle }
            return
        }
        lastFetched = url
        task?.cancel()
        state = .loading
        task = Task {
            do {
                let fetched = try await RecipeImporter.fetch(url)
                guard !Task.isCancelled else { return }
                result = fetched
                state = .idle
            } catch {
                guard !Task.isCancelled else { return }
                result = nil
                state = .failed(error.localizedDescription)
            }
        }
    }
}

struct LinkImportField: View {
    @Bindable var link: LinkImport

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "link").foregroundStyle(Palette.inkSecondary)
            TextField("Paste a recipe link", text: $link.text)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if link.text.isEmpty {
                PasteButton(payloadType: String.self) { strings in
                    if let s = strings.first { link.text = s }
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.capsule)
            } else if link.state == .loading {
                ProgressView()
            } else {
                Button { link.clear() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.inkSecondary)
            }
        }
        if case let .failed(message) = link.state {
            Label(message, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.orange)
        }
    }
}

/// Compact card for a recipe that's been fetched but not saved yet.
struct ParsedRecipeCard: View {
    let recipe: ParsedRecipe
    let image: Data?

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let image, let ui = UIImage(data: image) {
                    Image(uiImage: ui).resizable().scaledToFill()
                } else {
                    Text("🍽️").font(.largeTitle).frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.accent.opacity(0.12))
                }
            }
            .frame(width: 84, height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(recipe.title).font(.headline).lineLimit(2)
                if let site = recipe.siteName { Text(site).font(.subheadline).foregroundStyle(Palette.inkSecondary) }
                Text(recipe.hasRecipeDetails
                     ? "\(recipe.ingredients.count) ingredients · \(recipe.steps.filter { !$0.hasPrefix("## ") }.count) steps"
                     : "Link and photo only — no recipe details on that page")
                    .font(.caption).foregroundStyle(recipe.hasRecipeDetails ? .green : .orange)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Small card for a saved recipe (horizontal pickers).
struct RecipeChip: View {
    @ObservedObject var recipe: CDRecipe
    var isSelected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RecipePhoto(recipe: recipe)
                .frame(width: 130, height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(isSelected ? Palette.accent : .clear, lineWidth: 3))
            Text(recipe.title ?? "").font(.caption.weight(.semibold)).lineLimit(2).frame(width: 130, alignment: .leading)
        }
    }
}

// MARK: - Recipe view (cooking mode)

struct RecipeView: View {
    @ObservedObject var recipe: CDRecipe
    /// The planned meal's sides, when opened from the plan.
    var sides: [CDMealSide] = []
    /// Shown as "Change meal" when opened from the plan.
    var onEditMeal: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.openURL) private var openURL
    @Environment(Persistence.self) private var persistence
    @State private var checked: Set<Int> = []
    @State private var currentStep: Int?
    @State private var notes = ""
    @State private var addingToList = false
    @State private var openSide: CDRecipe?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if !sides.isEmpty { sidesRow }
                    if recipe.ingredientLines.isEmpty && recipe.stepLines.isEmpty {
                        noDetails
                    } else if sizeClass == .compact {
                        ingredients
                        steps
                    } else {
                        HStack(alignment: .top, spacing: 28) {
                            ingredients.frame(width: 340)
                            steps
                        }
                    }
                    notesField
                }
                .padding(sizeClass == .compact ? 16 : 28)
            }
            .background(Palette.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    if let link = recipe.link {
                        Button("Open website", systemImage: "safari") { openURL(link) }
                    }
                    PlanMenu(recipe: recipe)
                    if let onEditMeal {
                        Button("Change meal", systemImage: "pencil") { onEditMeal() }
                    }
                }
            }
            .onAppear { notes = recipe.notes ?? "" }
            .sheet(isPresented: $addingToList) { AddIngredientsSheet(recipe: recipe) }
            .sheet(item: $openSide) { RecipeView(recipe: $0) }
        }
    }

    /// The meal's sides. Ones with a recipe open it.
    private var sidesRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sides").font(.headline).foregroundStyle(Palette.inkSecondary)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(sides, id: \.objectID) { side in
                        Button { openSide = side.recipe } label: {
                            HStack(spacing: 8) {
                                if side.recipe?.imageData != nil {
                                    RecipePhoto(recipe: side.recipe)
                                        .frame(width: 34, height: 34)
                                        .clipShape(Circle())
                                }
                                Text(side.title ?? "").font(.headline).foregroundStyle(Palette.ink)
                                if side.recipe != nil {
                                    Image(systemName: "chevron.right").font(.caption.weight(.bold)).foregroundStyle(Palette.accent)
                                }
                            }
                            .padding(.leading, side.recipe?.imageData != nil ? 5 : 14)
                            .padding(.trailing, 14)
                            .padding(.vertical, 5)
                            .frame(minHeight: 44)
                            .background(Palette.surface, in: Capsule())
                            .overlay(Capsule().strokeBorder(Palette.hairline))
                        }
                        .buttonStyle(.plain)
                        .allowsHitTesting(side.recipe != nil)
                        .accessibilityLabel(side.recipe == nil ? "Side: \(side.title ?? "")" : "Open the \(side.title ?? "") recipe")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            if recipe.imageData != nil {
                RecipePhoto(recipe: recipe)
                    .frame(maxWidth: .infinity)
                    .frame(height: sizeClass == .compact ? 200 : 300)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            Text(recipe.title ?? "Recipe").font(.system(size: sizeClass == .compact ? 28 : 40, weight: .bold))
            HStack(spacing: 12) {
                if let site = recipe.siteName { Label(site, systemImage: "globe").foregroundStyle(Palette.inkSecondary) }
                if !recipe.timingSummary.isEmpty { Label(recipe.timingSummary, systemImage: "clock").foregroundStyle(Palette.inkSecondary) }
            }
            .font(.headline)
            if let summary = recipe.summary, !summary.isEmpty {
                Text(summary).foregroundStyle(Palette.inkSecondary).lineLimit(4)
            }
        }
    }

    private var ingredients: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Ingredients").font(.title2.weight(.bold))
                Spacer()
                Button { addingToList = true } label: {
                    Label("Add to list…", systemImage: "cart.badge.plus")
                }
                .buttonStyle(.bordered)
                .help("Choose ingredients to add to a Reminders list")
            }
            ForEach(Array(recipe.ingredientLines.enumerated()), id: \.offset) { i, line in
                Button {
                    if checked.contains(i) { checked.remove(i) } else { checked.insert(i) }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: checked.contains(i) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(checked.contains(i) ? Palette.accent : Palette.inkSecondary)
                        Text(line)
                            .strikethrough(checked.contains(i))
                            .foregroundStyle(checked.contains(i) ? Palette.inkSecondary : Palette.ink)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .font(.title3)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Steps").font(.title2.weight(.bold))
            let lines = recipe.stepLines
            let numbers = Self.stepNumbers(lines)
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                if line.hasPrefix("## ") {
                    Text(String(line.dropFirst(3))).font(.headline).foregroundStyle(Palette.accent).padding(.top, 6)
                } else {
                    Button { currentStep = currentStep == i ? nil : i } label: {
                        HStack(alignment: .top, spacing: 14) {
                            Text("\(numbers[i] ?? 0)")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(currentStep == i ? Palette.accent : Palette.inkSecondary.opacity(0.6)))
                            Text(line).font(.title3).foregroundStyle(Palette.ink).multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(currentStep == i ? Palette.accent.opacity(0.12) : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Step numbers that skip section headings.
    static func stepNumbers(_ lines: [String]) -> [Int: Int] {
        var n = 0
        var result: [Int: Int] = [:]
        for (i, line) in lines.enumerated() where !line.hasPrefix("## ") {
            n += 1
            result[i] = n
        }
        return result
    }

    private var noDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This page didn't include the recipe details, so open it on the website.")
                .foregroundStyle(Palette.inkSecondary)
            if let link = recipe.link {
                Button("Open \(recipe.siteName ?? "website")", systemImage: "safari") { openURL(link) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Our notes").font(.title2.weight(.bold))
            TextField("e.g. Double the garlic, kids like it less spicy", text: $notes, axis: .vertical)
                .font(.title3)
                .padding(14)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onChange(of: notes) { _, new in
                    recipe.notes = new
                    persistence.save()
                }
        }
    }
}

/// "Add to Shopping List…": pick which ingredients go on which Reminders list. Nothing starts
/// ticked and nothing is added until "Add" is tapped.
struct AddIngredientsSheet: View {
    @ObservedObject var recipe: CDRecipe
    @Environment(RemindersStore.self) private var reminders
    @Environment(\.dismiss) private var dismiss
    @AppStorage("recipes.ingredientsListID") private var lastListID = ""

    @State private var listID = ""
    @State private var items: [ShoppingItems.Item] = []
    @State private var selected: Set<Int> = []
    @State private var alreadyThere: Set<Int> = []

    private var list: ReminderList? { reminders.allLists.first { $0.id == listID } }

    var body: some View {
        NavigationStack {
            Form {
                if reminders.access != .granted {
                    Section {
                        Button("Connect Reminders") { Task { await reminders.requestAccess(); await prepare() } }
                    } footer: {
                        Text("Ingredients go into one of your Reminders lists, like your shared Shopping List.")
                    }
                } else {
                    Section {
                        Picker("Add to", selection: $listID) {
                            ForEach(reminders.allLists) { Text("\($0.emoji) \($0.title)").tag($0.id) }
                        }
                    }
                    Section {
                        ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                            Button {
                                if selected.contains(i) { selected.remove(i) } else { selected.insert(i) }
                            } label: {
                                HStack {
                                    Image(systemName: selected.contains(i) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected.contains(i) ? Palette.accent : Palette.inkSecondary)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.listTitle).foregroundStyle(Palette.ink)
                                        if alreadyThere.contains(i) {
                                            Text("Looks like it's already on the list").font(.caption).foregroundStyle(.orange)
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        HStack {
                            Text("Ingredients")
                            Spacer()
                            Button(selected.count == items.count ? "None" : "All") {
                                selected = selected.count == items.count ? [] : Set(items.indices)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(selected.count)") {
                        guard let list else { return }
                        let titles = selected.sorted().map { items[$0].listTitle }
                        reminders.addMany(titles, to: list, notes: "For \(recipe.title ?? "a recipe")")
                        lastListID = list.id
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(selected.isEmpty || list == nil)
                }
            }
            .task { await prepare() }
            .onChange(of: listID) { Task { await markExisting() } }
        }
        .presentationDetents([.large])
    }

    private func prepare() async {
        await reminders.reload()
        items = recipe.ingredientLines.map(ShoppingItems.item(from:))
        if listID.isEmpty { listID = reminders.preferredShoppingList(lastUsedID: lastListID)?.id ?? "" }
        await markExisting()
    }

    /// Notes which items already look like they're on the chosen list. Never changes what's ticked.
    private func markExisting() async {
        guard let list else { alreadyThere = []; return }
        let existing = await reminders.openTitles(in: list)
        alreadyThere = Set(items.indices.filter { ShoppingItems.isAlreadyOnList(items[$0], existing: existing) })
    }
}

/// "Plan it" → pick a day in the next two weeks → pick a meal.
struct PlanMenu: View {
    let recipe: CDRecipe
    @Environment(Persistence.self) private var persistence
    @State private var planned: String?

    private var days: [Date] {
        (0..<14).compactMap { Calendar.app.date(byAdding: .day, value: $0, to: Calendar.app.startOfDay(for: Date())) }
    }

    var body: some View {
        Menu {
            ForEach(days, id: \.self) { day in
                Menu(label(day)) {
                    ForEach(MealSlot.allCases) { slot in
                        Button("\(slot.emoji) \(slot.label)") {
                            RecipeImporter.plan(recipe, day: DayKey.from(day), slot: slot.rawValue, persistence: persistence)
                            persistence.save()
                            planned = "\(label(day)) · \(slot.label)"
                        }
                    }
                }
            }
        } label: {
            Label(planned.map { "Planned: \($0)" } ?? "Add to plan", systemImage: planned == nil ? "calendar.badge.plus" : "checkmark")
        }
    }

    private func label(_ day: Date) -> String {
        if Calendar.app.isDateInToday(day) { return "Today" }
        if Calendar.app.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }
}

// MARK: - Recipe box

struct RecipeBox: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var context
    @Environment(Persistence.self) private var persistence
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDRecipe.lastPlannedAt, order: .reverse), SortDescriptor(\CDRecipe.createdAt, order: .reverse)])
    private var recipes: FetchedResults<CDRecipe>

    @State private var search = ""
    @State private var open: CDRecipe?
    @State private var isAdding = false

    private var filtered: [CDRecipe] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Array(recipes) }
        return recipes.filter {
            ($0.title ?? "").localizedCaseInsensitiveContains(q) || ($0.ingredients ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if recipes.isEmpty {
                    ContentUnavailableView {
                        Label("No recipes yet", systemImage: "book.closed")
                    } description: {
                        Text("Paste a recipe link here or when planning a meal. On iPhone, tap Share → CasitaCal in Safari.")
                    } actions: {
                        Button("Add from a link") { isAdding = true }.buttonStyle(.borderedProminent)
                    }
                    .padding(.top, 60)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 18) {
                    ForEach(filtered, id: \.objectID) { recipe in
                        Button { open = recipe } label: { RecipeCard(recipe: recipe) }
                            .buttonStyle(.plain)
                            .contextMenu {
                                PlanMenu(recipe: recipe)
                                Button("Delete recipe", systemImage: "trash", role: .destructive) {
                                    context.delete(recipe)
                                    persistence.save()
                                }
                            }
                    }
                }
                .padding(20)
            }
            .background(Palette.canvas)
            .searchable(text: $search, prompt: "Search recipes or ingredients")
            .navigationTitle("Recipes")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("Add from link", systemImage: "plus") { isAdding = true }
                }
            }
            .sheet(item: $open) { RecipeView(recipe: $0) }
            .sheet(isPresented: $isAdding) { AddRecipeSheet() }
        }
    }
}

extension CDRecipe: Identifiable {}

private struct RecipeCard: View {
    @ObservedObject var recipe: CDRecipe

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RecipePhoto(recipe: recipe)
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(recipe.title ?? "").font(.headline).lineLimit(2).foregroundStyle(Palette.ink)
            Text([recipe.siteName, recipe.timingSummary.isEmpty ? nil : recipe.timingSummary].compactMap { $0 }.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(Palette.inkSecondary)
                .lineLimit(1)
        }
        .padding(10)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.hairline))
    }
}

private struct AddRecipeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Persistence.self) private var persistence
    @State private var link = LinkImport()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LinkImportField(link: link)
                }
                if let result = link.result {
                    Section { ParsedRecipeCard(recipe: result.recipe, image: result.image) }
                }
            }
            .navigationTitle("Add recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let result = link.result {
                            _ = RecipeImporter.save(result.recipe, image: result.image, persistence: persistence)
                            persistence.save()
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(link.result == nil)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
