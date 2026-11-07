import Foundation

enum CalendarMode: String, CaseIterable, Identifiable {
    case day, week, month, schedule
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Date math for each calendar mode.
enum CalendarRanges {
    /// The interval a mode needs loaded for a given anchor date.
    static func range(for mode: CalendarMode, anchor: Date, calendar: Calendar = .app) -> DateInterval {
        switch mode {
        case .day:
            return calendar.dateInterval(of: .day, for: anchor)!
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
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .schedule: .weekOfYear
        }
        return calendar.date(byAdding: component, value: n, to: anchor) ?? anchor
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

/// A timed event placed in a day's time grid.
struct PositionedEvent: Identifiable, Hashable {
    var event: CalendarEvent
    /// Portion of the event inside this day.
    var start: Date
    var end: Date
    var column: Int
    var columnCount: Int
    var id: String { event.id }
}

enum DayLayout {
    /// Events shorter than this still get room to show their title.
    static let minimumDuration: TimeInterval = 30 * 60

    static func allDay(_ events: [CalendarEvent], on day: Date, calendar: Calendar = .app) -> [CalendarEvent] {
        events.filter { $0.isAllDay && $0.overlaps(day: day, calendar: calendar) }
    }

    /// Timed events on `day`, clipped to the day, with side-by-side columns for overlaps.
    static func timed(_ events: [CalendarEvent], on day: Date, calendar: Calendar = .app) -> [PositionedEvent] {
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)!

        let segments = events
            .filter { !$0.isAllDay && $0.overlaps(day: day, calendar: calendar) }
            .map { e in
                PositionedEvent(event: e, start: max(e.start, dayStart), end: min(e.end, dayEnd), column: 0, columnCount: 1)
            }
            .sorted { ($0.start, $1.end) < ($1.start, $0.end) } // earlier first; longer first on ties

        var result: [PositionedEvent] = []
        var cluster: [PositionedEvent] = []
        var columnEnds: [Date] = []
        var clusterEnd = Date.distantPast

        func flush() {
            let count = max(columnEnds.count, 1)
            result += cluster.map { var p = $0; p.columnCount = count; return p }
            cluster = []
            columnEnds = []
        }

        for var seg in segments {
            let visualEnd = max(seg.end, seg.start.addingTimeInterval(minimumDuration))
            if seg.start >= clusterEnd { flush() }
            if let free = columnEnds.firstIndex(where: { $0 <= seg.start }) {
                seg.column = free
                columnEnds[free] = visualEnd
            } else {
                seg.column = columnEnds.count
                columnEnds.append(visualEnd)
            }
            cluster.append(seg)
            clusterEnd = max(clusterEnd, visualEnd)
        }
        flush()
        return result
    }

    /// Everything on a day (all-day first, then by start), for list-style views.
    static func agenda(_ events: [CalendarEvent], on day: Date, calendar: Calendar = .app) -> [CalendarEvent] {
        events
            .filter { $0.overlaps(day: day, calendar: calendar) }
            .sorted { ($0.isAllDay ? 0 : 1, $0.start, $0.title) < ($1.isAllDay ? 0 : 1, $1.start, $1.title) }
    }
}
