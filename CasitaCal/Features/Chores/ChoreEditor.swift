import SwiftUI

struct ChoreEditor: View {
    let existing: Chore?
    @Environment(ChoreStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var emoji: String
    @State private var people: [Member.ID]
    @State private var preset: Preset
    @State private var customMask: Int
    @State private var start: Date
    @State private var timeOfDay: TimeOfDay
    @State private var stars: Int
    @State private var confirmDelete = false

    enum Preset: String, CaseIterable, Identifiable {
        case once, daily, weekdays, weekends, weekly, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .once: "Once"
            case .daily: "Every day"
            case .weekdays: "Weekdays"
            case .weekends: "Weekends"
            case .weekly: "Weekly"
            case .custom: "Pick days"
            }
        }
    }

    static let emojiChoices = ["🛏️", "🪥", "🧹", "🧺", "🍽️", "🗑️", "🐶", "🐱", "🌱", "📚", "🎒", "🧸",
                               "🚿", "👕", "🧽", "🪴", "🥣", "🎹", "⚽️", "💊", "🚗", "📬", "⭐️", "✅"]

    init(chore: Chore?, defaultDay: Date) {
        existing = chore
        _title = State(initialValue: chore?.title ?? "")
        _emoji = State(initialValue: chore?.emoji ?? "⭐️")
        _people = State(initialValue: chore?.assignees ?? [])
        _timeOfDay = State(initialValue: chore?.timeOfDay ?? .anytime)
        _stars = State(initialValue: chore?.stars ?? 1)
        let startDate = chore.flatMap { DayKey.date($0.rule.startDay) } ?? defaultDay
        _start = State(initialValue: startDate)
        let weekdayBit = ChoreRule.mask(forWeekday: Calendar.app.component(.weekday, from: startDate))
        switch chore?.rule.kind {
        case .none: _preset = State(initialValue: .daily); _customMask = State(initialValue: weekdayBit)
        case .once: _preset = State(initialValue: .once); _customMask = State(initialValue: weekdayBit)
        case .daily: _preset = State(initialValue: .daily); _customMask = State(initialValue: weekdayBit)
        case let .days(mask):
            let p: Preset = mask == ChoreRule.weekdaysMask ? .weekdays
                : mask == ChoreRule.weekendsMask ? .weekends
                : mask == weekdayBit ? .weekly : .custom
            _preset = State(initialValue: p)
            _customMask = State(initialValue: mask)
        }
    }

    private var rule: ChoreRule {
        let startKey = DayKey.from(start)
        let weekdayBit = ChoreRule.mask(forWeekday: Calendar.app.component(.weekday, from: start))
        let kind: ChoreRule.Kind = switch preset {
        case .once: .once
        case .daily: .daily
        case .weekdays: .days(mask: ChoreRule.weekdaysMask)
        case .weekends: .days(mask: ChoreRule.weekendsMask)
        case .weekly: .days(mask: weekdayBit)
        case .custom: .days(mask: customMask)
        }
        return ChoreRule(kind: kind, startDay: startKey)
    }

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && (preset != .custom || customMask != 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        Text(emoji).font(.system(size: 44))
                        TextField("Chore, e.g. Make bed", text: $title)
                            .font(.title2)
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 8) {
                        ForEach(Self.emojiChoices, id: \.self) { e in
                            Text(e)
                                .font(.system(size: 30))
                                .frame(width: 46, height: 46)
                                .background(Circle().fill(emoji == e ? Palette.accent.opacity(0.2) : .clear))
                                .onTapGesture { emoji = e }
                        }
                    }
                }
                Section {
                    PeoplePicker(chosen: $people, everyoneLabel: "Anyone")
                } header: {
                    Text("Who does it?")
                } footer: {
                    Text(people.count > 1 ? "Each person gets their own copy to check off." : "“Anyone” chores get their own column — whoever does it checks it off.")
                }
                Section("How often") {
                    Picker("Repeat", selection: $preset) {
                        ForEach(Preset.allCases) { Text($0.label).tag($0) }
                    }
                    DatePicker(preset == .once ? "On" : "Starting", selection: $start, displayedComponents: .date)
                    if preset == .custom { weekdayToggles }
                }
                Section("When") {
                    Picker("Time of day", selection: $timeOfDay) {
                        ForEach(TimeOfDay.allCases) { Label($0.label, systemImage: $0.symbol).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Stepper(value: $stars, in: 0...5) {
                        HStack {
                            Text("Stars")
                            Spacer()
                            Text(stars == 0 ? "None" : String(repeating: "★", count: stars)).foregroundStyle(.orange)
                        }
                    }
                }
                if existing != nil {
                    Section {
                        Button("Delete chore", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New chore" : "Edit chore")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(existing == nil ? "Add" : "Save", action: save).fontWeight(.semibold).disabled(!isValid)
                }
            }
            .confirmationDialog("Delete “\(title)”?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let existing { store.delete(existing) }
                    dismiss()
                }
            } message: {
                Text("Its history and stars go too.")
            }
        }
    }

    private var weekdayToggles: some View {
        let cal = Calendar.app
        let order = (0..<7).map { (cal.firstWeekday - 1 + $0) % 7 } // 0 = Sunday
        return HStack(spacing: 8) {
            ForEach(order, id: \.self) { i in
                let on = customMask & (1 << i) != 0
                Button {
                    customMask ^= (1 << i)
                } label: {
                    Text(cal.veryShortWeekdaySymbols[i])
                        .font(.headline)
                        .frame(width: 42, height: 42)
                        .foregroundStyle(on ? .white : Palette.ink)
                        .background(Circle().fill(on ? Palette.accent : Palette.sidebar))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func save() {
        let chore = Chore(
            id: existing?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespaces),
            emoji: emoji, assignees: people, rule: rule,
            timeOfDay: timeOfDay, stars: stars, sortOrder: existing?.sortOrder ?? 0
        )
        store.save(chore)
        dismiss()
    }
}
