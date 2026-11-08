import EventKit
import Foundation
import Observation
import SwiftUI

/// A Reminders list (including lists shared with other Apple IDs).
struct ReminderList: Identifiable, Hashable, Sendable {
    let id: String          // EKCalendar.calendarIdentifier
    let title: String
    let colorHex: UInt32

    var color: Color { Color(hex: colorHex) }

    /// A friendly emoji guessed from the list name (Reminders lists don't have one).
    var emoji: String { ReminderList.emoji(for: title) }

    static func emoji(for title: String) -> String {
        let t = title.lowercased()
        let table: [(String, String)] = [
            ("shop", "🛒"), ("grocer", "🛒"), ("costco", "🛒"), ("target", "🎯"), ("food", "🥕"),
            ("to-do", "✅"), ("todo", "✅"), ("to do", "✅"), ("task", "✅"),
            ("pack", "🧳"), ("trip", "🧳"), ("travel", "🧳"), ("gift", "🎁"), ("christmas", "🎄"),
            ("birthday", "🎂"), ("home", "🏠"), ("house", "🏠"), ("fix", "🔧"), ("repair", "🔧"),
            ("pharm", "💊"), ("health", "💊"), ("pet", "🐾"), ("dog", "🐾"), ("cat", "🐾"),
            ("school", "🎒"), ("kid", "🧸"), ("movie", "🎬"), ("book", "📚"), ("recipe", "🍳"),
        ]
        return table.first { t.contains($0.0) }?.1 ?? "📝"
    }
}

/// One reminder, copied out of EventKit so SwiftUI can use it safely.
struct ReminderItem: Identifiable, Hashable, Sendable {
    let id: String          // EKReminder.calendarItemIdentifier
    let listID: String
    let title: String
    let isCompleted: Bool
    let completionDate: Date?
    let creationDate: Date?

    init(_ r: EKReminder) {
        id = r.calendarItemIdentifier
        listID = r.calendar?.calendarIdentifier ?? ""
        title = r.title ?? ""
        isCompleted = r.isCompleted
        completionDate = r.completionDate
        creationDate = r.creationDate
    }
}

/// Apple Reminders as the backing store for the Lists screen.
///
/// Lists and items live in the user's iCloud Reminders, so shared lists (e.g. a
/// "Shopping List" shared with a spouse) work everywhere: Reminders app, Siri,
/// Apple Watch, and here on the kitchen iPad.
@MainActor
@Observable
final class RemindersStore {
    enum Access { case notDetermined, denied, granted }

    private(set) var access: Access
    private(set) var allLists: [ReminderList] = []
    private(set) var items: [String: [ReminderItem]] = [:]
    private(set) var lastError: String?

    /// Lists shown in CasitaCal (per device). nil = never chosen → sensible default.
    private(set) var shownIDs: [String]? {
        didSet { UserDefaults.standard.set(shownIDs, forKey: Self.shownKey) }
    }
    static let shownKey = "lists.reminders.shown"

    /// How long checked-off items stay visible in the Completed section.
    static let completedWindow: TimeInterval = 3 * 24 * 3600

    @ObservationIgnored let store = EKEventStore()
    @ObservationIgnored private var changeObserver: NSObjectProtocol?

    init() {
        access = Self.currentAccess()
        shownIDs = UserDefaults.standard.stringArray(forKey: Self.shownKey)
        changeObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.reload() }
            }
        }
    }

    static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined: .notDetermined
        case .fullAccess: .granted
        default: .denied
        }
    }

    // MARK: - Lists

    /// The lists to show, in Reminders' order.
    var lists: [ReminderList] {
        let ids = shownIDs ?? Self.defaultShown(allLists)
        return allLists.filter { ids.contains($0.id) }
    }

    func isShown(_ list: ReminderList) -> Bool { lists.contains(list) }

    func setShown(_ list: ReminderList, _ shown: Bool) {
        var ids = lists.map(\.id)
        if shown { ids.append(list.id) } else { ids.removeAll { $0 == list.id } }
        shownIDs = ids
    }

    /// First run: shopping/grocery lists if there are any, otherwise everything.
    nonisolated static func defaultShown(_ lists: [ReminderList]) -> [String] {
        let shopping = lists.filter { l in
            let t = l.title.lowercased()
            return ["shop", "grocer"].contains { t.contains($0) }
        }
        return (shopping.isEmpty ? lists : shopping).map(\.id)
    }

    func items(in list: ReminderList) -> [ReminderItem] { items[list.id] ?? [] }

    func remainingCount(in list: ReminderList) -> Int {
        items(in: list).filter { !$0.isCompleted }.count
    }

    // MARK: - Access & loading

    func requestAccess() async {
        do {
            _ = try await store.requestFullAccessToReminders()
        } catch {
            lastError = error.localizedDescription
        }
        access = Self.currentAccess()
        if access == .granted { await reload() }
    }

    func reload() async {
        access = Self.currentAccess()
        guard access == .granted else { return }
        let calendars = store.calendars(for: .reminder)
        allLists = calendars.map {
            ReminderList(id: $0.calendarIdentifier, title: $0.title, colorHex: Self.hex($0.cgColor))
        }

        let shown = calendars.filter { c in lists.contains { $0.id == c.calendarIdentifier } }
        guard !shown.isEmpty else { items = [:]; return }

        let open = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: shown)
        let done = store.predicateForCompletedReminders(
            withCompletionDateStarting: Date().addingTimeInterval(-Self.completedWindow), ending: nil, calendars: shown)
        let fetched = await fetch(open) + fetch(done)
        items = Dictionary(grouping: fetched, by: \.listID)
    }

    private func fetch(_ predicate: NSPredicate) async -> [ReminderItem] {
        await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { reminders in
                cont.resume(returning: (reminders ?? []).map(ReminderItem.init))
            }
        }
    }

    // MARK: - Editing

    func add(_ title: String, to list: ReminderList) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let calendar = store.calendar(withIdentifier: list.id) else { return }
        let r = EKReminder(eventStore: store)
        r.title = title
        r.calendar = calendar
        commit { try store.save(r, commit: true) }
    }

    func toggle(_ item: ReminderItem) {
        guard let r = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        r.isCompleted.toggle()
        commit { try store.save(r, commit: true) }
    }

    func delete(_ items: [ReminderItem]) {
        let reminders = items.compactMap { store.calendarItem(withIdentifier: $0.id) as? EKReminder }
        guard !reminders.isEmpty else { return }
        commit {
            for r in reminders { try store.remove(r, commit: false) }
            try store.commit()
        }
    }

    /// Creates a new Reminders list (in the same account as the default list) and shows it.
    @discardableResult
    func createList(title: String) -> ReminderList? {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty,
              let source = store.defaultCalendarForNewReminders()?.source ?? store.sources.first(where: { $0.sourceType == .calDAV })
        else { return nil }
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = title
        calendar.source = source
        do {
            try store.saveCalendar(calendar, commit: true)
        } catch {
            lastError = "Couldn't create the list: \(error.localizedDescription)"
            return nil
        }
        let list = ReminderList(id: calendar.calendarIdentifier, title: title, colorHex: Self.hex(calendar.cgColor))
        allLists.append(list)
        setShown(list, true)
        Task { await reload() }
        return list
    }

    private func commit(_ work: () throws -> Void) {
        do {
            try work()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            store.reset()
        }
        Task { await reload() }
    }

    private static func hex(_ color: CGColor?) -> UInt32 {
        guard let c = color?.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil),
              let comps = c.components, comps.count >= 3 else { return 0xE87A61 }
        func byte(_ v: CGFloat) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
        return byte(comps[0]) << 16 | byte(comps[1]) << 8 | byte(comps[2])
    }
}
