import SwiftUI

// MARK: - People picker

/// Tap avatars to choose who an event is for. Empty selection = everyone.
struct PeoplePicker: View {
    @Binding var chosen: [Member.ID]
    var everyoneLabel = "Everyone"
    @Environment(MemberStore.self) private var memberStore
    var avatarSize: CGFloat = 60

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: avatarSize + 32), spacing: 12)], spacing: 14) {
            Button { chosen = [] } label: {
                VStack(spacing: 6) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: avatarSize * 0.36))
                        .foregroundStyle(Palette.family)
                        .frame(width: avatarSize, height: avatarSize)
                        .background(Circle().fill(Palette.family.opacity(0.17)))
                        .overlay(Circle().strokeBorder(Palette.family, lineWidth: chosen.isEmpty ? 4 : 0))
                    Text(everyoneLabel).font(.subheadline.weight(.semibold))
                }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(chosen.isEmpty ? .isSelected : [])

            ForEach(memberStore.members) { m in
                let on = chosen.contains(m.id)
                Button {
                    if on { chosen.removeAll { $0 == m.id } } else { chosen.append(m.id) }
                } label: {
                    VStack(spacing: 6) {
                        ProfileAvatar(member: m, size: avatarSize, isActive: on || chosen.isEmpty)
                            .overlay(alignment: .bottomTrailing) {
                                if on {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title3)
                                        .symbolRenderingMode(.palette)
                                        .foregroundStyle(.white, m.color.strong)
                                }
                            }
                        Text(m.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Add

/// The big "+" sheet: type it like you'd say it, or open the full form.
struct AddEventSheet: View {
    let day: Date
    @Environment(EventStore.self) private var store
    @Environment(MemberStore.self) private var memberStore
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var people: [Member.ID] = []
    @State private var isSaving = false
    @State private var error: String?
    @State private var showForm = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Soccer practice Tuesday 4pm", text: $text, axis: .vertical)
                        .font(.title2)
                        .submitLabel(.done)
                        .onSubmit(quickAdd)
                } header: {
                    Text("What's happening?")
                } footer: {
                    if Calendar.app.isDateInToday(day) {
                        Text("Type it like you'd say it. Google figures out the day and time — e.g. “Dentist Fri 3:30pm”, “Grandma visiting Dec 20–23”.")
                    } else {
                        Text("Type it like you'd say it — e.g. “Soccer 4pm”. With no day in it, it goes on \(day.formatted(.dateTime.weekday(.wide))).")
                    }
                }
                Section("Who's it for?") {
                    PeoplePicker(chosen: $people)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
                Section {
                    Button {
                        showForm = true
                    } label: {
                        Label("More options (times, repeat, location…)", systemImage: "slider.horizontal.3")
                    }
                }
            }
            .navigationTitle(Calendar.app.isDateInToday(day)
                             ? "Add to calendar"
                             : "Add to \(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else {
                        Button("Add", action: quickAdd)
                            .fontWeight(.semibold)
                            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
            .navigationDestination(isPresented: $showForm) {
                EventEditor(mode: .create, draft: {
                    var d = EventDraft(day: day)
                    d.title = text
                    d.people = people
                    return d
                }(), onDone: { dismiss() })
            }
        }
    }

    private func quickAdd() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isSaving else { return }
        isSaving = true
        error = nil
        let chosen = people.compactMap { id in memberStore.members.first { $0.id == id } }
        Task {
            defer { isSaving = false }
            do {
                try await store.quickAdd(EventStore.quickAddText(trimmed, day: day), people: chosen)
                dismiss()
            } catch {
                self.error = "Couldn't add: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Full editor

struct EventEditor: View {
    enum Mode: Equatable {
        case create
        case edit(CalendarEvent)
    }

    let mode: Mode
    @State var draft: EventDraft
    var onDone: () -> Void

    @Environment(EventStore.self) private var store
    @Environment(MemberStore.self) private var memberStore
    @State private var isSaving = false
    @State private var askScope = false
    @State private var error: String?

    private var editingEvent: CalendarEvent? {
        if case let .edit(e) = mode { return e }
        return nil
    }

    var body: some View {
        Form {
            Section {
                TextField("Title", text: $draft.title)
                    .font(.title2)
            }
            Section {
                Toggle("All day", isOn: $draft.isAllDay.animation())
                if draft.isAllDay {
                    DatePicker("Starts", selection: $draft.start, displayedComponents: .date)
                    DatePicker("Ends", selection: $draft.end, in: draft.start..., displayedComponents: .date)
                } else {
                    DatePicker("Starts", selection: $draft.start)
                    DatePicker("Ends", selection: $draft.end, in: draft.start...)
                }
                if let e = editingEvent, e.isRecurring {
                    LabeledContent("Repeat", value: "Repeating — change the pattern in Google Calendar")
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Repeat", selection: $draft.repeatRule) {
                        ForEach(RepeatRule.allCases) { Text($0.label).tag($0) }
                    }
                }
            }
            Section("Who's it for?") {
                PeoplePicker(chosen: $draft.people)
            }
            Section {
                TextField("Location", text: $draft.location)
                TextField("Notes", text: $draft.notes, axis: .vertical)
                    .lineLimit(3...8)
            }
            if let error {
                Section { Text(error).foregroundStyle(.red) }
            }
        }
        .navigationTitle(editingEvent == nil ? "New event" : "Edit event")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving { ProgressView() } else {
                    Button(editingEvent == nil ? "Add" : "Save") {
                        if editingEvent?.isRecurring == true { askScope = true } else { save(allRepeats: false) }
                    }
                    .fontWeight(.semibold)
                    .disabled(!draft.isValid)
                }
            }
        }
        .confirmationDialog("This is a repeating event", isPresented: $askScope, titleVisibility: .visible) {
            Button("Only this event") { save(allRepeats: false) }
            Button("All repeats") { save(allRepeats: true) }
        }
        .onChange(of: draft.start) { old, new in
            // Keep the length when the start moves.
            let length = draft.end.timeIntervalSince(old)
            draft.end = new.addingTimeInterval(max(length, 0))
        }
    }

    private func save(allRepeats: Bool) {
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                if let e = editingEvent {
                    try await store.update(e, with: draft, members: memberStore.members, allRepeats: allRepeats)
                } else {
                    try await store.create(draft, members: memberStore.members)
                }
                onDone()
            } catch {
                self.error = "Couldn't save to Google: \(error.localizedDescription)"
            }
        }
    }
}

// MARK: - Details

/// Tap an event: see details, reassign people, edit or delete.
struct EventDetailSheet: View {
    let event: CalendarEvent
    @Environment(MemberStore.self) private var memberStore
    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var chosen: [Member.ID] = []
    @State private var isSaving = false
    @State private var askScope = false
    @State private var askDelete = false
    @State private var editing = false
    @State private var error: String?

    private var assignment: EventMapper.Assignment {
        EventMapper.assignment(for: event, from: memberStore.members)
    }
    private var original: [Member.ID] { assignment.members.map(\.id) }
    private var hasChanges: Bool { Set(chosen) != Set(original) }
    private var chosenMembers: [Member] {
        chosen.compactMap { id in memberStore.members.first { $0.id == id } }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(event.title)
                            .font(.title.weight(.bold))
                        Text(dateText)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                Section {
                    PeoplePicker(chosen: $chosen)
                } header: {
                    Text("Who's this for?")
                } footer: {
                    if hasChanges {
                        Text("Saving sets the event color in Google, so phones show it too.")
                    } else if let why = assignment.source.explanation {
                        Text(why)
                    } else {
                        Text("Nobody picked, so it shows for everyone.")
                    }
                }
                if let location = event.location, !location.isEmpty {
                    Section("Where") { Text(location) }
                }
                if let notes = event.notes, !notes.isEmpty {
                    Section("Notes") { Text(notes) }
                }
                if event.isRecurring {
                    Section { Label("Repeating event", systemImage: "repeat") }
                }
                Section {
                    Button("Edit event", systemImage: "pencil") { editing = true }
                    if let link = event.htmlLink, let url = URL(string: link) {
                        Button("Open in Google Calendar", systemImage: "arrow.up.right.square") { openURL(url) }
                    }
                    Button("Delete event", systemImage: "trash", role: .destructive) { askDelete = true }
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(hasChanges ? "Cancel" : "Done") { dismiss() }
                }
                if hasChanges {
                    ToolbarItem(placement: .confirmationAction) {
                        if isSaving { ProgressView() } else {
                            Button("Save") {
                                if event.isRecurring { askScope = true } else { assign(allRepeats: false) }
                            }
                            .fontWeight(.semibold)
                        }
                    }
                }
            }
            .confirmationDialog("This is a repeating event", isPresented: $askScope, titleVisibility: .visible) {
                Button("Only this event") { assign(allRepeats: false) }
                Button("All repeats") { assign(allRepeats: true) }
            }
            .confirmationDialog("Delete “\(event.title)”?", isPresented: $askDelete, titleVisibility: .visible) {
                if event.isRecurring {
                    Button("Delete only this event", role: .destructive) { delete(allRepeats: false) }
                    Button("Delete all repeats", role: .destructive) { delete(allRepeats: true) }
                } else {
                    Button("Delete", role: .destructive) { delete(allRepeats: false) }
                }
            } message: {
                Text("It will be removed from everyone's Google Calendar.")
            }
            .navigationDestination(isPresented: $editing) {
                EventEditor(mode: .edit(event), draft: EventDraft(event: event, people: original), onDone: { dismiss() })
            }
            .onAppear { chosen = original }
            .interactiveDismissDisabled(hasChanges)
        }
    }

    private func assign(allRepeats: Bool) {
        run { try await store.assign(event, to: chosenMembers, allRepeats: allRepeats) }
    }

    private func delete(allRepeats: Bool) {
        run { try await store.delete(event, allRepeats: allRepeats) }
    }

    private func run(_ op: @escaping () async throws -> Void) {
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                try await op()
                dismiss()
            } catch {
                self.error = "Couldn't update Google: \(error.localizedDescription)"
            }
        }
    }

    private var dateText: String {
        if event.isAllDay {
            let lastDay = Calendar.app.date(byAdding: .day, value: -1, to: event.end) ?? event.start
            let first = event.start.formatted(.dateTime.weekday(.wide).month(.wide).day())
            return Calendar.app.isDate(lastDay, inSameDayAs: event.start)
                ? "\(first) · All day"
                : "\(first) – \(lastDay.formatted(.dateTime.weekday(.wide).month(.wide).day()))"
        }
        return "\(event.start.formatted(.dateTime.weekday(.wide).month(.wide).day())) · \(event.timeText())"
    }
}
