import Foundation
import SwiftUI

enum DailyTopic: String, CaseIterable, Identifiable, Sendable {
    case catholic, currentEvent, nationalDay, history, affirmation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .catholic: "Catholic Feast Days"
        case .currentEvent: "Coming Up"
        case .nationalDay: "National and World Days"
        case .history: "Today in History"
        case .affirmation: "A Thought for Today"
        }
    }

    /// Shorter label for the header card.
    var shortTitle: String { self == .nationalDay ? "Today Is" : title }

    /// SF Symbol for every topic but Catholic days, which `TopicIcon` draws as a Latin cross.
    var symbol: String {
        switch self {
        case .catholic: "cross.fill"
        case .currentEvent: "calendar.badge.clock"
        case .nationalDay: "party.popper.fill"
        case .history: "book.closed.fill"
        case .affirmation: "leaf.fill"
        }
    }

    var tint: Color {
        switch self {
        case .catholic: Palette.feast
        case .currentEvent: .blue
        case .nationalDay: Palette.accent
        case .history: .brown
        case .affirmation: .green
        }
    }
}

enum CatholicLevel: String, CaseIterable, Identifiable, Sendable {
    case holyDays, feastDays

    var id: String { rawValue }
    var title: String { self == .holyDays ? "Holy days only" : "Holy days and feast days" }
}

/// Something to show for a day, in the header chip and the detail sheet.
struct DailyItem: Identifiable, Hashable, Sendable {
    var id: String
    var topic: DailyTopic
    var headline: String
    /// Replaces the caption and headline on the header card when the headline alone says too little.
    var cardLine: String?
    var detail: String?
    var story: String?
    var food: [String] = []
    var activities: [String] = []
    var readings: [String] = []
    var prayers: [String] = []
    var indulgence: String?
    var badges: [String] = []
    var note: String?
    var link: URL?
    var linkLabel: String?
    var celebration: Celebration?
}

/// The optional daily info. Everything is off until chosen in Settings, per device.
@MainActor
@Observable
final class DailyInfoStore {
    private enum Key {
        static let topics = "daily.topics"
        static let level = "daily.catholicLevel"
        static let onCalendar = "daily.showFeastsOnCalendar"
        static let ascension = "daily.ascensionOnSunday"
    }

    private let defaults: UserDefaults
    private let session: URLSession

    private(set) var enabledTopics: Set<DailyTopic> {
        didSet { defaults.set(enabledTopics.map(\.rawValue), forKey: Key.topics) }
    }

    var catholicLevel: CatholicLevel {
        didSet { defaults.set(catholicLevel.rawValue, forKey: Key.level) }
    }

    var showFeastsOnCalendar: Bool {
        didSet { defaults.set(showFeastsOnCalendar, forKey: Key.onCalendar) }
    }

    var ascensionOnSunday: Bool {
        didSet {
            defaults.set(ascensionOnSunday, forKey: Key.ascension)
            calendars = [:]
        }
    }

    private(set) var historyByDay: [String: [HistoryFact]] = [:]
    private(set) var remoteEvents: [CurrentEvents.RemoteEvent] = []

    private let feastEntries: [FeastEntry]
    private let nationalDays: [NationalDay]
    private let affirmations: [String]
    @ObservationIgnored private var calendars: [Int: LiturgicalCalendar] = [:]
    @ObservationIgnored private var historyLoading: Set<String> = []
    @ObservationIgnored private var lastRemoteCheck: Date?

    init(defaults: UserDefaults = .standard, session: URLSession = .shared) {
        self.defaults = defaults
        self.session = session
        enabledTopics = Set((defaults.stringArray(forKey: Key.topics) ?? []).compactMap(DailyTopic.init(rawValue:)))
        catholicLevel = defaults.string(forKey: Key.level).flatMap(CatholicLevel.init(rawValue:)) ?? .feastDays
        showFeastsOnCalendar = defaults.bool(forKey: Key.onCalendar)
        ascensionOnSunday = defaults.object(forKey: Key.ascension) as? Bool ?? true
        feastEntries = DailyInfoStore.load("feasts") ?? []
        nationalDays = DailyInfoStore.load("national-days") ?? []
        affirmations = DailyInfoStore.load("affirmations") ?? []
        remoteEvents = Self.readCache("events.json") ?? []
    }

    private static func load<T: Decodable>(_ name: String) -> T? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func isOn(_ topic: DailyTopic) -> Bool { enabledTopics.contains(topic) }

    func set(_ topic: DailyTopic, on: Bool) {
        if on { enabledTopics.insert(topic) } else { enabledTopics.remove(topic) }
    }

    // MARK: Catholic calendar

    private func liturgicalCalendar(_ year: Int) -> LiturgicalCalendar {
        if let c = calendars[year] { return c }
        let c = LiturgicalCalendar(year: year, entries: feastEntries, ascensionOnSunday: ascensionOnSunday)
        calendars[year] = c
        return c
    }

    func celebrations(on date: Date) -> [Celebration] {
        let cal = DailyDates.calendar
        let found = liturgicalCalendar(cal.component(.year, from: date)).celebrations(on: DayKey.from(date, calendar: cal))
        return catholicLevel == .holyDays ? found.filter(\.isHolyDay) : found
    }

    /// All-day calendar items for the feasts in `range`. A real event with the same title wins.
    func feastOverlay(in range: DateInterval, existing: [CalendarEvent]) -> [CalendarEvent] {
        guard isOn(.catholic), showFeastsOnCalendar else { return [] }
        let cal = Calendar.app
        var overlay: [CalendarEvent] = []
        var day = cal.startOfDay(for: range.start)
        while day < range.end {
            guard let next = cal.date(byAdding: .day, value: 1, to: day) else { break }
            for c in celebrations(on: day) where !Self.isOnCalendar(c.entry.name, day: day, events: existing) {
                overlay.append(CalendarEvent(
                    id: "feast-\(c.id)", title: c.entry.name, start: day, end: next, isAllDay: true,
                    location: nil, notes: nil, colorId: nil, taggedMemberIDs: [], recurringEventId: nil, htmlLink: nil,
                    feastOverlayDay: c.dayKey
                ))
            }
            day = next
        }
        return overlay
    }

    static func isOnCalendar(_ title: String, day: Date, events: [CalendarEvent]) -> Bool {
        DayLayout.agenda(events, on: day).contains {
            !$0.isFeastOverlay && $0.title.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    // MARK: Items

    func items(for date: Date) -> [DailyItem] {
        let cal = DailyDates.calendar
        let key = DayKey.from(date, calendar: cal)
        var out: [DailyItem] = []

        if isOn(.catholic) {
            out += celebrations(on: date).map(Self.item)
        }
        if isOn(.currentEvent) {
            out += currentEvents(from: date).map { e, away in
                DailyItem(
                    id: "event-\(e.title)-\(key)", topic: .currentEvent,
                    headline: away == 0 ? e.title : "\(e.title) \(CurrentEvents.whenText(daysAway: away, day: e.day))",
                    detail: e.detail
                )
            }
        }
        if isOn(.nationalDay) {
            out += nationalDays.filter { $0.falls(on: date, calendar: cal) }.map {
                DailyItem(
                    id: "national-\($0.name)", topic: .nationalDay, headline: $0.name,
                    detail: $0.sourceNote, activities: $0.idea.map { [$0] } ?? []
                )
            }
        }
        if isOn(.history), let fact = WikipediaFeed.bestFact(historyByDay[key] ?? []) {
            let short = WikipediaFeed.shortened(fact.text)
            out.append(DailyItem(
                id: "history-\(key)", topic: .history,
                headline: fact.year.map { "On This Day in \(String($0))" } ?? "On This Day",
                cardLine: fact.year.map { "\(String($0)): \(short)" } ?? short,
                detail: fact.text,
                link: fact.pageURL.flatMap(URL.init(string:)),
                linkLabel: "Read more on Wikipedia"
            ))
        }
        if isOn(.affirmation), !affirmations.isEmpty {
            let ordinal = cal.ordinality(of: .day, in: .year, for: date) ?? 1
            out.append(DailyItem(id: "affirmation-\(key)", topic: .affirmation, headline: affirmations[(ordinal - 1) % affirmations.count]))
        }
        return out
    }

    /// Feasts and events in the six days after `date`.
    func comingUp(after date: Date) -> [(day: Date, items: [DailyItem])] {
        let cal = DailyDates.calendar
        return (1...6).compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: date) else { return nil }
            var items = isOn(.catholic) ? celebrations(on: day).map(Self.item) : []
            if isOn(.currentEvent) {
                items += currentEvents(from: day).filter { $0.daysAway == 0 }.map {
                    DailyItem(id: "event-\($0.event.title)", topic: .currentEvent, headline: $0.event.title)
                }
            }
            return items.isEmpty ? nil : (day, items)
        }
    }

    private func currentEvents(from date: Date) -> [(event: CurrentEvents.Event, daysAway: Int)] {
        let cal = DailyDates.calendar
        let year = cal.component(.year, from: date)
        var events = CurrentEvents.yearly(year, calendar: cal) + CurrentEvents.yearly(year + 1, calendar: cal)
        let start = cal.startOfDay(for: date)
        for remote in remoteEvents {
            guard let first = DayKey.date(remote.start, calendar: cal) else { continue }
            let last = remote.end.flatMap { DayKey.date($0, calendar: cal) } ?? first
            // A multi-day event counts from today while it's underway.
            let day = (first <= start && start <= last) ? start : first
            events.append(.init(day: day, title: remote.title, detail: remote.detail))
        }
        return CurrentEvents.upcoming(from: date, horizon: 7, events: events, calendar: cal)
    }

    private static func item(_ c: Celebration) -> DailyItem {
        var badges: [String] = []
        if c.isObligation { badges.append("Holy Day of Obligation") }
        if c.isFastDay { badges.append("Fasting and Abstinence") }
        return DailyItem(
            id: c.id, topic: .catholic, headline: c.entry.name, detail: c.entry.blurb, story: c.entry.story,
            food: c.entry.food ?? [], activities: c.entry.activities ?? [],
            readings: c.entry.readings ?? [], prayers: c.entry.prayers ?? [], indulgence: c.entry.indulgence, badges: badges, note: c.note, celebration: c
        )
    }

    // MARK: Network

    func refresh(for date: Date) async {
        if isOn(.history) { await loadHistory(for: date) }
        if isOn(.currentEvent) { await loadRemoteEvents() }
    }

    private func loadHistory(for date: Date) async {
        let cal = DailyDates.calendar
        let key = DayKey.from(date, calendar: cal)
        guard historyByDay[key] == nil, !historyLoading.contains(key) else { return }
        let file = "history-\(key).json"
        if let cached: [HistoryFact] = Self.readCache(file) {
            historyByDay[key] = cached
            return
        }
        let c = cal.dateComponents([.month, .day], from: date)
        guard let url = WikipediaFeed.url(month: c.month ?? 1, day: c.day ?? 1) else { return }
        historyLoading.insert(key)
        defer { historyLoading.remove(key) }
        guard let data = await fetch(url), let facts = try? WikipediaFeed.parse(data) else { return }
        historyByDay[key] = facts
        Self.writeCache(facts, file)
    }

    private func loadRemoteEvents() async {
        if let last = lastRemoteCheck, Date().timeIntervalSince(last) < 6 * 3600 { return }
        lastRemoteCheck = Date()
        guard let data = await fetch(Self.eventsURL),
              let events = try? JSONDecoder().decode([CurrentEvents.RemoteEvent].self, from: data) else { return }
        remoteEvents = events
        Self.writeCache(events, "events.json")
    }

    private func fetch(_ url: URL) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    private static let userAgent = "CasitaCal/1.0 (https://joeguardiola.github.io/casitacal/)"
    // swiftlint:disable:next force_unwrapping
    private static let eventsURL = URL(string: "https://joeguardiola.github.io/casitacal/daily/events.json")!

    // MARK: Cache

    private static var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: "DailyInfo")
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static func readCache<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: cacheDirectory.appending(path: name)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func writeCache<T: Encodable>(_ value: T, _ name: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: cacheDirectory.appending(path: name), options: .atomic)
    }
}
