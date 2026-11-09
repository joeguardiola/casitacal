import SwiftUI

/// Small rotating card next to the weather. Hidden until a topic is turned on in Settings.
struct DailyInfoChip: View {
    @Environment(DailyInfoStore.self) private var daily
    @State private var sheetDay: DailyDay?
    var maxWidth: CGFloat = 200

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
                    .accessibilityLabel("Today: \(item.headline)")
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
        HStack(spacing: 10) {
            Image(systemName: item.topic.symbol)
                .font(.title3)
                .foregroundStyle(item.topic.tint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.topic.shortTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Palette.inkSecondary)
                    .lineLimit(1)
                Text(item.headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minWidth: 170, maxWidth: maxWidth, minHeight: 58, alignment: .leading)
        .background(Palette.surface, in: shape)
        .overlay(shape.strokeBorder(Palette.hairline))
    }

    private func iconOnly(_ item: DailyItem) -> some View {
        Image(systemName: item.topic.symbol)
            .font(.title2)
            .foregroundStyle(item.topic.tint)
            .frame(width: 58, height: 58)
            .background(Palette.surface, in: shape)
            .overlay(shape.strokeBorder(Palette.hairline))
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
    @Environment(GoogleAuth.self) private var auth
    @Environment(MemberStore.self) private var members
    @Environment(\.dismiss) private var dismiss
    @State private var adding: Set<String> = []
    @State private var failure: String?

    private var canAdd: Bool { auth.isSignedIn && events.selectedCalendarId != nil }

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
            .task { await daily.refresh(for: date) }
            .alert("Couldn't add it", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(failure ?? "")
            }
        }
    }

    private func itemCard(_ item: DailyItem) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Label(item.topic.title, systemImage: item.topic.symbol)
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
                ideas("Food ideas", symbol: "fork.knife", item.food)
                ideas("Things to do", symbol: "sparkles", item.activities)
                ideas("Read together", symbol: "book", item.readings)
                ideas("Pray", symbol: "hands.sparkles", item.prayers)
                if let indulgence = item.indulgence { indulgenceNote(indulgence) }
                if let link = item.link {
                    Link(item.linkLabel ?? "Read more", destination: link).font(.subheadline.weight(.semibold))
                    Text("From Wikipedia, CC BY-SA 4.0").font(.caption).foregroundStyle(Palette.inkSecondary)
                }
                if let celebration = item.celebration, canAdd { addButton(celebration) }
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

    @ViewBuilder
    private func addButton(_ c: Celebration) -> some View {
        if DailyInfoStore.isOnCalendar(c.entry.name, day: date, events: events.events) {
            Label("Added to family calendar", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
        } else {
            Button {
                Task { await add(c) }
            } label: {
                if adding.contains(c.id) {
                    ProgressView()
                } else {
                    Label("Add to family calendar", systemImage: "calendar.badge.plus")
                }
            }
            .buttonStyle(.bordered)
            .disabled(adding.contains(c.id))
        }
    }

    private func add(_ c: Celebration) async {
        adding.insert(c.id)
        defer { adding.remove(c.id) }
        let day = Calendar.app.startOfDay(for: date)
        var draft = EventDraft(day: day)
        draft.title = c.entry.name
        draft.isAllDay = true
        draft.start = day
        draft.end = day
        draft.notes = c.entry.blurb
        do {
            try await events.create(draft, members: members.members)
        } catch {
            failure = error.localizedDescription
        }
    }

    @ViewBuilder
    private var comingUp: some View {
        let upcoming = daily.comingUp(after: date)
        if !upcoming.isEmpty {
            Text("Coming up this week")
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

/// The per-device switches for the daily info.
struct DailyInfoSection: View {
    @Environment(DailyInfoStore.self) private var daily
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }

    var body: some View {
        @Bindable var daily = daily
        Section {
            ForEach(DailyTopic.allCases.filter { isPad || $0 == .catholic }) { topic in
                Toggle(topic.title, isOn: Binding(get: { daily.isOn(topic) }, set: { daily.set(topic, on: $0) }))
            }
            if daily.isOn(.catholic) {
                Picker("Which days", selection: $daily.catholicLevel) {
                    ForEach(CatholicLevel.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Show on the calendar", isOn: $daily.showFeastsOnCalendar)
                Picker("Ascension", selection: $daily.ascensionOnSunday) {
                    Text("Sunday").tag(true)
                    Text("Thursday").tag(false)
                }
            }
        } header: {
            Text("Daily info")
        } footer: {
            Text(isPad
                 ? "Chosen topics show next to the weather. Tap for details. Today in history comes from Wikipedia. National days are mostly unofficial, and dates vary by source. Catholic dates follow the U.S. Catholic calendar; Boston, Hartford, New York, Omaha and Philadelphia keep Ascension on Thursday."
                 : "Feast days appear in your schedule when “Show on the calendar” is on. Dates follow the U.S. Catholic calendar; Boston, Hartford, New York, Omaha and Philadelphia keep Ascension on Thursday.")
        }
    }
}
