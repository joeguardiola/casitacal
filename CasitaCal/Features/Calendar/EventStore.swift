import Foundation
import Observation

/// The family calendar's events: loaded from Google, cached on the iPad for instant
/// (and offline) display, refreshed every 60s while on screen, and edited in place.
@MainActor
@Observable
final class EventStore {
    private(set) var calendars: [GCalCalendar] = []
    /// Everything cached for the selected calendar (views pick out the days they show).
    private(set) var events: [CalendarEvent] = []
    private(set) var isLoading = false
    private(set) var lastError: String?
    private(set) var lastSynced: Date?
    private(set) var loadedRange: DateInterval?

    var selectedCalendarId: String? {
        didSet {
            guard selectedCalendarId != oldValue else { return }
            defaults.set(selectedCalendarId, forKey: Self.calendarKey)
            loadedRange = nil
            lastSynced = nil
            events = cache.load(calendarId: selectedCalendarId)
        }
    }

    var selectedCalendar: GCalCalendar? { calendars.first { $0.id == selectedCalendarId } }

    private let auth: GoogleAuth
    private let defaults: UserDefaults
    private let cache: EventCache
    private static let calendarKey = "casitacal.familyCalendarId"
    private var client: GoogleCalendarClient {
        GoogleCalendarClient(tokenProvider: { [auth] in try await auth.accessToken() })
    }

    init(auth: GoogleAuth, defaults: UserDefaults = .standard, cache: EventCache = EventCache()) {
        self.auth = auth
        self.defaults = defaults
        self.cache = cache
        let id = defaults.string(forKey: Self.calendarKey)
        self.selectedCalendarId = id
        self.events = cache.load(calendarId: id)
    }

    // MARK: - Reading

    func loadCalendars() async {
        guard auth.isSignedIn else { return }
        do {
            calendars = try await client.calendarList()
                .sorted { ($0.primary == true ? 0 : 1, $0.displayName) < ($1.primary == true ? 0 : 1, $1.displayName) }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Fetch events for `range` and merge them into the cache. Safe to call repeatedly.
    func load(_ range: DateInterval) async {
        guard auth.isSignedIn, let calendarId = selectedCalendarId else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let raw = try await client.events(calendarId: calendarId, from: range.start, to: range.end)
            guard calendarId == selectedCalendarId else { return } // switched calendars mid-request
            let fresh = raw.compactMap { CalendarEvent(google: $0) }
            events = EventCache.merge(fresh, into: events, covering: range)
            cache.save(events, calendarId: calendarId)
            loadedRange = range
            lastSynced = Date()
            lastError = nil
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch let error as URLError {
            // Offline etc.: keep showing the cache, just flag it.
            lastError = error.localizedDescription
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Reload `range` now and then every `interval` until the task is cancelled.
    func keepFresh(_ range: DateInterval, every interval: Duration = .seconds(60)) async {
        while !Task.isCancelled {
            await load(range)
            try? await Task.sleep(for: interval)
        }
    }

    // MARK: - Writing

    func create(_ draft: EventDraft, members: [Member]) async throws {
        let calendarId = try requireCalendar()
        try await client.insertEvent(calendarId: calendarId, draft.body(members: members, includeRecurrence: true))
        await refresh()
    }

    /// Google's natural-language add ("Soccer Tue 4pm"), then tag people if any were picked.
    /// Google's quick add puts an entry with no day ("Soccer 4pm") on today. When the sheet was
    /// opened for another day, name that day, unless the text already gives one.
    nonisolated static func quickAddText(_ text: String, day: Date, now: Date = .now, calendar: Calendar = .app) -> String {
        guard !calendar.isDate(day, inSameDayAs: now) else { return text }
        let words = Set(text.lowercased().split { !$0.isLetter }.map(String.init))
        if !words.isDisjoint(with: ["today", "tonight"]) { return text }
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        // A time alone comes back as today; anything on another day means a day was named.
        let namesADay = detector?.matches(in: text, range: range).contains { match in
            match.date.map { !calendar.isDate($0, inSameDayAs: now) } ?? false
        } ?? false
        if namesADay { return text }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        format.dateFormat = "MMMM d, yyyy"
        return "\(text) on \(format.string(from: day))"
    }

    func quickAdd(_ text: String, people: [Member]) async throws {
        let calendarId = try requireCalendar()
        let created = try await client.quickAdd(calendarId: calendarId, text: text)
        if !people.isEmpty {
            try await client.patchEvent(calendarId: calendarId, eventId: created.id, Self.assignmentPatch(people))
        }
        await refresh()
    }

    func update(_ event: CalendarEvent, with draft: EventDraft, members: [Member], allRepeats: Bool) async throws {
        let calendarId = try requireCalendar()
        if allRepeats, let seriesId = event.recurringEventId {
            // Keep the series' first date; apply the edited time-of-day / length to it.
            let master = try await client.event(calendarId: calendarId, eventId: seriesId)
            guard let masterEvent = CalendarEvent(google: master) else { return }
            let seriesDraft = Self.retime(draft, ontoSeriesStarting: masterEvent.start)
            try await client.updateEvent(calendarId: calendarId, eventId: seriesId,
                                         seriesDraft.body(members: members, includeRecurrence: false))
        } else {
            try await client.updateEvent(calendarId: calendarId, eventId: event.id,
                                         draft.body(members: members, includeRecurrence: !event.isRecurring))
        }
        await refresh()
    }

    func delete(_ event: CalendarEvent, allRepeats: Bool) async throws {
        let calendarId = try requireCalendar()
        let targetId = allRepeats ? (event.recurringEventId ?? event.id) : event.id
        try await client.deleteEvent(calendarId: calendarId, eventId: targetId)
        events.removeAll { $0.id == event.id || (allRepeats && $0.recurringEventId == targetId) }
        cache.save(events, calendarId: calendarId)
        await refresh()
    }

    /// Assign people to an event (from the detail sheet).
    func assign(_ event: CalendarEvent, to people: [Member], allRepeats: Bool) async throws {
        let calendarId = try requireCalendar()
        let targetId = allRepeats ? (event.recurringEventId ?? event.id) : event.id
        try await client.patchEvent(calendarId: calendarId, eventId: targetId, Self.assignmentPatch(people))

        // Show the change right away, then confirm with a fresh load.
        let tagIDs = people.count > 1 ? people.map(\.id) : []
        for i in events.indices where events[i].id == event.id || (allRepeats && events[i].recurringEventId == targetId) {
            events[i].colorId = people.first?.color.googleColorId
            events[i].taggedMemberIDs = tagIDs
        }
        await refresh()
    }

    func reset() {
        cache.clearAll()
        calendars = []
        events = []
        loadedRange = nil
        lastSynced = nil
    }

    // MARK: - Helpers

    /// One person: just the color (a phone can change it later).
    /// Several: first person's color + hidden tag listing everyone. Nobody: calendar color.
    nonisolated static func assignmentPatch(_ people: [Member]) -> GCalEventPatch {
        GCalEventPatch(
            colorId: people.first?.color.googleColorId,
            sharedProperties: [CalendarEvent.membersPropertyKey: people.count > 1 ? people.map(\.id.uuidString).joined(separator: ",") : ""]
        )
    }

    /// Move a draft's time-of-day and length onto the series' original first day.
    nonisolated static func retime(_ draft: EventDraft, ontoSeriesStarting seriesStart: Date, calendar: Calendar = .app) -> EventDraft {
        var d = draft
        let seriesDay = calendar.startOfDay(for: seriesStart)
        if draft.isAllDay {
            let spanDays = calendar.dateComponents([.day], from: calendar.startOfDay(for: draft.start), to: calendar.startOfDay(for: draft.end)).day ?? 0
            d.start = seriesDay
            d.end = calendar.date(byAdding: .day, value: spanDays, to: seriesDay)!
        } else {
            let t = calendar.dateComponents([.hour, .minute], from: draft.start)
            let duration = draft.end.timeIntervalSince(draft.start)
            d.start = calendar.date(bySettingHour: t.hour ?? 0, minute: t.minute ?? 0, second: 0, of: seriesDay)!
            d.end = d.start.addingTimeInterval(duration)
        }
        return d
    }

    private func requireCalendar() throws -> String {
        guard auth.isSignedIn, let id = selectedCalendarId else { throw GoogleCalendarError.notSignedIn }
        return id
    }

    private func refresh() async {
        if let loadedRange { await load(loadedRange) }
    }
}

/// On-device JSON cache of events, one file per calendar, so the screen is never blank.
struct EventCache {
    var directory: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EventCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Keep roughly two months back and four months ahead.
    static let keepWindow: (past: Int, future: Int) = (60, 120)

    func load(calendarId: String?) -> [CalendarEvent] {
        guard let calendarId, let data = try? Data(contentsOf: file(for: calendarId)) else { return [] }
        return (try? JSONDecoder().decode([CalendarEvent].self, from: data)) ?? []
    }

    func save(_ events: [CalendarEvent], calendarId: String) {
        let now = Date()
        let from = now.addingTimeInterval(-Double(Self.keepWindow.past) * 86400)
        let to = now.addingTimeInterval(Double(Self.keepWindow.future) * 86400)
        let trimmed = events.filter { $0.end >= from && $0.start <= to }
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        try? data.write(to: file(for: calendarId), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func clearAll() {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Fresh results are the truth for `range`: drop cached events overlapping it, add the new ones.
    static func merge(_ fresh: [CalendarEvent], into cached: [CalendarEvent], covering range: DateInterval) -> [CalendarEvent] {
        let kept = cached.filter { e in
            let overlaps = e.start == e.end
                ? (e.start >= range.start && e.start < range.end)
                : (e.start < range.end && e.end > range.start)
            return !overlaps
        }
        return (kept + fresh).sorted { ($0.start, $0.end, $0.id) < ($1.start, $1.end, $1.id) }
    }

    private func file(for calendarId: String) -> URL {
        let safe = calendarId.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? String($0) : "_" }.joined()
        return directory.appendingPathComponent("events-\(safe).json")
    }
}
