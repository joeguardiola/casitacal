import CoreData
import Foundation
import Observation

/// Chores + completions from the household database, as plain values for the UI.
@MainActor
@Observable
final class ChoreStore {
    private(set) var chores: [Chore] = []
    private(set) var completions: [ChoreCompletion] = []

    private let persistence: Persistence
    @ObservationIgnored private var observer: NSObjectProtocol?

    init(persistence: Persistence) {
        self.persistence = persistence
        reload()
        observer = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange, object: persistence.context, queue: .main
        ) { [weak self] note in
            let relevant = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey, NSRefreshedObjectsKey]
                .contains { ((note.userInfo?[$0] as? Set<NSManagedObject>) ?? []).contains { $0 is CDChore || $0 is CDChoreCompletion } }
            guard relevant else { return }
            MainActor.assumeIsolated { self?.reload() }
        }
    }

    func chores(for member: UUID?, on day: Date) -> [Chore] {
        ChoreLogic.chores(chores, completions: completions, member: member,
                          day: DayKey.from(day), today: DayKey.from(Date()))
    }

    func isDone(_ chore: Chore, member: UUID?, on day: Date) -> Bool {
        ChoreLogic.isDone(chore, member: member, day: DayKey.from(day), completions: completions)
    }

    func hasAnyoneChores(on day: Date) -> Bool { !chores(for: nil, on: day).isEmpty }

    /// Stars for the week containing `day`.
    func weeklyStars(for member: UUID, weekOf day: Date) -> Int {
        let week = CalendarRanges.range(for: .week, anchor: day)
        let keys = Set(CalendarRanges.days(in: week).map { DayKey.from($0) })
        return ChoreLogic.stars(for: member, days: keys, chores: chores, completions: completions)
    }

    func toggle(_ chore: Chore, member: UUID?, on day: Date) {
        let key = DayKey.from(day)
        guard let row = fetchChore(chore.id) else { return }
        let existing = (row.completions as? Set<CDChoreCompletion> ?? []).filter {
            $0.day == key && ($0.memberID ?? "") == (member?.uuidString ?? "")
        }
        if existing.isEmpty {
            let c = persistence.insert(CDChoreCompletion.self)
            c.id = UUID()
            c.day = key
            c.memberID = member?.uuidString ?? ""
            c.completedAt = Date()
            c.chore = row
        } else {
            existing.forEach(persistence.context.delete)
        }
        persistence.save()
        reload()
    }

    func save(_ chore: Chore) {
        let row = fetchChore(chore.id) ?? {
            let r = persistence.insert(CDChore.self)
            r.id = chore.id
            r.createdAt = Date()
            r.sortOrder = Int16(chores.count)
            r.household = persistence.household()
            return r
        }()
        row.title = chore.title
        row.emoji = chore.emoji
        row.assigneeIDs = chore.assignees.map(\.uuidString).joined(separator: ",")
        switch chore.rule.kind {
        case .once: row.repeatKind = "once"; row.weekdayMask = 0
        case .daily: row.repeatKind = "daily"; row.weekdayMask = 0
        case let .days(mask): row.repeatKind = "days"; row.weekdayMask = Int16(mask)
        }
        row.startDay = chore.rule.startDay
        row.timeOfDay = chore.timeOfDay.rawValue
        row.stars = Int16(chore.stars)
        persistence.save()
        reload()
    }

    func delete(_ chore: Chore) {
        if let row = fetchChore(chore.id) { persistence.context.delete(row) }
        persistence.save()
        reload()
    }

    // MARK: - Storage

    private func reload() {
        let request = NSFetchRequest<CDChore>(entityName: "CDChore")
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        let rows = (try? persistence.context.fetch(request)) ?? []
        var seen = Set<UUID>()
        chores = rows.compactMap(Self.chore(from:)).filter { seen.insert($0.id).inserted }
        completions = rows.flatMap { row -> [ChoreCompletion] in
            guard let choreID = row.id else { return [] }
            return (row.completions as? Set<CDChoreCompletion> ?? []).compactMap { c in
                guard let day = c.day else { return nil }
                return ChoreCompletion(choreID: choreID, day: day, memberID: UUID(uuidString: c.memberID ?? ""))
            }
        }
    }

    private func fetchChore(_ id: UUID) -> CDChore? {
        let request = NSFetchRequest<CDChore>(entityName: "CDChore")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try? persistence.context.fetch(request).first
    }

    private static func chore(from row: CDChore) -> Chore? {
        guard let id = row.id, let title = row.title, let start = row.startDay else { return nil }
        let kind: ChoreRule.Kind = switch row.repeatKind {
        case "daily": .daily
        case "days": .days(mask: Int(row.weekdayMask))
        default: .once
        }
        return Chore(
            id: id, title: title, emoji: row.emoji ?? "⭐️",
            assignees: (row.assigneeIDs ?? "").split(separator: ",").compactMap { UUID(uuidString: String($0)) },
            rule: ChoreRule(kind: kind, startDay: start),
            timeOfDay: TimeOfDay(rawValue: row.timeOfDay ?? "") ?? .anytime,
            stars: Int(row.stars), sortOrder: Int(row.sortOrder)
        )
    }
}
