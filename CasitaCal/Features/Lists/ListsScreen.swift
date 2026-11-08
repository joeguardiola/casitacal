import SwiftUI

/// Lists backed by Apple Reminders: shared Reminders lists (e.g. "Shopping List")
/// show up here, in the Reminders app, in Siri and on everyone's Apple Watch.
struct ListsScreen: View {
    @Environment(RemindersStore.self) private var reminders
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass

    @AppStorage("lists.selectedReminderList") private var selectedID: String = ""
    @State private var isCreating = false
    @State private var isChoosing = false

    private var selected: ReminderList? {
        reminders.lists.first { $0.id == selectedID } ?? reminders.lists.first
    }

    var body: some View {
        Group {
            switch reminders.access {
            case .notDetermined: AccessPrompt()
            case .denied: AccessDenied()
            case .granted:
                if sizeClass == .compact { phoneBody } else { padBody }
            }
        }
        .task { await reminders.reload() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await reminders.reload() } }
        }
        .sheet(isPresented: $isCreating) {
            NewListSheet { list in selectedID = list.id }
        }
        .sheet(isPresented: $isChoosing) { ChooseListsSheet() }
    }

    // MARK: Phone

    private var phoneBody: some View {
        NavigationStack {
            List {
                ForEach(reminders.lists) { list in
                    NavigationLink {
                        ListDetail(list: list)
                            .navigationBarTitleDisplayMode(.inline)
                            .background(Palette.surface)
                    } label: {
                        ListRow(list: list, remaining: reminders.remainingCount(in: list), isSelected: false)
                    }
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                if reminders.lists.isEmpty { noListsShown }
            }
            .listStyle(.plain)
            .navigationTitle("Lists")
            .toolbar {
                Menu {
                    Button("New list", systemImage: "plus") { isCreating = true }
                    Button("Choose lists…", systemImage: "checklist") { isChoosing = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            .background(Palette.canvas)
        }
    }

    // MARK: iPad

    private var padBody: some View {
        HStack(alignment: .top, spacing: 18) {
            sidebar.frame(width: 280)
            Group {
                if let selected {
                    ListDetail(list: selected).id(selected.id)
                } else {
                    noListsShown
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Palette.hairline))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.canvas)
    }

    private var sidebar: some View {
        VStack(spacing: 10) {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(reminders.lists) { list in
                        ListRow(list: list, remaining: reminders.remainingCount(in: list), isSelected: list == selected)
                            .onTapGesture { selectedID = list.id }
                    }
                }
            }
            HStack(spacing: 10) {
                Button { isCreating = true } label: {
                    Label("New list", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                Button { isChoosing = true } label: {
                    Image(systemName: "checklist")
                        .font(.headline)
                        .padding(.vertical, 12)
                }
                .accessibilityLabel("Choose lists")
            }
            .buttonStyle(.bordered)
            Label("Synced with Apple Reminders", systemImage: "checklist.checked")
                .font(.footnote)
                .foregroundStyle(Palette.inkSecondary)
        }
    }

    private var noListsShown: some View {
        ContentUnavailableView {
            Label("No lists shown", systemImage: "list.bullet.rectangle")
        } description: {
            Text("Pick which Reminders lists appear here — like your shared Shopping List.")
        } actions: {
            Button("Choose lists…") { isChoosing = true }.buttonStyle(.borderedProminent)
        }
    }
}

// MARK: - Rows & detail

private struct ListRow: View {
    let list: ReminderList
    let remaining: Int
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(list.emoji)
                .font(.system(size: 26))
                .frame(width: 44, height: 44)
                .background(Circle().fill(isSelected ? .white.opacity(0.25) : list.color.opacity(0.18)))
            Text(list.title).font(.title3.weight(.semibold)).lineLimit(1)
            Spacer()
            if remaining > 0 {
                Text("\(remaining)")
                    .font(.headline)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Capsule().fill(isSelected ? .white.opacity(0.3) : Palette.sidebar))
            }
        }
        .padding(12)
        .foregroundStyle(isSelected ? .white : Palette.ink)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(isSelected ? Palette.accent : Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(isSelected ? .clear : Palette.hairline))
        .contentShape(Rectangle())
    }
}

private struct ListDetail: View {
    let list: ReminderList

    @Environment(RemindersStore.self) private var reminders
    @State private var newItem = ""
    @State private var confirmClear = false
    @FocusState private var addFocused: Bool

    private var all: [ReminderItem] { reminders.items(in: list) }
    private var open: [ReminderItem] {
        all.filter { !$0.isCompleted }.sorted { ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast) }
    }
    private var done: [ReminderItem] {
        all.filter(\.isCompleted).sorted { ($0.completionDate ?? .distantPast) > ($1.completionDate ?? .distantPast) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(list.emoji).font(.system(size: 36))
                Text(list.title).font(.largeTitle.weight(.bold)).lineLimit(1).minimumScaleFactor(0.7)
                Spacer()
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
                ForEach(open) { item in ItemRow(item: item) { toggle(item) } }
                    .onDelete { offsets in reminders.delete(offsets.map { open[$0] }) }
                if !done.isEmpty {
                    Section {
                        ForEach(done) { item in ItemRow(item: item) { toggle(item) } }
                            .onDelete { offsets in reminders.delete(offsets.map { done[$0] }) }
                    } header: {
                        HStack {
                            Text("Completed (\(done.count))")
                            Spacer()
                            Button("Clear") { confirmClear = true }
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .overlay {
                if all.isEmpty {
                    Text("Nothing on this list").foregroundStyle(Palette.inkSecondary)
                }
            }
            if let error = reminders.lastError {
                Text(error).font(.footnote).foregroundStyle(.red).padding(8)
            }
        }
        .confirmationDialog("Clear \(done.count) completed item\(done.count == 1 ? "" : "s")?",
                            isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear completed", role: .destructive) { withAnimation { reminders.delete(done) } }
        } message: {
            Text("They're removed from “\(list.title)” in Reminders for everyone sharing it.")
        }
    }

    private func add() {
        reminders.add(newItem, to: list)
        newItem = ""
        addFocused = true // keep typing the next item
    }

    private func toggle(_ item: ReminderItem) {
        withAnimation(.snappy) { reminders.toggle(item) }
    }
}

private struct ItemRow: View {
    let item: ReminderItem
    var toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 14) {
                Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 28))
                    .foregroundStyle(item.isCompleted ? Palette.accent : Palette.inkSecondary)
                Text(item.title)
                    .font(.title3)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? Palette.inkSecondary : Palette.ink)
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

// MARK: - Sheets

private struct ChooseListsSheet: View {
    @Environment(RemindersStore.self) private var reminders
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(reminders.allLists) { list in
                        Toggle(isOn: Binding(
                            get: { reminders.isShown(list) },
                            set: { reminders.setShown(list, $0); Task { await reminders.reload() } }
                        )) {
                            HStack(spacing: 10) {
                                Text(list.emoji)
                                Text(list.title)
                                Spacer()
                                Circle().fill(list.color).frame(width: 10, height: 10)
                            }
                        }
                    }
                } footer: {
                    Text("These are your Reminders lists, including ones shared with you. To share a list with someone, open it in the Reminders app and tap Share. This choice is just for this device.")
                }
            }
            .navigationTitle("Lists to show")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.fontWeight(.semibold) }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct NewListSheet: View {
    var onCreate: (ReminderList) -> Void

    @Environment(RemindersStore.self) private var reminders
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text(ReminderList.emoji(for: title)).font(.system(size: 36))
                        TextField("List name", text: $title).font(.title2)
                    }
                } footer: {
                    Text("Creates a new list in Apple Reminders. Share it from the Reminders app to sync it with family.")
                }
            }
            .navigationTitle("New list")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        if let list = reminders.createList(title: title) { onCreate(list) }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Permission screens

private struct AccessPrompt: View {
    @Environment(RemindersStore.self) private var reminders

    var body: some View {
        ContentUnavailableView {
            Label("Use your Reminders lists", systemImage: "checklist")
        } description: {
            Text("CasitaCal shows and edits your Apple Reminders lists — including shared ones like a family Shopping List — so everything stays in sync with Reminders, Siri and everyone's phones.")
        } actions: {
            Button("Connect Reminders") { Task { await reminders.requestAccess() } }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.canvas)
    }
}

private struct AccessDenied: View {
    var body: some View {
        ContentUnavailableView {
            Label("Reminders access is off", systemImage: "checklist.unchecked")
        } description: {
            Text("Turn on Full Access for CasitaCal in Settings → Apps → CasitaCal → Reminders.")
        } actions: {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.canvas)
    }
}
