import CoreData
import SwiftUI

/// Shared lists (groceries, to-dos, packing…): lists on the left, items on the right.
struct ListsScreen: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [SortDescriptor(\CDList.sortOrder), SortDescriptor(\CDList.createdAt)])
    private var lists: FetchedResults<CDList>

    @AppStorage("lists.selected") private var selectedID: String = ""
    @State private var naming: NameDraft?

    struct NameDraft: Identifiable {
        var id = UUID()
        var list: CDList?
        var title = ""
        var emoji = "📝"
    }

    private var selected: CDList? {
        lists.first { $0.id?.uuidString == selectedID } ?? lists.first
    }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            sidebar.frame(width: 280)
            Group {
                if let selected {
                    ListDetail(list: selected, onRename: { naming = NameDraft(list: selected, title: selected.title ?? "", emoji: selected.emoji ?? "📝") })
                        .id(selected.objectID)
                } else {
                    ContentUnavailableView("No lists", systemImage: "list.bullet.rectangle", description: Text("Make one for groceries, to-dos or packing."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.hairline))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.canvas)
        .sheet(item: $naming) { draft in
            ListNameSheet(draft: draft) { saved in
                selectedID = saved.id?.uuidString ?? selectedID
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 10) {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(lists, id: \.objectID) { list in
                        ListRow(list: list, isSelected: list == selected)
                            .onTapGesture { selectedID = list.id?.uuidString ?? "" }
                    }
                }
            }
            Button {
                naming = NameDraft()
            } label: {
                Label("New list", systemImage: "plus")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct ListRow: View {
    @ObservedObject var list: CDList
    let isSelected: Bool

    private var remaining: Int {
        (list.items as? Set<CDListItem> ?? []).filter { !$0.isDone }.count
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(list.emoji ?? "📝").font(.system(size: 30))
            Text(list.title ?? "List").font(.title3.weight(.semibold)).lineLimit(1)
            Spacer()
            if remaining > 0 {
                Text("\(remaining)")
                    .font(.headline)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(isSelected ? .white.opacity(0.3) : Palette.sidebar))
            }
        }
        .padding(14)
        .foregroundStyle(isSelected ? .white : Palette.ink)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(isSelected ? Palette.accent : Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(isSelected ? .clear : Palette.hairline))
        .contentShape(Rectangle())
    }
}

private struct ListDetail: View {
    @ObservedObject var list: CDList
    var onRename: () -> Void

    @Environment(\.managedObjectContext) private var context
    @FetchRequest private var items: FetchedResults<CDListItem>
    @State private var newItem = ""
    @State private var confirmDelete = false
    @FocusState private var addFocused: Bool

    init(list: CDList, onRename: @escaping () -> Void) {
        self.list = list
        self.onRename = onRename
        _items = FetchRequest(
            sortDescriptors: [SortDescriptor(\CDListItem.createdAt)],
            predicate: NSPredicate(format: "list == %@", list)
        )
    }

    private var open: [CDListItem] { items.filter { !$0.isDone } }
    private var done: [CDListItem] { items.filter(\.isDone).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(list.emoji ?? "📝").font(.system(size: 36))
                Text(list.title ?? "List").font(.largeTitle.weight(.bold))
                Spacer()
                Menu {
                    Button("Rename", systemImage: "pencil", action: onRename)
                    Button("Delete list", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title)
                }
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 12)

            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill").font(.title2).foregroundStyle(Palette.accent)
                TextField("Add an item", text: $newItem)
                    .font(.title3)
                    .focused($addFocused)
                    .submitLabel(.done)
                    .onSubmit(add)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.canvas))
            .padding(.horizontal, 20)

            List {
                ForEach(open, id: \.objectID) { item in ItemRow(item: item, toggle: { toggle(item) }) }
                    .onDelete { $0.map { open[$0] }.forEach(delete) }
                if !done.isEmpty {
                    Section {
                        ForEach(done, id: \.objectID) { item in ItemRow(item: item, toggle: { toggle(item) }) }
                            .onDelete { $0.map { done[$0] }.forEach(delete) }
                    } header: {
                        HStack {
                            Text("Completed (\(done.count))")
                            Spacer()
                            Button("Clear") { withAnimation { done.forEach(delete) } }
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .overlay {
                if items.isEmpty {
                    Text("Nothing on this list yet").foregroundStyle(Palette.inkSecondary)
                }
            }
        }
        .confirmationDialog("Delete “\(list.title ?? "list")”?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete list and its items", role: .destructive) {
                context.delete(list)
                try? context.save()
            }
        }
    }

    private func add() {
        let title = newItem.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        let item = CDListItem(context: context)
        item.id = UUID()
        item.title = title
        item.createdAt = Date()
        item.list = list
        try? context.save()
        newItem = ""
        addFocused = true // keep typing the next item
    }

    private func toggle(_ item: CDListItem) {
        withAnimation(.snappy) {
            item.isDone.toggle()
            item.completedAt = item.isDone ? Date() : nil
            try? context.save()
        }
    }

    private func delete(_ item: CDListItem) {
        context.delete(item)
        try? context.save()
    }
}

private struct ItemRow: View {
    @ObservedObject var item: CDListItem
    var toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 14) {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 28))
                    .foregroundStyle(item.isDone ? Palette.accent : Palette.inkSecondary)
                Text(item.title ?? "")
                    .font(.title3)
                    .strikethrough(item.isDone)
                    .foregroundStyle(item.isDone ? Palette.inkSecondary : Palette.ink)
                Spacer()
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 4, leading: 24, bottom: 4, trailing: 24))
    }
}

private struct ListNameSheet: View {
    @State var draft: ListsScreen.NameDraft
    var onSave: (CDList) -> Void

    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(HouseholdData.self) private var household

    private let emojis = ["🛒", "✅", "📝", "🎁", "🧳", "🏠", "🔧", "🎄", "🎂", "📦", "💊", "🐾"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(draft.emoji).font(.system(size: 40))
                        TextField("List name", text: $draft.title).font(.title2)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 8) {
                        ForEach(emojis, id: \.self) { e in
                            Text(e).font(.system(size: 30)).frame(width: 46, height: 46)
                                .background(Circle().fill(draft.emoji == e ? Palette.accent.opacity(0.2) : .clear))
                                .onTapGesture { draft.emoji = e }
                        }
                    }
                }
            }
            .navigationTitle(draft.list == nil ? "New list" : "Rename list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let list = draft.list ?? {
                            let l = CDList(context: context)
                            l.id = UUID()
                            l.createdAt = Date()
                            l.sortOrder = Int16.max
                            l.household = household.persistence.household()
                            return l
                        }()
                        list.title = draft.title.trimmingCharacters(in: .whitespaces)
                        list.emoji = draft.emoji
                        try? context.save()
                        onSave(list)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
