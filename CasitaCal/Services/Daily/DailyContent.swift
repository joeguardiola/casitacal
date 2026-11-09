import Foundation

/// "The second Sunday of February" style dates.
struct WeekdayRule: Codable, Hashable, Sendable {
    var month: Int
    /// 1 = Sunday.
    var weekday: Int
    /// 1–4, or -1 for the last one in the month.
    var nth: Int

    func date(year: Int, calendar: Calendar = DailyDates.calendar) -> Date? {
        if nth > 0 {
            return calendar.date(from: DateComponents(year: year, month: month, weekday: weekday, weekdayOrdinal: nth))
        }
        guard let first = calendar.date(from: DateComponents(year: year, month: month + 1, day: 1)) else { return nil }
        for back in 1...7 {
            if let d = calendar.date(byAdding: .day, value: -back, to: first), calendar.component(.weekday, from: d) == weekday {
                return d
            }
        }
        return nil
    }
}

enum DailyDates {
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    static func monthDay(_ date: Date, calendar: Calendar = DailyDates.calendar) -> String {
        let c = calendar.dateComponents([.month, .day], from: date)
        return String(format: "%02d-%02d", c.month ?? 0, c.day ?? 0)
    }
}

struct NationalDay: Codable, Hashable, Sendable {
    var on: String?
    var rule: WeekdayRule?
    var name: String
    var idea: String?
    /// "un" for United Nations days, "food" for unofficial U.S. food days.
    var source: String?

    var sourceNote: String? {
        switch source {
        case "un": "A United Nations international day."
        case "food": "An unofficial U.S. food day."
        default: nil
        }
    }

    func falls(on date: Date, calendar: Calendar = DailyDates.calendar) -> Bool {
        if let on { return on == DailyDates.monthDay(date, calendar: calendar) }
        guard let rule, let d = rule.date(year: calendar.component(.year, from: date), calendar: calendar) else { return false }
        return calendar.isDate(d, inSameDayAs: date)
    }
}

/// Holidays and big yearly moments in the U.S. Anything else lives in the editable events file.
enum CurrentEvents {
    struct Event: Hashable, Sendable {
        var day: Date
        var title: String
        var detail: String?
    }

    /// One row of `docs/daily/events.json`, edited on GitHub without an app update.
    struct RemoteEvent: Codable, Hashable, Sendable {
        var start: String
        var end: String?
        var title: String
        var detail: String?
        var link: String?
    }

    static func yearly(_ year: Int, calendar: Calendar = DailyDates.calendar) -> [Event] {
        func fixed(_ m: Int, _ d: Int, _ title: String, _ detail: String? = nil) -> Event? {
            calendar.date(from: DateComponents(year: year, month: m, day: d)).map { Event(day: $0, title: title, detail: detail) }
        }
        func rule(_ m: Int, _ w: Int, _ n: Int, _ title: String, _ detail: String? = nil) -> Event? {
            WeekdayRule(month: m, weekday: w, nth: n).date(year: year, calendar: calendar).map { Event(day: $0, title: title, detail: detail) }
        }
        var list: [Event?] = [
            fixed(1, 1, "New Year's Day"),
            rule(1, 2, 3, "Martin Luther King Jr. Day"),
            fixed(2, 2, "Groundhog Day"),
            rule(2, 1, 2, "Super Bowl Sunday", "The usual date. Check the kickoff time."),
            rule(2, 2, 3, "Presidents' Day"),
            rule(3, 1, 2, "Daylight saving time starts", "Clocks go forward an hour."),
            rule(5, 1, 2, "Mother's Day"),
            rule(5, 2, -1, "Memorial Day"),
            fixed(6, 14, "Flag Day"),
            rule(6, 1, 3, "Father's Day"),
            fixed(6, 19, "Juneteenth"),
            fixed(7, 4, "Independence Day"),
            rule(9, 2, 1, "Labor Day"),
            rule(10, 2, 2, "Columbus Day"),
            fixed(10, 31, "Halloween"),
            rule(11, 1, 1, "Daylight saving time ends", "Clocks go back an hour."),
            fixed(11, 11, "Veterans Day"),
            rule(11, 5, 4, "Thanksgiving"),
            fixed(12, 31, "New Year's Eve"),
        ]
        if let labor = WeekdayRule(month: 9, weekday: 2, nth: 1).date(year: year, calendar: calendar),
           let sunday = calendar.date(byAdding: .day, value: 6, to: labor) {
            list.append(Event(day: sunday, title: "Grandparents Day"))
        }
        if year.isMultiple(of: 2),
           let monday = WeekdayRule(month: 11, weekday: 2, nth: 1).date(year: year, calendar: calendar),
           let tuesday = calendar.date(byAdding: .day, value: 1, to: monday) {
            list.append(Event(day: tuesday, title: "Election Day"))
        }
        return list.compactMap { $0 }
    }

    /// Events today or within `horizon` days.
    static func upcoming(from day: Date, horizon: Int, events: [Event], calendar: Calendar = DailyDates.calendar) -> [(event: Event, daysAway: Int)] {
        let start = calendar.startOfDay(for: day)
        return events.compactMap { e -> (event: Event, daysAway: Int)? in
            guard let n = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: e.day)).day,
                  n >= 0, n <= horizon else { return nil }
            return (e, n)
        }
        .sorted { $0.daysAway < $1.daysAway }
    }

    static func whenText(daysAway n: Int, day: Date) -> String {
        switch n {
        case 0: "today"
        case 1: "tomorrow"
        default: "on \(day.formatted(.dateTime.weekday(.wide)))"
        }
    }
}

/// One "on this day" entry from Wikipedia.
struct HistoryFact: Codable, Hashable, Sendable {
    var year: Int?
    var text: String
    var pageTitle: String?
    var pageURL: String?
}

enum WikipediaFeed {
    static func url(month: Int, day: Int) -> URL? {
        URL(string: String(format: "https://en.wikipedia.org/api/rest_v1/feed/onthisday/selected/%02d/%02d", month, day))
    }

    private struct Feed: Decodable {
        struct Item: Decodable {
            struct Page: Decodable {
                struct Links: Decodable {
                    struct Desktop: Decodable { var page: String? }
                    var desktop: Desktop?
                }
                var normalizedtitle: String?
                var content_urls: Links?
            }
            var year: Int?
            var text: String
            var pages: [Page]?
        }
        var selected: [Item]
    }

    /// The kitchen iPad is on all day in front of the kids. Keep discoveries, space, inventions and
    /// the arts; better to show nothing than a massacre or the day's politics.
    static func familyFriendly(_ facts: [HistoryFact]) -> [HistoryFact] {
        facts.filter {
            $0.text.range(of: delightWords, options: [.regularExpression, .caseInsensitive]) != nil
                && $0.text.range(of: grimWords, options: [.regularExpression, .caseInsensitive]) == nil
        }
    }

    private static let delightWords = #"\b(discover\w*|invent\w*|patent\w*|launch\w*|telescope|spacecraft|space|nasa|comet|planet\w*|moon|apollo|voyager|astronaut\w*|premier\w*|publish\w*|opened|inaugurated|museum|library|university|national park|olympic\w*|world cup|nobel|symphony|opera|film|novel|album|broadway|musical|bridge|canal|railway|flight|airship|expedition|climb\w*|everest|canoniz\w*|beatif\w*|cathedral|encyclical|painted|painting|first|record)\b"#

    private static let grimWords = #"\b(kill\w*|war|wars|battle\w*|massacre\w*|murder\w*|bomb\w*|attack\w*|assassinat\w*|execut\w*|shot|shoot\w*|dead|death\w*|die|died|dies|dying|bodies|body|genocide|terror\w*|invade\w*|invasion|crash\w*|disaster\w*|earthquake\w*|hijack\w*|nazi\w*|holocaust|slave\w*|slavery|rape\w*|coup|sank|sunk|sink\w*|explo\w*|riot\w*|hanged|lynch\w*|victims?|casualt\w*|plague|pandemic|famine|disappear\w*|sentenc\w*|arrest\w*|prison\w*|jail\w*|military|army|armies|troops?|soldiers?|navy|naval|warship\w*|rebel\w*|revolt\w*|uprising|protest\w*|fires?|flood\w*|hurricane|cyclone|tornado|volcano\w*|erupt\w*|fatal\w*|injur\w*|destroy\w*|abduct\w*|kidnap\w*|hostage\w*|captur\w*|conquer\w*|siege|annex\w*|dictator\w*|banned|ban|election\w*|president\w*|prime minister|parliament|government\w*|court|overthrew|overthrow|deposed|nuclear|weapon\w*|missile\w*|violen\w*|crime\w*|crimin\w*|sex\w*|transvest\w*|transsex\w*|adults|abort\w*|suicide|collapse\w*|derail\w*|mutin\w*|surrender\w*|occup\w*|independence|referendum|constitution\w*)\b"#

    static func parse(_ data: Data) throws -> [HistoryFact] {
        try JSONDecoder().decode(Feed.self, from: data).selected.map { item in
            let page = item.pages?.first
            return HistoryFact(year: item.year, text: item.text, pageTitle: page?.normalizedtitle, pageURL: page?.content_urls?.desktop?.page)
        }
    }
}
