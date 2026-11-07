import SwiftUI

/// Resolves an event's people and color once, for any view.
struct EventStyle {
    let members: [Member]
    var color: Color { members.first?.color.strong ?? Palette.family }
    var softColor: Color { color.opacity(0.17) }

    init(_ event: CalendarEvent, members all: [Member]) {
        members = EventMapper.members(for: event, from: all)
    }
}

extension CalendarEvent {
    func timeText(on day: Date? = nil, calendar: Calendar = .current) -> String {
        if isAllDay { return "All day" }
        let s = start.formatted(date: .omitted, time: .shortened)
        let e = end.formatted(date: .omitted, time: .shortened)
        return start == end ? s : "\(s) – \(e)"
    }

    var startText: String {
        isAllDay ? "All day" : start.formatted(date: .omitted, time: .shortened)
    }
}

/// Tiny stacked avatars for an event's people.
struct MemberDots: View {
    let members: [Member]
    var size: CGFloat = 20

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(members) { m in
                Text(m.emoji.isEmpty ? m.initial : m.emoji)
                    .font(.system(size: size * 0.55))
                    .frame(width: size, height: size)
                    .background(Circle().fill(Palette.surface))
                    .overlay(Circle().strokeBorder(m.color.strong, lineWidth: 1.5))
            }
        }
    }
}

/// Card used in Week, Schedule and the all-day strips.
struct EventCard: View {
    enum Size { case compact, regular, large }

    let event: CalendarEvent
    let style: EventStyle
    var size: Size = .regular

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 3)
                .fill(style.color)
                .frame(width: 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(event.title)
                    .font(titleFont)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(size == .large ? 3 : 2)
                HStack(spacing: 6) {
                    Text(event.timeText())
                    if size == .large, let location = event.location, !location.isEmpty {
                        Text("·")
                        Text(location).lineLimit(1)
                    }
                }
                .font(detailFont)
                .foregroundStyle(Palette.inkSecondary)
            }
            Spacer(minLength: 0)
            if !style.members.isEmpty {
                MemberDots(members: style.members, size: size == .large ? 28 : 20)
            }
        }
        .padding(.vertical, size == .compact ? 8 : 11)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(style.softColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var titleFont: Font {
        switch size {
        case .compact: .subheadline.weight(.semibold)
        case .regular: .body.weight(.semibold)
        case .large: .title3.weight(.semibold)
        }
    }

    private var detailFont: Font {
        size == .large ? .body : .footnote
    }
}

/// Block drawn inside a time grid (Day view).
struct TimeBlock: View {
    let positioned: PositionedEvent
    let style: EventStyle
    let height: CGFloat

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 2.5)
                .fill(style.color)
                .frame(width: 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(positioned.event.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(height > 60 ? 3 : 1)
                if height > 40 {
                    Text(positioned.event.timeText())
                        .font(.caption)
                        .foregroundStyle(Palette.inkSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if height > 40, !style.members.isEmpty {
                MemberDots(members: style.members, size: 20)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(style.softColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// Event details, with "who's this for?" assignment that saves back to Google.
struct EventDetailSheet: View {
    let event: CalendarEvent
    @Environment(MemberStore.self) private var memberStore
    @Environment(EventStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var chosen: [Member.ID] = []
    @State private var isSaving = false
    @State private var askScope = false
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
                    whoPicker
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
                if let link = event.htmlLink, let url = URL(string: link) {
                    Section {
                        Button("Open in Google Calendar", systemImage: "arrow.up.right.square") { openURL(url) }
                    }
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
                        if isSaving {
                            ProgressView()
                        } else {
                            Button("Save") {
                                if event.isRecurring { askScope = true } else { save(allRepeats: false) }
                            }
                            .fontWeight(.semibold)
                        }
                    }
                }
            }
            .confirmationDialog("This is a repeating event", isPresented: $askScope, titleVisibility: .visible) {
                Button("Only this event") { save(allRepeats: false) }
                Button("All repeats") { save(allRepeats: true) }
            }
            .onAppear { chosen = original }
            .interactiveDismissDisabled(hasChanges)
        }
    }

    private var whoPicker: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 12)], spacing: 14) {
            Button {
                chosen = []
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Palette.family)
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(Palette.family.opacity(0.17)))
                        .overlay(Circle().strokeBorder(Palette.family, lineWidth: chosen.isEmpty ? 4 : 0))
                    Text("Everyone").font(.subheadline.weight(.semibold))
                }
            }
            .buttonStyle(.plain)

            ForEach(memberStore.members) { m in
                let on = chosen.contains(m.id)
                Button {
                    if on { chosen.removeAll { $0 == m.id } } else { chosen.append(m.id) }
                } label: {
                    VStack(spacing: 6) {
                        ProfileAvatar(member: m, size: 60, isActive: on || chosen.isEmpty)
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

    private func save(allRepeats: Bool) {
        isSaving = true
        error = nil
        Task {
            defer { isSaving = false }
            do {
                try await store.assign(event, to: chosenMembers, allRepeats: allRepeats)
                dismiss()
            } catch {
                self.error = "Couldn't save to Google: \(error.localizedDescription)"
            }
        }
    }

    private var dateText: String {
        if event.isAllDay {
            let lastDay = Calendar.current.date(byAdding: .day, value: -1, to: event.end) ?? event.start
            let first = event.start.formatted(.dateTime.weekday(.wide).month(.wide).day())
            return Calendar.current.isDate(lastDay, inSameDayAs: event.start)
                ? "\(first) · All day"
                : "\(first) – \(lastDay.formatted(.dateTime.weekday(.wide).month(.wide).day()))"
        }
        return "\(event.start.formatted(.dateTime.weekday(.wide).month(.wide).day())) · \(event.timeText())"
    }
}
