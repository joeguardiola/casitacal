import Foundation

enum CalendarMode: String, CaseIterable, Identifiable {
    case week, month, schedule
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Date math for each calendar mode.
enum CalendarRanges {
    /// The interval a mode needs loaded for a given anchor date.
    static func range(for mode: CalendarMode, anchor: Date, calendar: Calendar = .app) -> DateInterval {
        switch mode {
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: anchor)!
        case .month:
            let days = monthGrid(for: anchor, calendar: calendar)
            return DateInterval(start: days.first!, end: calendar.date(byAdding: .day, value: 1, to: days.last!)!)
        case .schedule:
            let start = calendar.startOfDay(for: anchor)
            return DateInterval(start: start, end: calendar.date(byAdding: .day, value: scheduleDays, to: start)!)
        }
    }

    static let scheduleDays = 30

    /// Step the anchor forward/back by one page of the mode.
    static func step(_ anchor: Date, mode: CalendarMode, by n: Int, calendar: Calendar = .app) -> Date {
        let component: Calendar.Component = switch mode {
        case .week: .weekOfYear
        case .month: .month
        case .schedule: .weekOfYear
        }
        return calendar.date(byAdding: component, value: n, to: anchor) ?? anchor
    }

    // MARK: Rolling week (Calendar and Meals; Chores uses real calendar weeks)

    static let defaultRollingDayCount = 5

    /// `count` consecutive days with `start`'s day on the left.
    static func rollingRange(from start: Date, count: Int, calendar: Calendar = .app) -> DateInterval {
        let first = calendar.startOfDay(for: start)
        return DateInterval(start: first, end: calendar.date(byAdding: .day, value: count, to: first)!)
    }

    static func rollingDays(from start: Date, count: Int, calendar: Calendar = .app) -> [Date] {
        days(in: rollingRange(from: start, count: count, calendar: calendar), calendar: calendar)
    }

    /// Move a rolling window forward/back by whole pages of `count` days.
    static func stepRolling(_ anchor: Date, count: Int, by n: Int, calendar: Calendar = .app) -> Date {
        calendar.date(byAdding: .day, value: count * n, to: anchor) ?? anchor
    }

    /// At a new day: a calendar that was showing today follows it; one paged elsewhere stays put.
    static func rolledAnchor(_ anchor: Date, previousToday: Date, now: Date, calendar: Calendar = .app) -> Date {
        calendar.isDate(anchor, inSameDayAs: previousToday) ? now : anchor
    }

    static func days(in interval: DateInterval, calendar: Calendar = .app) -> [Date] {
        var days: [Date] = []
        var d = calendar.startOfDay(for: interval.start)
        while d < interval.end {
            days.append(d)
            d = calendar.date(byAdding: .day, value: 1, to: d)!
        }
        return days
    }

    /// Whole weeks covering the anchor's month (5 or 6 rows of 7 days).
    static func monthGrid(for anchor: Date, calendar: Calendar = .app) -> [Date] {
        let month = calendar.dateInterval(of: .month, for: anchor)!
        let firstWeek = calendar.dateInterval(of: .weekOfYear, for: month.start)!
        let lastDay = calendar.date(byAdding: .day, value: -1, to: month.end)!
        let lastWeek = calendar.dateInterval(of: .weekOfYear, for: lastDay)!
        return days(in: DateInterval(start: firstWeek.start, end: lastWeek.end), calendar: calendar)
    }
}

enum DayLayout {
    static func allDay(_ events: [CalendarEvent], on day: Date, calendar: Calendar = .app) -> [CalendarEvent] {
        events.filter { $0.isAllDay && $0.overlaps(day: day, calendar: calendar) }
    }

    /// Everything on a day (all-day first, then by start), for list-style views.
    /// Feast days go at the bottom of the day, like the dinner on the Week view.
    static func agenda(_ events: [CalendarEvent], on day: Date, calendar: Calendar = .app) -> [CalendarEvent] {
        func rank(_ e: CalendarEvent) -> Int { e.isFeastOverlay ? 2 : (e.isAllDay ? 0 : 1) }
        return events
            .filter { $0.overlaps(day: day, calendar: calendar) }
            .sorted { (rank($0), $0.start, $0.title) < (rank($1), $1.start, $1.title) }
    }
}

/// Month grid sizing: rows share the height, and each shows only the events that fit.
enum MonthCells {
    static let maxChips = 6
    /// Padding (10) plus the date line (26).
    private static let fixedHeight: CGFloat = 36
    /// One event chip plus the gap above it.
    private static let chipPitch: CGFloat = 23

    static func rowHeight(total: CGFloat, rows: Int, spacing: CGFloat) -> CGFloat {
        guard rows > 0 else { return 0 }
        let usable = total - spacing * CGFloat(rows - 1)
        return max(usable / CGFloat(rows), 0)
    }

    static func chipCount(rowHeight: CGFloat) -> Int {
        let fits = Int((rowHeight - fixedHeight) / chipPitch)
        return min(max(fits, 0), maxChips)
    }
}

/// Column widths for the rolling week: equal, or one column double-width.
enum WeekColumns {
    /// Which column is wider. Starts on `.automatic`: today, when today is on screen.
    enum Choice: Equatable {
        case automatic
        case day(Date)
        case equal
    }

    static func widenedIndex(_ choice: Choice, days: [Date], today: Date = .now, calendar: Calendar = .app) -> Int? {
        switch choice {
        case .automatic: days.firstIndex { calendar.isDate($0, inSameDayAs: today) }
        case let .day(day): days.firstIndex { calendar.isDate($0, inSameDayAs: day) }
        case .equal: nil
        }
    }

    /// Tapping the wide column evens them out; tapping any other widens it.
    static func toggled(_ choice: Choice, tapped index: Int, days: [Date], today: Date = .now) -> Choice {
        widenedIndex(choice, days: days, today: today) == index ? .equal : .day(days[index])
    }

    static func widths(total: CGFloat, spacing: CGFloat, count: Int, widened: Int?) -> [CGFloat] {
        guard count > 0 else { return [] }
        let isValid = widened.map { (0..<count).contains($0) } ?? false
        let usable = max(total - spacing * CGFloat(count - 1), 0)
        let unit = usable / CGFloat(count + (isValid ? 1 : 0))
        return (0..<count).map { isValid && $0 == widened ? unit * 2 : unit }
    }
}
