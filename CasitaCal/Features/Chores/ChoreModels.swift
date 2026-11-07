import Foundation

/// When a chore happens.
struct ChoreRule: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case once
        case daily
        /// Bit (weekday - 1): Sunday = bit 0 … Saturday = bit 6.
        case days(mask: Int)
    }

    var kind: Kind
    /// First day ("yyyy-MM-dd"); for `.once` it's the due day.
    var startDay: String

    static let weekdaysMask = 0b0111110   // Mon–Fri
    static let weekendsMask = 0b1000001   // Sat, Sun

    static func mask(forWeekday weekday: Int) -> Int { 1 << (weekday - 1) }

    /// Is the chore scheduled on `day` (ignoring overdue carry-over)?
    func isScheduled(on day: String, calendar: Calendar = .app) -> Bool {
        guard day >= startDay else { return false } // keys sort chronologically
        switch kind {
        case .once:
            return day == startDay
        case .daily:
            return true
        case let .days(mask):
            guard let date = DayKey.date(day, calendar: calendar) else { return false }
            return mask & Self.mask(forWeekday: calendar.component(.weekday, from: date)) != 0
        }
    }

    var summary: String {
        switch kind {
        case .once:
            let d = DayKey.date(startDay).map { $0.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) } ?? startDay
            return "Once · \(d)"
        case .daily:
            return "Every day"
        case let .days(mask):
            if mask == Self.weekdaysMask { return "Weekdays" }
            if mask == Self.weekendsMask { return "Weekends" }
            if mask == 0b1111111 { return "Every day" }
            let symbols = Calendar.app.shortWeekdaySymbols
            let order = (0..<7).map { (Calendar.app.firstWeekday - 1 + $0) % 7 }
            return order.filter { mask & (1 << $0) != 0 }.map { symbols[$0] }.joined(separator: ", ")
        }
    }
}

enum TimeOfDay: String, CaseIterable, Identifiable, Sendable {
    case morning, afternoon, evening, anytime
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .morning: "sunrise.fill"
        case .afternoon: "sun.max.fill"
        case .evening: "moon.stars.fill"
        case .anytime: "clock"
        }
    }
    var order: Int { TimeOfDay.allCases.firstIndex(of: self) ?? 0 }
}

struct Chore: Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var emoji: String
    /// Empty = anyone can do it.
    var assignees: [UUID]
    var rule: ChoreRule
    var timeOfDay: TimeOfDay
    var stars: Int
    var sortOrder: Int

    var isForAnyone: Bool { assignees.isEmpty }
}

struct ChoreCompletion: Equatable, Sendable {
    var choreID: UUID
    var day: String
    /// nil when the chore is for anyone.
    var memberID: UUID?
}

/// Pure scheduling logic shared by the store and tests.
enum ChoreLogic {
    /// Chores to show in one person's column (or the "Anyone" column when `member` is nil) on `day`.
    /// One-off chores that were missed carry over to today until done.
    static func chores(_ all: [Chore], completions: [ChoreCompletion], member: UUID?, day: String, today: String) -> [Chore] {
        all.filter { chore in
            let belongs = member.map { chore.assignees.contains($0) } ?? chore.isForAnyone
            guard belongs else { return false }
            if chore.rule.isScheduled(on: day) { return true }
            // Overdue one-off: show on today if never done, or done today.
            if case .once = chore.rule.kind, day == today, chore.rule.startDay < today {
                let done = completions.filter { $0.choreID == chore.id && $0.memberID == member }
                return done.isEmpty || done.contains { $0.day == today }
            }
            return false
        }
        .sorted { ($0.timeOfDay.order, $0.sortOrder, $0.title) < ($1.timeOfDay.order, $1.sortOrder, $1.title) }
    }

    static func isDone(_ chore: Chore, member: UUID?, day: String, completions: [ChoreCompletion]) -> Bool {
        completions.contains { $0.choreID == chore.id && $0.memberID == member && $0.day == day }
    }

    /// Stars earned by `member` on the given days.
    static func stars(for member: UUID, days: Set<String>, chores: [Chore], completions: [ChoreCompletion]) -> Int {
        let byID = Dictionary(uniqueKeysWithValues: chores.map { ($0.id, $0) })
        return completions
            .filter { $0.memberID == member && days.contains($0.day) }
            .reduce(0) { $0 + (byID[$1.choreID]?.stars ?? 0) }
    }
}
